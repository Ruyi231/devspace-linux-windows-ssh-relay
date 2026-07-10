$ErrorActionPreference='Stop'; . "$PSScriptRoot\lib.ps1"; $cfg=Read-Config
if (-not $cfg['RELAY_SSH_TARGET']) { throw 'RELAY_SSH_TARGET is empty. Run .\set_relay.cmd user@linux-host first.' }; if (-not $cfg['NGROK_PUBLIC_URL']) { throw 'NGROK_PUBLIC_URL is empty. Run .\setup_ngrok.cmd first.' }
$public=Normalize-Url $cfg['NGROK_PUBLIC_URL']; $ssh=Get-SshPath; $ngrok=Get-NgrokPath; if (-not $ssh -or -not $ngrok) { throw 'Run .\install.cmd first.' }
& "$PSScriptRoot\stop.ps1" | Out-Null
Write-Host '[1/3] Starting SSH local forward...'; $sshLog=Join-Path $Script:LogDir 'ssh.log'; $sshErr=Join-Path $Script:LogDir 'ssh-error.log'; Remove-Item $sshLog,$sshErr -Force -ErrorAction SilentlyContinue
$forward="$($cfg['RELAY_LOCAL_HOST']):$($cfg['RELAY_LOCAL_PORT']):$($cfg['RELAY_REMOTE_HOST']):$($cfg['RELAY_REMOTE_PORT'])"
$sshProc=Start-Process -FilePath $ssh -ArgumentList @('-N','-o','ExitOnForwardFailure=yes','-o','ServerAliveInterval=30','-o','ServerAliveCountMax=3','-L',$forward,$cfg['RELAY_SSH_TARGET']) -RedirectStandardOutput $sshLog -RedirectStandardError $sshErr -PassThru -WindowStyle Hidden
Set-Content (Join-Path $Script:RunDir 'ssh.pid') $sshProc.Id -Encoding ASCII
for($i=0;$i -lt 30;$i++){ if(-not (Get-Process -Id $sshProc.Id -ErrorAction SilentlyContinue)){ throw "SSH forward failed. Log: $sshErr" }; $code=Local-McpCode ([int]$cfg['RELAY_LOCAL_PORT']); if($code -in 401,200,405){break}; Start-Sleep -Seconds 1 }
if((Local-McpCode ([int]$cfg['RELAY_LOCAL_PORT'])) -notin 401,200,405){ throw "SSH forward did not reach Linux DevSpace. Check $sshErr" }
Write-Host '[2/3] Starting local ngrok...'; Clear-NgrokProxy; $ngLog=Join-Path $Script:LogDir 'ngrok.log'; $ngErr=Join-Path $Script:LogDir 'ngrok-error.log'; Remove-Item $ngLog,$ngErr -Force -ErrorAction SilentlyContinue
$ngProc=Start-Process -FilePath $ngrok -ArgumentList @('http',"127.0.0.1:$($cfg['RELAY_LOCAL_PORT'])",'--url',$public) -RedirectStandardOutput $ngLog -RedirectStandardError $ngErr -PassThru -WindowStyle Hidden; Set-Content (Join-Path $Script:RunDir 'ngrok.pid') $ngProc.Id -Encoding ASCII
try { $actual=Normalize-Url (Wait-NgrokUrl $ngProc.Id $cfg['NGROK_WEB_API'] ([int]$cfg['NGROK_STARTUP_TIMEOUT_SECONDS'])) } catch { & "$PSScriptRoot\stop.ps1" | Out-Null; throw "ngrok failed. Log: $ngErr" }; if($actual -ne $public){ & "$PSScriptRoot\stop.ps1" | Out-Null; throw "ngrok URL mismatch. Expected $public, got $actual" }
Write-Host '[3/3] Done.'; Write-Host "MCP URL: $public/mcp"; Write-Host 'Owner password: use the password printed by Linux start.sh.'
