using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

namespace Bili3x {
    public class ArchiveInfo {
        public long Length, CoreOffset;
        public byte[] Header, Core;
        public string Json, State, OriginalHash, PatchedHash;
        public int[] NodeSpan;
        public int BlockSize;
        public string FileHash;
        public string[] Blocks;
    }
    public static class AsarEngine {
        public const string OldMenu = "static get info(){return[{name:\"2.0x\",value:2},{name:\"1.5x\",value:1.5},{name:\"1.25x\",value:1.25},{name:\"1.0x\",value:1},{name:\"0.75x\",value:.75},{name:\"0.5x\",value:.5}]}";
        const string Prefix = "static get info(){return";
        const string Items = "[{name:\"3.0x\",value:3},{name:\"2.0x\",value:2},{name:\"1.5x\",value:1.5},{name:\"1.25x\",value:1.25},{name:\"1.0x\",value:1},{name:\"0.5x\",value:.5}]";
        public static readonly string NewMenu = Prefix + Items.Substring(0, Items.Length-1) + new string(' ', OldMenu.Length-Prefix.Length-Items.Length-1) + "]}";
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength=64*1024*1024, RecursionLimit=256 }; }
        static byte[] ReadBytes(Stream s, int count) {
            byte[] b=new byte[count]; int n=0;
            while(n<count) { int got=s.Read(b,n,count-n); if(got==0)throw new InvalidDataException("Truncated ASAR."); n+=got; }
            return b;
        }
        static Dictionary<string,object> Obj(object value) {
            var d=value as Dictionary<string,object>; if(d==null)throw new InvalidDataException("Unexpected ASAR object."); return d;
        }
        static object Get(Dictionary<string,object> d, string key) {
            object v; if(!d.TryGetValue(key,out v))throw new InvalidDataException("Missing ASAR field: "+key); return v;
        }
        static int SkipString(string s,int i) {
            if(s[i]!='"')throw new InvalidDataException("Expected JSON string.");
            for(i++;i<s.Length;i++) { if(s[i]=='\\')i++; else if(s[i]=='"')return i+1; }
            throw new InvalidDataException("Unterminated JSON string.");
        }
        static int White(string s,int i) { while(i<s.Length&&char.IsWhiteSpace(s[i]))i++; return i; }
        static int End(string s,int i) {
            if(s[i]=='"')return SkipString(s,i);
            if(s[i]=='{'||s[i]=='[') {
                int depth=0;
                for(;i<s.Length;i++) {
                    if(s[i]=='"') { i=SkipString(s,i)-1;continue; }
                    if(s[i]=='{'||s[i]=='[')depth++;
                    else if(s[i]=='}'||s[i]==']') { if(--depth==0)return i+1; }
                }
                throw new InvalidDataException("Unbalanced JSON.");
            }
            while(i<s.Length&&s[i]!=','&&s[i]!='}'&&s[i]!=']')i++;
            return i;
        }
        static int[] Property(string s,int start,int end,string name) {
            int i=White(s,start);if(s[i]!='{')throw new InvalidDataException("Expected JSON object.");i++;
            int[] result=null;int hits=0;
            while(i<end) {
                i=White(s,i);if(s[i]=='}')break;
                int keyStart=i,keyEnd=SkipString(s,i);
                string key=Serializer().Deserialize<string>(s.Substring(keyStart,keyEnd-keyStart));
                i=White(s,keyEnd);if(s[i++]!=':')throw new InvalidDataException("Expected JSON colon.");
                i=White(s,i);int valueEnd=End(s,i);
                if(key==name) { result=new int[]{i,valueEnd};hits++; }
                i=White(s,valueEnd);if(s[i]==',')i++;else if(s[i]!='}')throw new InvalidDataException("Expected JSON delimiter.");
            }
            if(hits!=1)throw new InvalidDataException("ASAR property missing or ambiguous: "+name);
            return result;
        }
        static string Hash(byte[] b,int start,int count) {
            using(var h=SHA256.Create())return Hex(h.ComputeHash(b,start,count));
        }
        static string Hex(byte[] hash) { return BitConverter.ToString(hash).Replace("-","").ToLowerInvariant(); }
        public static string FileHash(string path) { using(var s=File.OpenRead(path))using(var h=SHA256.Create())return Hex(h.ComputeHash(s)); }
        static void CheckSharedCore(Dictionary<string,object> node,Dictionary<string,object> core,long start,long size) {
            if(node.ContainsKey("files")) { foreach(var child in Obj(node["files"]).Values)CheckSharedCore(Obj(child),core,start,size);return; }
            if(object.ReferenceEquals(node,core)||!node.ContainsKey("offset")||(node.ContainsKey("unpacked")&&Convert.ToBoolean(node["unpacked"])))return;
            long offset=Convert.ToInt64(node["offset"]),length=Convert.ToInt64(Get(node,"size"));
            if(offset<0||length<0)throw new InvalidDataException("Invalid packed file bounds.");
            if(length>0&&offset<start+size&&offset>start-length)throw new InvalidDataException("Core bytes are shared with another packed file; modification refused.");
        }
        static int Count(string text,string needle) {
            int count=0,pos=0;while((pos=text.IndexOf(needle,pos,StringComparison.Ordinal))>=0){count++;pos+=needle.Length;}return count;
        }
        static ArchiveInfo Read(Stream stream) {
            stream.Position=0;byte[] first=ReadBytes(stream,16);
            uint hs=BitConverter.ToUInt32(first,4),js=BitConverter.ToUInt32(first,12);
            if(BitConverter.ToUInt32(first,0)!=4||hs<8||hs>64*1024*1024||hs%4!=0||BitConverter.ToUInt32(first,8)+4!=hs||js>hs-8||hs-8-js>3||8L+hs>stream.Length)throw new InvalidDataException("Invalid ASAR header bounds.");
            byte[] header=ReadBytes(stream,(int)js);string json=Utf8.GetString(header);
            var root=Obj(Serializer().DeserializeObject(json));var node=root;int[] span=new int[]{0,json.Length};
            foreach(string part in new string[]{"files","render","files","assets","files","lib","files","core.js"}) {
                node=Obj(Get(node,part));span=Property(json,span[0],span[1],part);
            }
            if(node.ContainsKey("unpacked")&&Convert.ToBoolean(node["unpacked"]))throw new InvalidDataException("Unpacked core.js is unsupported.");
            long offset;string raw=Convert.ToString(Get(node,"offset"));
            if(!long.TryParse(raw,out offset)||offset<0)throw new InvalidDataException("Invalid core offset.");
            long size=Convert.ToInt64(Get(node,"size"));
            if(size<=0||size>128*1024*1024||Convert.ToDouble(Get(node,"size"))!=size||offset>stream.Length-8L-hs-size)throw new InvalidDataException("Invalid core bounds.");
            CheckSharedCore(root,node,offset,size);
            var integrity=Obj(Get(node,"integrity"));if(Convert.ToString(Get(integrity,"algorithm"))!="SHA256")throw new InvalidDataException("Unsupported integrity algorithm.");
            long bs=Convert.ToInt64(Get(integrity,"blockSize"));if(bs<=0||bs>int.MaxValue||Convert.ToDouble(Get(integrity,"blockSize"))!=bs)throw new InvalidDataException("Invalid integrity block size.");
            var array=Get(integrity,"blocks") as object[];if(array==null||array.Length!=(size+bs-1)/bs)throw new InvalidDataException("Invalid integrity block count.");
            string[] blocks=new string[array.Length];for(int i=0;i<array.Length;i++)blocks[i]=Convert.ToString(array[i]);
            string fileHash=Convert.ToString(Get(integrity,"hash"));
            stream.Position=8L+hs+offset;byte[] core=ReadBytes(stream,(int)size);
            if(!string.Equals(Hash(core,0,core.Length),fileHash,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Core integrity mismatch.");
            for(int i=0;i<blocks.Length;i++)if(!string.Equals(Hash(core,(int)(i*bs),(int)Math.Min(bs,size-i*bs)),blocks[i],StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Core block integrity mismatch.");
            string text=Encoding.ASCII.GetString(core);int old=Count(text,OldMenu),patched=Count(text,NewMenu);
            string state=old==1&&patched==0?"original":patched==1&&old==0?"patched":"unknown";
            return new ArchiveInfo{Length=stream.Length,CoreOffset=8L+hs+offset,Header=header,Json=json,Core=core,NodeSpan=span,BlockSize=(int)bs,FileHash=fileHash,Blocks=blocks,State=state};
        }
        public static ArchiveInfo Inspect(string path) { using(var s=File.OpenRead(path))return Read(s); }
        static void ReplaceValue(ArchiveInfo info,int[] span,string old,string value) {
            string literal=info.Json.Substring(span[0],span[1]-span[0]);
            if(literal!="\""+old+"\"")throw new InvalidDataException("Noncanonical integrity hash.");
            byte[] b=Encoding.ASCII.GetBytes("\""+value+"\"");int start=Utf8.GetByteCount(info.Json.Substring(0,span[0]));
            if(b.Length!=Utf8.GetByteCount(literal))throw new InvalidDataException("Integrity replacement changes length.");
            Buffer.BlockCopy(b,0,info.Header,start,b.Length);
        }
        public static ArchiveInfo BuildCandidate(string source,string target) {
            using(var input=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                ArchiveInfo info=Read(input);if(info.State!="original")throw new InvalidDataException("Menu pattern is unsupported or already patched.");
                input.Position=0;using(var h=SHA256.Create())info.OriginalHash=Hex(h.ComputeHash(input));
                string text=Encoding.ASCII.GetString(info.Core);byte[] replacement=Encoding.ASCII.GetBytes(NewMenu);
                Buffer.BlockCopy(replacement,0,info.Core,text.IndexOf(OldMenu,StringComparison.Ordinal),replacement.Length);
                int[] integ=Property(info.Json,info.NodeSpan[0],info.NodeSpan[1],"integrity");
                ReplaceValue(info,Property(info.Json,integ[0],integ[1],"hash"),info.FileHash,Hash(info.Core,0,info.Core.Length));
                int[] blockSpan=Property(info.Json,integ[0],integ[1],"blocks");int pos=White(info.Json,blockSpan[0]+1);
                for(int i=0;i<info.Blocks.Length;i++) {
                    int end=SkipString(info.Json,pos);
                    ReplaceValue(info,new int[]{pos,end},info.Blocks[i],Hash(info.Core,i*info.BlockSize,(int)Math.Min(info.BlockSize,info.Core.Length-(long)i*info.BlockSize)));
                    pos=White(info.Json,end);if(info.Json[pos]==',')pos=White(info.Json,pos+1);
                }
                input.Position=0;
                using(var output=new FileStream(target,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None)) {
                    input.CopyTo(output,1024*1024);output.Position=16;output.Write(info.Header,0,info.Header.Length);
                    output.Position=info.CoreOffset;output.Write(info.Core,0,info.Core.Length);output.Flush(true);
                }
                var check=Inspect(target);if(check.State!="patched"||check.Length!=info.Length)throw new InvalidDataException("Candidate verification failed.");
                info.PatchedHash=FileHash(target);return info;
            }
        }
    }
}
