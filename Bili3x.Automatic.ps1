#Requires -Version 5.1
function Get-BiliTaskName([string]$DataRoot='') {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return 'Bili3xAutoPatch-'+(Get-BiliKey ($sid+'|'+(Get-BiliDataRoot $DataRoot))).Substring(0,12)
}
function Get-BiliEventName([string]$DataRoot){return 'Global\Bili3xStop-'+(Get-BiliKey $DataRoot)}
function New-BiliMutex([string]$Kind,[string]$DataRoot){return [Threading.Mutex]::new($false,('Global\Bili3x-'+$Kind+'-'+(Get-BiliKey $DataRoot)))}
function Invoke-BiliLocked($Context,[scriptblock]$Body){
    $mutex=New-BiliMutex 'Operation' $Context.DataRoot;$owned=$false
    try{
        try{$owned=$mutex.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Another patch operation is busy.'}
        & $Body
    }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Get-BiliAutomaticSummary([string]$DataRoot){
    $settings=Read-BiliJson (Join-Path $DataRoot 'settings.json')
    $state=Read-BiliJson (Join-Path $DataRoot 'automatic-state.json')
    $task=Get-ScheduledTask -TaskName (Get-BiliTaskName $DataRoot) -TaskPath '\' -ErrorAction SilentlyContinue
    return [pscustomobject]@{Enabled=[bool]($settings -and $settings.AutomaticEnabled);TaskState=if($task){[string]$task.State}else{'NotInstalled'};LastState=$state}
}
function Invoke-BiliWatch([string]$DataRoot,[string[]]$InstallRoots,[string[]]$ResourceDirs,[int]$PollSeconds=5,[int]$StableSeconds=5){
    $data=Get-BiliDataRoot $DataRoot;$context=Get-BiliContext $data $InstallRoots $ResourceDirs
    $guard=New-BiliMutex 'Watcher' $data;$owned=$false;$stop=$null
    $cache=@{};$nextDiscovery=[DateTime]::MinValue;$lastStatus='';$lastLog=''
    try{
        try{$owned=$guard.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){return}
        $stop=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,(Get-BiliEventName $data));$stop.Reset()|Out-Null
        Write-BiliLog 'Automatic maintenance started; changed packages are processed after the client exits.' $context -Quiet
        while(-not $stop.WaitOne(0)){
            $settings=Read-BiliJson (Join-Path $data 'settings.json')
            if($settings -and -not $settings.AutomaticEnabled){break}
            $now=[DateTime]::UtcNow
            if($now -ge $nextDiscovery){$context=Get-BiliContext $data $InstallRoots $ResourceDirs;$nextDiscovery=$now.AddSeconds(60)}
            $targets=@(Get-BiliTargets $context);$pending=0;$patched=0;$unsupported=0;$busy=$null
            foreach($path in $targets){
                if($stop.WaitOne(0)){break}
                try{
                    $signature=Get-BiliSignature $path
                    if(-not $cache.ContainsKey($path) -or $cache[$path].Signature -ne $signature){
                        $cache[$path]=@{Signature=$signature;StableSince=$now;State='pending';NextTry=$now;Failures=0}
                    }
                    $entry=$cache[$path]
                    if($entry.State -eq 'patched'){$patched++;continue}
                    if($entry.State -eq 'unsupported'){$unsupported++;continue}
                    $pending++
                    if(($now-$entry.StableSince).TotalSeconds -lt $StableSeconds -or $now -lt $entry.NextTry){continue}
                    if($null -eq $busy){$busy=Test-BiliBusy $context}
                    if($busy){continue}
                    $result=Invoke-BiliLocked $context {
                        if($stop.WaitOne(0)){return 'stopped'}
                        Assert-BiliIdle $context
                        if((Get-BiliSignature $path) -ne $signature){throw 'Package changed before processing.'}
                        $inspection=[Bili3x.AsarEngine]::Inspect($path)
                        if($inspection.State -eq 'unknown'){return 'unsupported'}
                        if($inspection.State -eq 'patched'){
                            try{Import-BiliLegacy $path $context}catch{Write-BiliLog ('Legacy recovery not imported: '+$_.Exception.Message) $context -Quiet}
                            return 'patched'
                        }
                        return Invoke-BiliPatch $path $context
                    }
                    if($result -eq 'stopped'){break}
                    $entry.Signature=Get-BiliSignature $path
                    if($result -eq 'unsupported'){$entry.State='unsupported';$unsupported++;Write-BiliLog ('Unsupported menu layout; package left unchanged: '+[IO.Path]::GetFileName($path)) $context -Quiet}
                    else{$entry.State='patched';$patched++;Write-BiliLog ('Verified 3.0x patch: '+[IO.Path]::GetFileName($path)) $context -Quiet}
                    $pending--
                }catch{
                    $message=Protect-BiliText $_.Exception.Message $context
                    if($cache.ContainsKey($path)){
                        $entry=$cache[$path];$entry.Failures++;$entry.NextTry=$now.AddSeconds([Math]::Min(300,5*[Math]::Pow(2,[Math]::Min(6,$entry.Failures))))
                    }
                    if($lastLog -ne $message){Write-BiliLog ('Deferred: '+$message) $context -Quiet;$lastLog=$message}
                }
            }
            foreach($old in @($cache.Keys)){if($targets -notcontains $old){$cache.Remove($old)}}
            $mode=if($busy){'waiting-for-client-exit'}elseif(-not $targets.Count){'waiting-for-installation'}elseif($pending){'waiting-for-stable-file-or-retry'}elseif($unsupported){'unsupported-version'}else{'ready'}
            $summary=[pscustomobject]@{Version=1;Mode=$mode;Packages=$targets.Count;Patched=$patched;Pending=$pending;Unsupported=$unsupported}
            $serialized=$summary|ConvertTo-Json -Compress
            if($serialized -ne $lastStatus){Write-BiliJson (Join-Path $data 'automatic-state.json') $summary;$lastStatus=$serialized}
            if($stop.WaitOne($PollSeconds*1000)){break}
        }
        Write-BiliLog 'Automatic maintenance stopped.' $context -Quiet
    }finally{if($stop){$stop.Dispose()};if($owned){$guard.ReleaseMutex()};$guard.Dispose()}
}
