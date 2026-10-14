#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Rollback,[switch]$Status,[switch]$Watch,
    [Parameter(Position=0,ValueFromRemainingArguments=$true)][string[]]$Paths,
    [string]$DataRoot='', [string[]]$InstallRoots,[string[]]$ResourceDirs,
    [ValidateRange(1,60)][int]$PollSeconds=5,[ValidateRange(1,60)][int]$StableSeconds=5
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Bili3x.Core.ps1')
. (Join-Path $PSScriptRoot 'Bili3x.Automatic.ps1')
$context=$null;$code=0
try{
    $modes=@($Rollback,$Status,$Watch)|Where-Object {$_.IsPresent}
    if(@($modes).Count -gt 1){throw 'Choose only one of Rollback, Status or Watch.'}
    $context=Get-BiliContext $DataRoot $InstallRoots $ResourceDirs
    if($Watch){Invoke-BiliWatch $context.DataRoot $InstallRoots $ResourceDirs $PollSeconds $StableSeconds;exit 0}
    $targets=if($Paths){@($Paths|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object -Unique)}else{@(Get-BiliTargets $context)}
    if($Status){
        $auto=Get-BiliAutomaticSummary $context.DataRoot
        Write-Host ('Automatic: enabled={0}; task={1}' -f $auto.Enabled,$auto.TaskState)
        if($auto.LastState){Write-Host ('Maintenance: {0}; patched={1}; pending={2}; unsupported={3}' -f $auto.LastState.Mode,$auto.LastState.Patched,$auto.LastState.Pending,$auto.LastState.Unsupported)}
        Write-Host ('Client or updater running: '+(Test-BiliBusy $context))
        if(-not $targets.Count){Write-Host 'No application packages discovered.';$code=1}
        foreach($path in $targets){
            try{
                $null=Get-BiliSignature $path;$info=[Bili3x.AsarEngine]::Inspect($path)
                Write-Host ('[{0}] {1}; integrity verified' -f $info.State,[IO.Path]::GetFileName($path))
                if($info.State -eq 'unknown'){$code=1}
            }catch{Write-Host ('[unverified] '+(Protect-BiliText $_.Exception.Message $context));$code=1}
        }
        exit $code
    }
    if($Rollback){
        $ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-BiliAutomatic.ps1') -Remove -DataRoot $context.DataRoot
        if($LASTEXITCODE -ne 0){throw 'Could not stop automatic maintenance; rollback cancelled.'}
    }
    if(-not $targets.Count){throw '未发现客户端应用包。请安装客户端，或设置 BILI_INSTALL_DIR 指向安装目录。'}
    Invoke-BiliLocked $context {
        Assert-BiliIdle $context
        foreach($path in $targets){
            try{
                if($Rollback){$result=Invoke-BiliRollback $path $context}
                else{$result=Invoke-BiliPatch $path $context;if($result -eq 'patched'){Import-BiliLegacy $path $context}}
                Write-BiliLog ('['+$result+'] '+[IO.Path]::GetFileName($path)) $context
            }catch{Write-BiliLog ('[failed] '+[IO.Path]::GetFileName($path)+': '+$_.Exception.Message) $context;$script:code=1}
        }
    }
}catch{
    Write-Host (Protect-BiliText $_.Exception.Message $context) -ForegroundColor Red;$code=1
}
exit $code
