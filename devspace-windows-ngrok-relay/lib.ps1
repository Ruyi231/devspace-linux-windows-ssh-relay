$ErrorActionPreference = 'Stop'
$Script:KitDir = $PSScriptRoot
$Script:ConfigFile = Join-Path $Script:KitDir 'config.env'
$Script:LogDir = Join-Path $Script:KitDir 'logs'
$Script:RunDir = Join-Path $Script:KitDir 'run'
$Script:NgrokDir = Join-Path $Script:KitDir 'tools\ngrok'
New-Item -ItemType Directory -Force -Path $Script:LogDir, $Script:RunDir, $Script:NgrokDir | Out-Null

function Ensure-Config {
  if (Test-Path -LiteralPath $Script:ConfigFile) { return }
  @(
    'RELAY_SSH_TARGET=',
    'RELAY_LOCAL_PORT=17676',
    'RELAY_REMOTE_HOST=127.0.0.1',
    'RELAY_REMOTE_PORT=7676',
    'NGROK_PUBLIC_URL=',
    'NGROK_WEB_API=http://127.0.0.1:4040/api',
    'NGROK_STARTUP_TIMEOUT_SECONDS=30'
  ) | Set-Content -LiteralPath $Script:ConfigFile -Encoding UTF8
}

function Read-Config {
  Ensure-Config
  $cfg = @{}
  foreach ($line in Get-Content -LiteralPath $Script:ConfigFile -Encoding UTF8) {
    if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)\s*$') { $cfg[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'") }
  }
  foreach ($pair in @{ RELAY_SSH_TARGET=''; RELAY_LOCAL_PORT='17676'; RELAY_REMOTE_HOST='127.0.0.1'; RELAY_REMOTE_PORT='7676'; NGROK_PUBLIC_URL=''; NGROK_WEB_API='http://127.0.0.1:4040/api'; NGROK_STARTUP_TIMEOUT_SECONDS='30' }.GetEnumerator()) {
    if (-not $cfg.ContainsKey($pair.Key)) { $cfg[$pair.Key] = $pair.Value }
  }
  return $cfg
}

function Save-Config([hashtable]$Config) {
  @('RELAY_SSH_TARGET','RELAY_LOCAL_PORT','RELAY_REMOTE_HOST','RELAY_REMOTE_PORT','NGROK_PUBLIC_URL','NGROK_WEB_API','NGROK_STARTUP_TIMEOUT_SECONDS') | ForEach-Object { "$_=$($Config[$_])" } | Set-Content -LiteralPath $Script:ConfigFile -Encoding UTF8
}

function Get-NgrokPath { $file = Join-Path $Script:NgrokDir 'ngrok.exe'; if (Test-Path -LiteralPath $file) { return $file }; return (Get-Command ngrok.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source) }
function Get-SshPath { return (Get-Command ssh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source) }
function Normalize-Url([string]$Url) { $url = $Url.Trim().TrimEnd('/'); if ($url -notmatch '^https://[^/?#]+$') { throw 'NGROK_PUBLIC_URL must be an HTTPS origin, for example https://example.ngrok-free.dev' }; return $url }
function Clear-NgrokProxy { 'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy' | ForEach-Object { Remove-Item "Env:$_" -ErrorAction SilentlyContinue } }
function Running([string]$PidText) { $id = 0; return [int]::TryParse($PidText, [ref]$id) -and $null -ne (Get-Process -Id $id -ErrorAction SilentlyContinue) }
function Stop-Pid([string]$Name) { $file = Join-Path $Script:RunDir "$Name.pid"; if (-not (Test-Path $file)) { return }; $pidText = (Get-Content $file | Select-Object -First 1); $id = 0; if ([int]::TryParse($pidText,[ref]$id)) { $p=Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { Stop-Process -Id $id -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500; if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } } }; Remove-Item $file -Force -ErrorAction SilentlyContinue }
function Get-NgrokUrl([string]$Api,[string]$LogFile='') {
  foreach ($path in @('endpoints','tunnels')) {
    try {
      $json=Invoke-RestMethod -Uri "$Api/$path" -TimeoutSec 3
      $items=@($json.endpoints)+@($json.tunnels)
      $item=$items | Where-Object { $_.public_url -like 'https://*' } | Select-Object -First 1
      if ($item) { return $item.public_url.TrimEnd('/') }
    } catch {}
  }
  if ($LogFile -and (Test-Path -LiteralPath $LogFile)) {
    $match=Select-String -LiteralPath $LogFile -Pattern 'https://[A-Za-z0-9.-]+\.ngrok(?:-free)?\.(?:dev|app)' -AllMatches | Select-Object -Last 1
    if ($match -and $match.Matches.Count) { return $match.Matches[$match.Matches.Count-1].Value.TrimEnd('/') }
  }
  return ''
}
function Wait-NgrokUrl([int]$ProcessId,[string]$Api,[int]$Seconds,[string]$LogFile='') { for ($i=0;$i -lt $Seconds*2;$i++) { if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'ngrok exited before exposing an endpoint.' }; $url=Get-NgrokUrl $Api $LogFile; if ($url) { return $url }; Start-Sleep -Milliseconds 500 }; throw "ngrok did not expose an endpoint within $Seconds seconds. Check the ngrok log file." }
function Local-McpCode([int]$Port) { try { Invoke-WebRequest -Uri "http://127.0.0.1:$Port/mcp" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop | Out-Null; return 200 } catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }; return 0 } }
