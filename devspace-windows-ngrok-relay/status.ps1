$ErrorActionPreference='Stop'; . "$PSScriptRoot\lib.ps1"; $cfg=Read-Config
foreach($name in 'ssh','ngrok'){ $file=Join-Path $Script:RunDir "$name.pid"; $text=if(Test-Path $file){Get-Content $file|Select-Object -First 1}else{''}; Write-Host "$name`: $(if(Running $text){"running, pid=$text"}else{'not running'})" }
$actual=Get-NgrokUrl $cfg['NGROK_WEB_API']; Write-Host "Configured URL: $($cfg['NGROK_PUBLIC_URL'])"; Write-Host "Actual URL:     $actual"; Write-Host "Forward check:  HTTP $(Local-McpCode ([int]$cfg['RELAY_LOCAL_PORT']))"
