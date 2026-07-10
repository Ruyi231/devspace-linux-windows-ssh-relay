$ErrorActionPreference='Stop'; . "$PSScriptRoot\lib.ps1"; Stop-Pid ngrok; Stop-Pid ssh; Write-Host 'Stopped local SSH relay and ngrok.'
