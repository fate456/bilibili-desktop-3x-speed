#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Apply','Status','Rollback','Enable','Disable')][string]$Action='Apply')
$ErrorActionPreference='Stop'
$ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($Action -ne 'Status' -and -not $admin){
    try{
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1}' -f $PSCommandPath,$Action
        $child=Start-Process -FilePath $ps -ArgumentList $arguments -Verb RunAs -PassThru -ErrorAction Stop
        $null=$child.Handle;$child.WaitForExit();exit $child.ExitCode
    }catch{Write-Host 'Administrator request was cancelled or failed.';exit 1}
}
$installer=Join-Path $PSScriptRoot 'Install-BiliAutomatic.ps1'
$patcher=Join-Path $PSScriptRoot 'patch_bili_asar.ps1'
switch($Action){
    'Enable' {& $ps -NoProfile -ExecutionPolicy Bypass -File $installer;exit $LASTEXITCODE}
    'Disable' {& $ps -NoProfile -ExecutionPolicy Bypass -File $installer -Remove;exit $LASTEXITCODE}
    'Status' {& $ps -NoProfile -ExecutionPolicy Bypass -File $patcher -Status;exit $LASTEXITCODE}
    'Rollback' {& $ps -NoProfile -ExecutionPolicy Bypass -File $patcher -Rollback;exit $LASTEXITCODE}
    'Apply' {
        & $ps -NoProfile -ExecutionPolicy Bypass -File $installer
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
        . (Join-Path $PSScriptRoot 'Bili3x.Core.ps1')
        $context=Get-BiliContext ''
        if(Test-BiliBusy $context){Write-Host 'Automatic maintenance is enabled. Exit the client from the background to let it apply the patch.';exit 0}
        & $ps -NoProfile -ExecutionPolicy Bypass -File $patcher;exit $LASTEXITCODE
    }
}
