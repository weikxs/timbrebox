# Installs a freshly built Windows package with the real install.ps1, from a
# local stand-in for the GitHub release, then starts the installed app, checks
# it keeps running, uninstalls it and checks it is gone. Used by the release
# and Full workflows on a Windows machine before anything is published.
#
# usage: scripts/release/verify-install.ps1 <tag> <folder with the release files>

param(
  [Parameter(Mandatory)] [string]$Tag,
  [Parameter(Mandatory)] [string]$Dist
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$RunSeconds = 15
$Port = 8765

function Say([string]$Message) { Write-Information "verify-install: $Message" -InformationAction Continue }
function Fail([string]$Message) { throw "verify-install: FAILED: $Message" }

$work = Join-Path ([IO.Path]::GetTempPath()) ("timbrebox-verify-" + [Guid]::NewGuid().ToString('N'))
$release = Join-Path $work "release\download\$Tag"
New-Item -ItemType Directory -Force -Path $release | Out-Null
$server = $null
try {
  # The release as install.ps1 sees it: <base>/download/<tag>/<file> and checksums.txt.
  $packages = @(Get-ChildItem -Path $Dist -Filter 'timbrebox_*_windows_amd64.zip')
  if ($packages.Count -ne 1) { Fail "expected one Windows package in $Dist, found $($packages.Count)" }
  Copy-Item $packages[0].FullName $release
  $hash = (Get-FileHash -Algorithm SHA256 $packages[0].FullName).Hash.ToLowerInvariant()
  Set-Content -Path (Join-Path $release 'checksums.txt') -Value "$hash  $($packages[0].Name)" -Encoding ascii
  $server = Start-Process -FilePath 'python' -PassThru -WindowStyle Hidden -ArgumentList @(
    '-m', 'http.server', "$Port", '--bind', '127.0.0.1', '--directory', (Join-Path $work 'release')
  )
  $ready = $false
  for ($i = 0; $i -lt 10 -and -not $ready; $i++) {
    try {
      Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/download/$Tag/checksums.txt" | Out-Null
      $ready = $true
    } catch { Start-Sleep -Seconds 1 }
  }
  if (-not $ready) { Fail 'the stand-in release server did not start' }

  $env:TIMBREBOX_BASE_URL = "http://127.0.0.1:$Port"
  $dir = Join-Path $work 'Programs\TimbreBox'
  & (Join-Path $PSScriptRoot '..\..\install.ps1') -Version $Tag -Dir $dir
  $exe = Join-Path $dir 'timbrebox_app.exe'
  if (-not (Test-Path $exe)) { Fail "install.ps1 did not put timbrebox_app.exe into $dir" }
  $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'TimbreBox.lnk'
  if (-not (Test-Path $shortcut)) { Fail 'install.ps1 did not add the Start menu entry' }
  Say "installed into $dir, with a Start menu entry"

  # Running it again upgrades in place.
  & (Join-Path $PSScriptRoot '..\..\install.ps1') -Version $Tag -Dir $dir
  if (-not (Test-Path $exe)) { Fail 'installing over an installed version lost the app' }
  Say 'installing again over it works'

  $app = Start-Process -FilePath $exe -PassThru
  Start-Sleep -Seconds $RunSeconds
  if ($app.HasExited) { Fail "the app exited within ${RunSeconds}s (exit code $($app.ExitCode))" }
  Stop-Process -Id $app.Id -Force
  $app.WaitForExit()
  Say "the app started and kept running for ${RunSeconds}s"

  & (Join-Path $PSScriptRoot '..\..\install.ps1') -Uninstall -Dir $dir
  if ((Test-Path $dir) -or (Test-Path $shortcut)) { Fail '-Uninstall left TimbreBox or its Start menu entry behind' }
  Say 'uninstalled: the app and the Start menu entry are gone'
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Remove-Item Env:\TIMBREBOX_BASE_URL -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
