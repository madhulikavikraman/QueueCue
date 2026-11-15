# QueueCue on Windows: one command to start everything.
#   .\run_demo.ps1 [-Reset] [-Live] [-Lan]
param([switch]$Reset, [switch]$Live, [switch]$Lan)
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
$Port = 8080
$Log = Join-Path $PSScriptRoot "server\data\logs"
New-Item -ItemType Directory -Force -Path $Log | Out-Null
$cfg = Get-Content server\config.json -Raw | ConvertFrom-Json

Write-Host "1/5 Local AI (Ollama, model: $($cfg.model))" -ForegroundColor White
try { Invoke-RestMethod http://127.0.0.1:11434/api/tags -TimeoutSec 2 | Out-Null; Write-Host "  ok Ollama running" }
catch {
  if (Get-Command ollama -ErrorAction SilentlyContinue) { Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden; Start-Sleep 3; Write-Host "  ok started Ollama" }
  else { Write-Host "  ! Ollama not installed; Demo Mode cache still works" -ForegroundColor Yellow }
}

Write-Host "2/5 Web app"
if (-not (Test-Path app\build\web\index.html)) {
  Push-Location app; flutter build web --release --no-web-resources-cdn --no-wasm-dry-run; Pop-Location
}

Write-Host "3/5 Server on :$Port"
$sargs = @("run", "bin/server.dart")
if ($Reset) { $sargs += "--reset" }
if ($Live) { $sargs += "--live" }
$server = Start-Process dart -ArgumentList $sargs -WorkingDirectory (Join-Path $PSScriptRoot "server") -RedirectStandardOutput "$Log\server.log" -RedirectStandardError "$Log\server.err.log" -PassThru -WindowStyle Hidden
for ($i = 0; $i -lt 90; $i++) { try { Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 1 | Out-Null; break } catch { Start-Sleep 1 } }

Write-Host "4/5 HTTPS link"
$url = ""
if (-not $Lan -and (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
  $tunnel = Start-Process cloudflared -ArgumentList "tunnel --no-autoupdate --url http://localhost:$Port" -RedirectStandardError "$Log\tunnel.log" -PassThru -WindowStyle Hidden
  for ($i = 0; $i -lt 40; $i++) {
    $m = Select-String -Path "$Log\tunnel.log" -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { $url = $m.Matches[0].Value; break }; Start-Sleep 1
  }
}
if (-not $url) {
  $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notmatch "^169" } | Select-Object -First 1).IPAddress
  $url = "http://$($ip):$Port"
  Write-Host "  ! LAN link (same Wi-Fi; iPhone camera/mic need HTTPS)" -ForegroundColor Yellow
}

Write-Host "5/5 Scan with the iPhone camera:"
Push-Location server; dart run bin/qr.dart $url; Pop-Location
Write-Host ""
Write-Host "Students:  $url"
Write-Host "Phone A:   $url/?student=demo-viktor"
Write-Host "Phone B:   $url/?student=demo-hermione"
Write-Host "Recruiter: $url/booth/northwind?key=bk-northwind"
Write-Host "Organizer: $url/organizer?org=$($cfg.organizer_key)"
Write-Host "Press Enter to stop."
[void][System.Console]::ReadLine()
Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
if ($tunnel) { Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue }
