$ErrorActionPreference='Stop'; . "$PSScriptRoot\lib.ps1"
Write-Host '[1/2] Checking OpenSSH client...'; $ssh=Get-SshPath; if (-not $ssh) { throw 'ssh.exe is missing. Install Windows OpenSSH Client from Optional Features, then rerun.' }; Write-Host "      $ssh"
Write-Host '[2/2] Installing local ngrok...'; $ngrok=Get-NgrokPath
if (-not $ngrok) { $zip=Join-Path $env:TEMP 'ngrok-windows-amd64.zip'; Invoke-WebRequest -Uri 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip' -OutFile $zip -UseBasicParsing; Expand-Archive -LiteralPath $zip -DestinationPath $Script:NgrokDir -Force; Remove-Item $zip -Force; $ngrok=Get-NgrokPath }
if (-not $ngrok) { throw 'ngrok installation failed.' }; & $ngrok version; Ensure-Config; Write-Host "Config file: $Script:ConfigFile"; Write-Host 'Next: .\setup_ngrok.cmd, then .\set_relay.cmd user@linux-host'
