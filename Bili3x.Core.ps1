#Requires -Version 5.1
$script:BiliProjectRoot=$PSScriptRoot
if(-not ('Bili3x.AsarEngine' -as [type])){
    Add-Type -AssemblyName System.Web.Extensions
    Add-Type -Path (Join-Path $PSScriptRoot 'lib\AsarEngine.cs') -ReferencedAssemblies @('System.Web.Extensions','System')
}
function Get-BiliKey([string]$Value){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant()))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Test-BiliUnder([string]$Path,[string]$Root){
    if(-not $Path -or -not $Root){return $false}
    return [IO.Path]::GetFullPath($Path).StartsWith([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Get-BiliDataRoot([string]$Value){
    if(-not $Value){$Value=Join-Path $env:LOCALAPPDATA 'Bili3x'}
    if(-not [IO.Path]::IsPathRooted($Value)){throw 'DataRoot must be an absolute path.'}
    $path=[IO.Path]::GetFullPath($Value).TrimEnd('\')
    if($path -eq [IO.Path]::GetPathRoot($path).TrimEnd('\') -or $path -eq $script:BiliProjectRoot -or (Test-BiliUnder $path $script:BiliProjectRoot)){throw 'Recovery data cannot be a drive root or inside the project.'}
    foreach($broad in @($env:windir,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:USERPROFILE,$env:APPDATA,$env:LOCALAPPDATA,[IO.Path]::GetTempPath())){
        if($broad -and $path -eq [IO.Path]::GetFullPath($broad).TrimEnd('\')){throw 'Recovery data needs a dedicated directory.'}
    }
    if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Recovery directory cannot be a reparse point.'}
    return $path
}
function Write-BiliJson([string]$Path,$Value){
    $dir=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
    $tmp=Join-Path $dir ('.json-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tmp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$Path)}
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function Read-BiliJson([string]$Path){
    if(Test-Path -LiteralPath $Path){return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop}
    return $null
}
function Protect-BiliText([string]$Text,$Context){
    $paths=@($env:USERPROFILE,$script:BiliProjectRoot)
    if($Context){$paths+=@($Context.InstallRoots)+@($Context.ResourceDirs)+@($Context.DataRoot)}
    foreach($path in ($paths|Where-Object{$_}|Sort-Object Length -Descending)){$Text=[regex]::Replace($Text,[regex]::Escape($path),'[LOCAL]',[Text.RegularExpressions.RegexOptions]::IgnoreCase)}
    foreach($name in @($env:USERNAME,$env:COMPUTERNAME)){
        if($name -and $name.Length -ge 3){$Text=[regex]::Replace($Text,'(?i)(?<![\w])'+[regex]::Escape($name)+'(?![\w])','[LOCAL-ID]')}
    }
    return $Text
}
function Write-BiliLog([string]$Message,$Context,[switch]$Quiet){
    $text=Protect-BiliText $Message $Context
    if(-not $Quiet){Write-Host $text}
    $dir=Join-Path $Context.DataRoot 'logs'
    if(-not (Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
    $log=Join-Path $dir 'automatic.log'
    if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB){
        for($i=2;$i -ge 1;$i--){$old=$log+'.'+$i;if(Test-Path -LiteralPath $old){Move-Item -LiteralPath $old -Destination ($log+'.'+($i+1)) -Force}}
        Move-Item -LiteralPath $log -Destination ($log+'.1') -Force
    }
    Add-Content -LiteralPath $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' '+$text) -Encoding UTF8
}
function Get-BiliContext([string]$DataRoot,[string[]]$InstallRoots,[string[]]$ResourceDirs){
    $data=Get-BiliDataRoot $DataRoot
    $settings=Read-BiliJson (Join-Path $data 'settings.json')
    $limited=[bool]($InstallRoots -or $ResourceDirs -or ($settings -and $settings.ExplicitScope))
    $roots=New-Object Collections.Generic.List[string]
    $rootInputs=if($limited){@($InstallRoots)+@($settings.InstallRoots)}else{@($InstallRoots)+@($env:BILI_INSTALL_DIR)+@($settings.InstallRoots)}
    foreach($root in $rootInputs){
        if($root -and [IO.Path]::IsPathRooted($root)){$roots.Add([IO.Path]::GetFullPath($root).TrimEnd('\'))}
    }
    if(-not $limited){foreach($registry in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')){
        foreach($key in (Get-ChildItem -LiteralPath $registry -ErrorAction SilentlyContinue)){
            $v=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if($v.DisplayName -notmatch '^(哔哩哔哩|bilibili)(\s|$)'){continue}
            $root=[string]$v.InstallLocation
            if(-not $root -and $v.DisplayIcon){$icon=([string]$v.DisplayIcon -replace ',\s*-?\d+$','').Trim('"');if([IO.Path]::IsPathRooted($icon)){$root=Split-Path -Parent $icon}}
            if($root -and [IO.Path]::IsPathRooted($root)){$roots.Add([IO.Path]::GetFullPath($root).TrimEnd('\'))}
        }
    }
    foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)})) {if($base){$roots.Add((Join-Path $base 'bilibili'))}}
    $roots.Add((Join-Path $env:LOCALAPPDATA 'Programs\bilibili'))
    }
    $valid=@($roots|Sort-Object -Unique|Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ 'resources\app.asar') -PathType Leaf) -and
        ($_ -ne [IO.Path]::GetPathRoot($_).TrimEnd('\')) -and ($_ -ne $env:ProgramFiles) -and ($_ -ne $env:windir)
    })
    $resources=@($ResourceDirs)+@($settings.ResourceDirs)
    if(-not $limited){$resources+=@((Join-Path $env:APPDATA 'bilibili\resource'),(Join-Path $env:LOCALAPPDATA 'bilibili\resource'))}
    $resources=@($resources|Where-Object{$_ -and [IO.Path]::IsPathRooted($_)}|ForEach-Object{[IO.Path]::GetFullPath($_).TrimEnd('\')}|Sort-Object -Unique)
    return [pscustomobject]@{DataRoot=$data;InstallRoots=$valid;ResourceDirs=$resources;ExplicitScope=$limited}
}
function Get-BiliTargets($Context){
    $found=New-Object Collections.Generic.List[string]
    foreach($root in $Context.InstallRoots){$p=Join-Path $root 'resources\app.asar';if(Test-Path -LiteralPath $p -PathType Leaf){$found.Add($p)}}
    foreach($dir in $Context.ResourceDirs){
        if(Test-Path -LiteralPath $dir -PathType Container){
            foreach($file in (Get-ChildItem -LiteralPath $dir -Filter '*.asar' -File -ErrorAction Stop)){
                if(-not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){$found.Add($file.FullName)}
            }
        }
    }
    return @($found|Sort-Object -Unique)
}
function Test-BiliBusy($Context){
    $roots=@($Context.InstallRoots)+@($Context.ResourceDirs|ForEach-Object{Split-Path -Parent $_})
    foreach($p in @(Get-CimInstance Win32_Process -Property Name,ExecutablePath -ErrorAction Stop)){
        $path=$p.ExecutablePath
        if(-not $path -and $p.Name -match 'bili|哔哩'){return $true}
        foreach($root in $roots){if($path -and (Test-BiliUnder $path $root)){return $true}}
    }
    return $false
}
function Get-BiliSignature([string]$Path){
    $f=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($f.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ASAR cannot be a reparse point.'}
    if($f.PSIsContainer -or $f.Extension -ne '.asar'){throw 'Only regular .asar files are supported.'}
    return '{0}|{1}|{2}' -f $f.Length,$f.LastWriteTimeUtc.Ticks,$f.CreationTimeUtc.Ticks
}
function Get-BiliRecordPath([string]$Path,$Context){return Join-Path (Join-Path (Join-Path $Context.DataRoot 'backups') (Get-BiliKey ([IO.Path]::GetFullPath($Path)))) 'current.json'}
function Assert-BiliIdle($Context){if(Test-BiliBusy $Context){throw '客户端或更新程序仍在运行，已延后；彻底退出后台后会自动处理。'}}
function Copy-BiliSnapshot([string]$Source,[string]$Backup,[string]$Hash){
    if((Test-Path -LiteralPath $Backup) -and ((Get-Item -LiteralPath $Backup).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Recovery snapshot cannot be a reparse point.'}
    if(Test-Path -LiteralPath $Backup){if([Bili3x.AsarEngine]::FileHash($Backup) -ne $Hash){throw 'Recovery snapshot hash mismatch.'};return}
    $dir=Split-Path -Parent $Backup;if(-not (Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    if((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Recovery snapshot directory cannot be a reparse point.'}
    $tmp=Join-Path $dir ([guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::Copy($Source,$tmp,$false)
        if([Bili3x.AsarEngine]::FileHash($tmp) -ne $Hash){throw 'Source changed while saving recovery snapshot.'}
        [IO.File]::Move($tmp,$Backup)
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function Invoke-BiliPatch([string]$Path,$Context){
    $Path=[IO.Path]::GetFullPath($Path);$null=Get-BiliSignature $Path;Assert-BiliIdle $Context
    $info=[Bili3x.AsarEngine]::Inspect($Path)
    if($info.State -eq 'patched'){return 'patched'}
    if($info.State -ne 'original'){throw '新版倍速菜单结构不兼容，已保留原文件，等待适配。'}
    $tmp=Join-Path (Split-Path -Parent $Path) ('.bili3x-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $candidate=[Bili3x.AsarEngine]::BuildCandidate($Path,$tmp)
        $recordPath=Get-BiliRecordPath $Path $Context
        $backup=Join-Path (Split-Path -Parent $recordPath) ($candidate.OriginalHash+'.asar')
        Copy-BiliSnapshot $Path $backup $candidate.OriginalHash
        $record=@{Version=1;Source=$Path;OriginalHash=$candidate.OriginalHash;PatchedHash=$candidate.PatchedHash;Backup=$backup;Phase='prepared'}
        Write-BiliJson $recordPath $record
        Assert-BiliIdle $Context
        if([Bili3x.AsarEngine]::FileHash($Path) -ne $candidate.OriginalHash){throw 'Client updated the package during preparation; retry later.'}
        [IO.File]::Replace($tmp,$Path,[Management.Automation.Language.NullString]::Value)
        if([Bili3x.AsarEngine]::Inspect($Path).State -ne 'patched' -or [Bili3x.AsarEngine]::FileHash($Path) -ne $candidate.PatchedHash){throw 'Post-write verification failed; recovery snapshot retained.'}
        $record.Phase='committed';Write-BiliJson $recordPath $record
        return 'applied'
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function Import-BiliLegacy([string]$Path,$Context){
    $recordPath=Get-BiliRecordPath $Path $Context
    if(Test-Path -LiteralPath $recordPath){return}
    $legacy=$Path+'.backup'
    if(-not (Test-Path -LiteralPath $legacy -PathType Leaf)){return}
    $dir=Join-Path $Context.DataRoot 'legacy-validation';New-Item -ItemType Directory -Path $dir -Force|Out-Null
    $tmp=Join-Path $dir ([guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $candidate=[Bili3x.AsarEngine]::BuildCandidate($legacy,$tmp)
        if([Bili3x.AsarEngine]::FileHash($Path) -ne $candidate.PatchedHash){throw 'Legacy backup does not reproduce this patched version; restoration refused.'}
        $backup=Join-Path (Split-Path -Parent $recordPath) ($candidate.OriginalHash+'.asar')
        Copy-BiliSnapshot $legacy $backup $candidate.OriginalHash
        Write-BiliJson $recordPath @{Version=1;Source=$Path;OriginalHash=$candidate.OriginalHash;PatchedHash=$candidate.PatchedHash;Backup=$backup;Phase='committed'}
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function Invoke-BiliRollback([string]$Path,$Context){
    $Path=[IO.Path]::GetFullPath($Path);$null=Get-BiliSignature $Path;Assert-BiliIdle $Context
    Import-BiliLegacy $Path $Context
    $record=Read-BiliJson (Get-BiliRecordPath $Path $Context)
    if(-not $record){throw 'No verified recovery snapshot for this package.'}
    $dir=Split-Path -Parent (Get-BiliRecordPath $Path $Context)
    if($record.Version -ne 1 -or $record.Source -ne $Path -or $record.OriginalHash -notmatch '^[a-f0-9]{64}$' -or $record.PatchedHash -notmatch '^[a-f0-9]{64}$' -or $record.Backup -ne (Join-Path $dir ($record.OriginalHash+'.asar'))){throw 'Invalid recovery record.'}
    if((Get-Item -LiteralPath $record.Backup).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Recovery snapshot cannot be a reparse point.'}
    if([Bili3x.AsarEngine]::FileHash($record.Backup) -ne $record.OriginalHash){throw 'Recovery snapshot was altered.'}
    $hash=[Bili3x.AsarEngine]::FileHash($Path)
    if($hash -eq $record.OriginalHash){return 'original'}
    if($hash -ne $record.PatchedHash){throw 'Client package changed after patching; refusing to restore an older version.'}
    $tmp=Join-Path (Split-Path -Parent $Path) ('.bili3x-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::Copy($record.Backup,$tmp,$false);Assert-BiliIdle $Context
        if([Bili3x.AsarEngine]::FileHash($Path) -ne $hash){throw 'Package changed during restoration.'}
        [IO.File]::Replace($tmp,$Path,[Management.Automation.Language.NullString]::Value)
        if([Bili3x.AsarEngine]::FileHash($Path) -ne $record.OriginalHash){throw 'Restoration verification failed.'}
        return 'restored'
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
