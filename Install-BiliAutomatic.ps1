#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Remove,[string]$DataRoot='', [string[]]$InstallRoots,[string[]]$ResourceDirs)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Bili3x.Core.ps1')
. (Join-Path $PSScriptRoot 'Bili3x.Automatic.ps1')
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin=([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){Write-Host 'Please run this installer as administrator.';exit 1}
$context=Get-BiliContext $DataRoot $InstallRoots $ResourceDirs
$taskName=Get-BiliTaskName $context.DataRoot
$owner='Bili3xAutoPatch:'+ (Get-BiliKey ($identity.User.Value+'|'+$context.DataRoot))
$existing=Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
if($existing -and $existing.Description -ne $owner){throw 'An unrelated scheduled task has the same name; it was not changed.'}
$settingsPath=Join-Path $context.DataRoot 'settings.json'
if($Remove){
    $settings=Read-BiliJson $settingsPath
    if(-not $settings){$settings=[pscustomobject]@{Version=1;AutomaticEnabled=$false;ExplicitScope=$context.ExplicitScope;InstallRoots=@($context.InstallRoots);ResourceDirs=@($context.ResourceDirs)}}
    else{$settings|Add-Member -NotePropertyName AutomaticEnabled -NotePropertyValue $false -Force}
    Write-BiliJson $settingsPath $settings
    if($existing){Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null}
    try{$stop=[Threading.EventWaitHandle]::OpenExisting((Get-BiliEventName $context.DataRoot));try{$stop.Set()|Out-Null}finally{$stop.Dispose()}}catch [Threading.WaitHandleCannotBeOpenedException]{}
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    $guard=New-BiliMutex 'Watcher' $context.DataRoot;$guardOwned=$false
    try{
        do{
            try{$guardOwned=$guard.WaitOne(300)}catch [Threading.AbandonedMutexException]{$guardOwned=$true}
        }while(-not $guardOwned -and [DateTime]::UtcNow -lt $deadline)
    }finally{if($guardOwned){$guard.ReleaseMutex()};$guard.Dispose()}
    $state=Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
    if($state -and $state.State -eq 'Running'){Stop-ScheduledTask -TaskName $taskName -TaskPath '\'}
    if($existing){Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false}
    Write-Host 'Automatic maintenance disabled. Existing patches and recovery snapshots are preserved.'
    exit 0
}
$runtimeFiles=@('patch_bili_asar.ps1','Bili3x.Core.ps1','Bili3x.Automatic.ps1','lib\AsarEngine.cs')
$runtimeFingerprint=($runtimeFiles|ForEach-Object{(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $_) -Algorithm SHA256).Hash}) -join '|'
$runtime=Join-Path (Join-Path $context.DataRoot 'runtime') (Get-BiliKey $runtimeFingerprint)
foreach($file in $runtimeFiles){
    $source=Join-Path $PSScriptRoot $file;$destination=Join-Path $runtime $file
    $dir=Split-Path -Parent $destination
    if(-not (Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    if(Test-Path -LiteralPath $destination){
        if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash){throw 'Installed runtime hash mismatch; existing task was preserved.'}
    }else{Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop}
}
$scriptPath=Join-Path $runtime 'patch_bili_asar.ps1'
$ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Watch -DataRoot "{1}"' -f $scriptPath,$context.DataRoot
$action=New-ScheduledTaskAction -Execute $ps -Argument $arguments -WorkingDirectory $runtime
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$principal=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
$taskSettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
Write-BiliJson $settingsPath @{Version=1;AutomaticEnabled=$true;ExplicitScope=$context.ExplicitScope;InstallRoots=@($context.InstallRoots);ResourceDirs=@($context.ResourceDirs)}
Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $taskSettings -Description $owner -Force|Out-Null
if($existing -and $existing.State -eq 'Running'){
    try{$stop=[Threading.EventWaitHandle]::OpenExisting((Get-BiliEventName $context.DataRoot));try{$stop.Set()|Out-Null}finally{$stop.Dispose()}}catch [Threading.WaitHandleCannotBeOpenedException]{}
    Start-Sleep -Seconds 2
    if((Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -eq 'Running'){Stop-ScheduledTask -TaskName $taskName -TaskPath '\'}
}
Start-ScheduledTask -TaskName $taskName -TaskPath '\'
Write-Host 'Automatic maintenance enabled and started. It also starts after you sign in.'
