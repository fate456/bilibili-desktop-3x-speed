#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutFile='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Bili3x.Core.ps1')
$context=Get-BiliContext ''
$privatePaths=@($root,$env:USERPROFILE)+@($context.InstallRoots)+@($context.ResourceDirs)
$privateNames=@($env:USERNAME,$env:COMPUTERNAME)|Where-Object {$_ -and $_.Length -ge 3}
$patterns=@{
    Key='-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
    Credential='(?:sk-(?:proj-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16})'
    Email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    Phone='(?<!\w)1[3-9]\d{9}(?!\w)'
    UserPath='(?i)[A-Z]:[\\/]Users[\\/](?!Public[\\/]|Default[\\/])[^\\/\s"'']+'
}
$issues=New-Object Collections.Generic.List[object]
$count=0;$entries=0
function Inspect-BiliBytes([byte[]]$Bytes,[string]$Label){
    foreach($text in @([Text.Encoding]::UTF8.GetString($Bytes),[Text.Encoding]::Unicode.GetString($Bytes))){
        foreach($path in $privatePaths){if($path -and $text.IndexOf($path,[StringComparison]::OrdinalIgnoreCase) -ge 0){$issues.Add(@{File=$Label;Category='Local path'})}}
        foreach($identity in $privateNames){if($text -match ('(?i)(?<![\w])'+[regex]::Escape($identity)+'(?![\w])')){$issues.Add(@{File=$Label;Category='Local identity'})}}
        foreach($category in $patterns.Keys){if($text -match $patterns[$category]){$issues.Add(@{File=$Label;Category=$category})}}
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$pending=New-Object Collections.Generic.Stack[string];$pending.Push($root)
while($pending.Count){
    foreach($item in (Get-ChildItem -LiteralPath $pending.Pop() -Force)){
        $name=$item.FullName.Substring($root.Length+1).Replace('\','/')
        if($name -eq '.git'){continue}
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){$issues.Add(@{File=$name;Category='Reparse point'});continue}
        if($item.PSIsContainer){$pending.Push($item.FullName);continue}
        $count++
        if($item.Extension -in @('.log','.asar','.backup','.bak','.lnk') -or $item.Name -in @('settings.json','automatic-state.json')){$issues.Add(@{File=$name;Category='Private runtime artifact'})}
        if($item.Extension -eq '.zip'){
            $archive=[IO.Compression.ZipFile]::OpenRead($item.FullName)
            try{foreach($entry in $archive.Entries){if(-not $entry.Name){continue};$entries++;$s=$entry.Open();$memory=New-Object IO.MemoryStream;try{$s.CopyTo($memory);Inspect-BiliBytes $memory.ToArray() ($name+'::'+$entry.FullName)}finally{$s.Dispose();$memory.Dispose()}}}finally{$archive.Dispose()}
        }else{Inspect-BiliBytes ([IO.File]::ReadAllBytes($item.FullName)) $name}
    }
}
$report=@{Version=1;Files=$count;ArchiveEntries=$entries;Findings=@($issues.ToArray());IssueCount=$issues.Count}
if($OutFile){Write-BiliJson ([IO.Path]::GetFullPath($OutFile)) $report}
Write-Host ('Privacy review: '+$count+' files, '+$entries+' archive entries, '+$issues.Count+' findings.')
if($issues.Count){$issues.ToArray()|ForEach-Object{[pscustomobject]$_}|Format-Table;exit 1}
exit 0
