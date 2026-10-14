#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Bili3x.Core.ps1')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sources=@('Bili3x.Core.ps1','Bili3x.Automatic.ps1','Bili3x.Command.ps1','Install-BiliAutomatic.ps1','patch_bili_asar.ps1','lib/AsarEngine.cs',
    '应用补丁.bat','查看状态.bat','回滚.bat','启用自动补丁.bat','关闭自动补丁.bat','使用说明.md','开始使用.txt','.gitignore',
    'tests/Verify-Bili3x.ps1','tools/Review-Bili3x.ps1','tools/Build-Release.ps1',
    'README.md','LICENSE','VERSION','.gitattributes','.github/workflows/verify.yml','docs/images/hero.svg','docs/images/quickstart.svg')
$files=$sources+@('artifacts/code-review.txt','artifacts/verification.json','artifacts/live-acceptance.json','artifacts/privacy-review.json','artifacts/source-hashes.txt')
foreach($file in $sources){if(-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)){throw 'Missing release source file.'}}
$hashes=@($sources|ForEach-Object{'{0}  {1}' -f (Get-FileHash -LiteralPath (Join-Path $root $_) -Algorithm SHA256).Hash.ToLowerInvariant(),$_})
[IO.File]::WriteAllLines((Join-Path $root 'artifacts/source-hashes.txt'),[string[]]$hashes,[Text.UTF8Encoding]::new($false))
$target=Join-Path $root 'artifacts/Bili3x.zip';$tmp=$target+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
$stream=$null;$archive=$null
try{
    $stream=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew)
    $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    foreach($file in $files){
        $entry=$archive.CreateEntry('Bili3x/'+$file,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
        $inputStream=[IO.File]::OpenRead((Join-Path $root $file));$outputStream=$entry.Open()
        try{$inputStream.CopyTo($outputStream)}finally{$inputStream.Dispose();$outputStream.Dispose()}
    }
    $archive.Dispose();$archive=$null;$stream.Dispose();$stream=$null
    if(Test-Path -LiteralPath $target){[IO.File]::Replace($tmp,$target,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$target)}
}finally{
    if($archive){$archive.Dispose()};if($stream){$stream.Dispose()}
    if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}
}
Write-Host ('Package built: '+$files.Count+' allowlisted files.')
