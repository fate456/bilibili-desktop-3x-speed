#Requires -Version 5.1
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'Bili3x.Core.ps1')
. (Join-Path $project 'Bili3x.Automatic.ps1')
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('Bili3xTests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox -Force|Out-Null
$checks=New-Object Collections.Generic.List[string]
$watcher=$null;$busyProcess=$null;$installedData=$null
function Assert-BiliTest($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Expect-BiliFailure([scriptblock]$Body){$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Assert-BiliTest $failed 'Expected refusal.'}
function Pass-BiliTest([string]$Message){$checks.Add($Message);Write-Host ('PASS '+$Message)}
function New-AsarFixture([string]$Path,[string]$Version='one',[string]$Menu=[Bili3x.AsarEngine]::OldMenu,[switch]$Shared){
    $core=[Text.Encoding]::UTF8.GetBytes(('/* 中文内容 '+$Version+' */'+$Menu+';'))
    $sha=[Security.Cryptography.SHA256]::Create();try{$hash=[BitConverter]::ToString($sha.ComputeHash($core)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $node=[ordered]@{size=$core.Length;offset='0';integrity=[ordered]@{algorithm='SHA256';hash=$hash;blockSize=4194304;blocks=@($hash)}}
    $duplicate=[ordered]@{size=$core.Length;offset=[string]$core.Length;integrity=[ordered]@{algorithm='SHA256';hash=$hash;blockSize=4194304;blocks=@($hash)}}
    if($Shared){$duplicate.offset='0'}
    $root=[ordered]@{files=[ordered]@{render=@{files=@{assets=@{files=@{lib=@{files=@{'core.js'=$node}}}}}};'另一个.js'=$duplicate};label='保留中文头部'}
    $json=[Text.Encoding]::UTF8.GetBytes(($root|ConvertTo-Json -Depth 15 -Compress))
    $pad=(4-(($json.Length+8)%4))%4;$headerSize=8+$json.Length+$pad
    $dir=Split-Path -Parent $Path;if(-not (Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $stream=[IO.File]::Create($Path);$writer=New-Object IO.BinaryWriter($stream)
    try{
        $writer.Write([uint32]4);$writer.Write([uint32]$headerSize);$writer.Write([uint32]($headerSize-4));$writer.Write([uint32]$json.Length)
        $writer.Write($json);$writer.Write((New-Object byte[] $pad));$writer.Write($core);if(-not $Shared){$writer.Write($core)}
    }finally{$writer.Dispose();$stream.Dispose()}
    return $hash
}
function Wait-BiliPatched([string]$Path){
    $deadline=[DateTime]::UtcNow.AddSeconds(25)
    do{try{if([Bili3x.AsarEngine]::Inspect($Path).State -eq 'patched'){return}}catch{};Start-Sleep -Milliseconds 300}while([DateTime]::UtcNow -lt $deadline)
    throw 'Automatic maintenance did not apply the fixture patch.'
}
function Run-BiliInstaller([string]$Script,[string]$Data,[string]$Resource,[switch]$Remove,[switch]$Fail){
    $ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if($Remove){& $ps -NoProfile -ExecutionPolicy Bypass -File $Script -DataRoot $Data -Remove|Out-Null}
    else{& $ps -NoProfile -ExecutionPolicy Bypass -File $Script -DataRoot $Data -ResourceDirs $Resource|Out-Null}
    if($Fail){Assert-BiliTest ($LASTEXITCODE -ne 0) 'Unrelated task was overwritten.'}else{Assert-BiliTest ($LASTEXITCODE -eq 0) 'Installer failed.'}
}
try{
    foreach($file in (Get-ChildItem -LiteralPath $project -Filter '*.ps1' -Recurse)){
        $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)|Out-Null
        Assert-BiliTest ($errors.Count -eq 0) 'PowerShell parse error.'
    }
    Pass-BiliTest 'All scripts parse in Windows PowerShell 5.1.'
    $path=Join-Path $sandbox '中文 路径\sample.asar'
    $context=[pscustomobject]@{DataRoot=(Join-Path $sandbox 'data');InstallRoots=@((Split-Path -Parent $path));ResourceDirs=@()}
    $originalCoreHash=New-AsarFixture $path
    $original=[Bili3x.AsarEngine]::FileHash($path);$length=(Get-Item -LiteralPath $path).Length
    Assert-BiliTest ((Invoke-BiliPatch $path $context) -eq 'applied') 'Patch failed.'
    $info=[Bili3x.AsarEngine]::Inspect($path)
    Assert-BiliTest ($info.State -eq 'patched' -and $info.Length -eq $length) 'Patch changed the layout.'
    $header=$info.Json|ConvertFrom-Json
    Assert-BiliTest ($header.label -eq '保留中文头部' -and $header.files.'另一个.js'.integrity.hash -eq $originalCoreHash) 'Unrelated header was changed.'
    Pass-BiliTest 'Equal-length patch preserves UTF8 and offsets; repeated file/block hashes are scoped to core.js.'
    $patched=[Bili3x.AsarEngine]::FileHash($path)
    Assert-BiliTest ((Invoke-BiliPatch $path $context) -eq 'patched' -and [Bili3x.AsarEngine]::FileHash($path) -eq $patched) 'Repeated patch changed bytes.'
    Pass-BiliTest 'Patch is idempotent.'
    Assert-BiliTest ((Invoke-BiliRollback $path $context) -eq 'restored' -and [Bili3x.AsarEngine]::FileHash($path) -eq $original) 'Rollback changed original bytes.'
    Pass-BiliTest 'Verified recovery restores exact original bytes.'
    $null=Invoke-BiliPatch $path $context;$null=New-AsarFixture $path 'updated';$newOriginal=[Bili3x.AsarEngine]::FileHash($path)
    Expect-BiliFailure {Invoke-BiliRollback $path $context}
    Assert-BiliTest ([Bili3x.AsarEngine]::FileHash($path) -eq $newOriginal) 'Stale recovery overwrote the update.'
    Pass-BiliTest 'Stale recovery cannot overwrite a newer client version.'
    $null=Invoke-BiliPatch $path $context;$null=Invoke-BiliRollback $path $context
    Assert-BiliTest ([Bili3x.AsarEngine]::FileHash($path) -eq $newOriginal) 'Updated version did not recover.'
    Pass-BiliTest 'After an update, the new version gets its own verified original snapshot.'
    $bad=Join-Path $sandbox 'bad.asar';$null=New-AsarFixture $bad 'bad' 'differentMenu()';$before=[Bili3x.AsarEngine]::FileHash($bad)
    Expect-BiliFailure {Invoke-BiliPatch $bad $context};Assert-BiliTest ([Bili3x.AsarEngine]::FileHash($bad) -eq $before) 'Unsupported menu was altered.'
    $null=New-AsarFixture $bad 'bad' ([Bili3x.AsarEngine]::OldMenu+[Bili3x.AsarEngine]::OldMenu)
    Expect-BiliFailure {Invoke-BiliPatch $bad $context}
    Pass-BiliTest 'Unknown and ambiguous menu layouts are refused without overwriting.'
    $null=New-AsarFixture $bad 'shared' -Shared;Expect-BiliFailure {[Bili3x.AsarEngine]::Inspect($bad)}
    $null=New-AsarFixture $bad;$bytes=[IO.File]::ReadAllBytes($bad);$index=[int][Bili3x.AsarEngine]::Inspect($bad).CoreOffset;$bytes[$index]=$bytes[$index] -bxor 1;[IO.File]::WriteAllBytes($bad,$bytes)
    Expect-BiliFailure {Invoke-BiliPatch $bad $context}
    [IO.File]::WriteAllBytes($bad,(New-Object byte[] 8));Expect-BiliFailure {[Bili3x.AsarEngine]::Inspect($bad)}
    Pass-BiliTest 'Shared core storage, invalid hashes and truncated headers fail closed.'
    $legacy=Join-Path $sandbox 'legacy.asar';$null=New-AsarFixture $legacy
    Copy-Item -LiteralPath $legacy -Destination ($legacy+'.backup');$temp=Join-Path $sandbox 'legacy.tmp';$null=[Bili3x.AsarEngine]::BuildCandidate($legacy,$temp)
    [IO.File]::Replace($temp,$legacy,[Management.Automation.Language.NullString]::Value)
    Import-BiliLegacy $legacy $context;Assert-BiliTest ((Invoke-BiliRollback $legacy $context) -eq 'restored') 'Legacy recovery failed.'
    Pass-BiliTest 'Legacy backups are imported only after reproducing the patched bytes.'
    $busyExe=Join-Path (Split-Path -Parent $path) 'bilibili.exe'
    Add-Type -TypeDefinition 'public class BiliBusyFixture { public static void Main(){System.Threading.Thread.Sleep(60000);} }' -OutputAssembly $busyExe -OutputType WindowsApplication
    $busyProcess=Start-Process -FilePath $busyExe -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 250;Expect-BiliFailure {Invoke-BiliPatch $path $context};Stop-Process -Id $busyProcess.Id -Force;$busyProcess=$null
    Pass-BiliTest 'A running client fixture prevents modification.'
    $resource=Join-Path $sandbox 'automatic-resource';$autoData=Join-Path $sandbox 'automatic-data';$autoFile=Join-Path $resource 'hash-one.asar';$null=New-AsarFixture $autoFile
    $ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $watchArguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Watch -DataRoot "{1}" -ResourceDirs "{2}" -PollSeconds 1 -StableSeconds 1' -f (Join-Path $project 'patch_bili_asar.ps1'),$autoData,$resource
    $watcher=Start-Process -FilePath $ps -ArgumentList $watchArguments -WindowStyle Hidden -PassThru;$null=$watcher.Handle
    Wait-BiliPatched $autoFile;$null=New-AsarFixture $autoFile 'update';Wait-BiliPatched $autoFile
    $newFile=Join-Path $resource 'new-hash.asar';$null=New-AsarFixture $newFile 'new-name';Wait-BiliPatched $newFile
    $stop=[Threading.EventWaitHandle]::OpenExisting((Get-BiliEventName $autoData));try{$stop.Set()|Out-Null}finally{$stop.Dispose()}
    Assert-BiliTest ($watcher.WaitForExit(15000) -and $watcher.ExitCode -eq 0) 'Watcher did not stop gracefully.';$watcher=$null
    Pass-BiliTest 'Real watcher repairs same-name updates and newly named hot-update packages automatically.'
    $operation=New-BiliMutex 'Operation' $autoData;$null=$operation.WaitOne(0)
    try{
        $null=New-AsarFixture $autoFile 'stop-queued'
        $watcher=Start-Process -FilePath $ps -ArgumentList $watchArguments -WindowStyle Hidden -PassThru;$null=$watcher.Handle
        Start-Sleep -Seconds 4
        $stop=[Threading.EventWaitHandle]::OpenExisting((Get-BiliEventName $autoData));try{$stop.Set()|Out-Null}finally{$stop.Dispose()}
    }finally{$operation.ReleaseMutex();$operation.Dispose()}
    Assert-BiliTest ($watcher.WaitForExit(15000) -and $watcher.ExitCode -eq 0) 'Queued watcher ignored stop.';$watcher=$null
    Assert-BiliTest ([Bili3x.AsarEngine]::Inspect($autoFile).State -eq 'original') 'Disabled watcher reapplied the patch.'
    Pass-BiliTest 'A stop request cancels a queued patch before writing; rollback cannot be repatched by the watcher.'
    $clone=Join-Path $sandbox '源代码 副本';New-Item -ItemType Directory -Path (Join-Path $clone 'lib') -Force|Out-Null
    foreach($file in @('patch_bili_asar.ps1','Bili3x.Core.ps1','Bili3x.Automatic.ps1','Install-BiliAutomatic.ps1','lib\AsarEngine.cs')){Copy-Item -LiteralPath (Join-Path $project $file) -Destination (Join-Path $clone $file)}
    $installedData=Join-Path $sandbox 'installed-data';$taskFile=Join-Path $resource 'task-update.asar';$null=New-AsarFixture $taskFile 'task'
    Run-BiliInstaller (Join-Path $clone 'Install-BiliAutomatic.ps1') $installedData $resource
    $moved=Join-Path $sandbox '已移动 副本'
    Assert-BiliTest ((Test-BiliUnder $clone $sandbox) -and (Test-BiliUnder $moved $sandbox)) 'Unsafe fixture move.'
    Move-Item -LiteralPath $clone -Destination $moved
    Wait-BiliPatched $taskFile
    $null=New-AsarFixture $taskFile 'task-update';Wait-BiliPatched $taskFile
    Run-BiliInstaller (Join-Path $moved 'Install-BiliAutomatic.ps1') $installedData $resource -Remove
    Assert-BiliTest (-not (Get-ScheduledTask -TaskName (Get-BiliTaskName $installedData) -TaskPath '\' -ErrorAction SilentlyContinue)) 'Owned task remained.'
    $installedData=$null
    Pass-BiliTest 'Real logon task uses installed runtime, survives source-folder relocation, and disables cleanly.'
    $private=Protect-BiliText ($env:USERPROFILE+' '+$project+' '+$env:USERNAME+' '+$env:COMPUTERNAME) $context
    Assert-BiliTest ($private -notmatch [regex]::Escape($env:USERPROFILE) -and $private -notmatch [regex]::Escape($project)) 'Private diagnostics were not masked.'
    Pass-BiliTest 'Local paths and account/host identifiers are masked.'
    $result=@{Version=1;Result='PASS';Checks=@($checks.ToArray());ActualClientModified=$false}
}catch{
    $result=@{Version=1;Result='FAIL';Checks=@($checks.ToArray());Failure=(Protect-BiliText $_.Exception.Message $context)}
    Write-Host ('FAIL '+$result.Failure) -ForegroundColor Red
}finally{
    if($watcher -and -not $watcher.HasExited){Stop-Process -Id $watcher.Id -Force -ErrorAction SilentlyContinue}
    if($busyProcess -and -not $busyProcess.HasExited){Stop-Process -Id $busyProcess.Id -Force -ErrorAction SilentlyContinue}
    if($installedData){Run-BiliInstaller (Join-Path $project 'Install-BiliAutomatic.ps1') $installedData '' -Remove}
    $absolute=[IO.Path]::GetFullPath($sandbox)
    if(-not (Test-BiliUnder $absolute ([IO.Path]::GetTempPath())) -or (Split-Path -Leaf $absolute) -notmatch '^Bili3xTests-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup path.'}
    if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
Write-BiliJson (Join-Path $project 'artifacts/verification.json') $result
if($result.Result -ne 'PASS'){exit 1}
Write-Host ('Verified '+$checks.Count+' critical behaviors.')
