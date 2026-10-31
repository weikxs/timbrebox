# TimbreBox installer for Windows (x64).
#
#   irm https://raw.githubusercontent.com/weikxs/timbrebox/main/install.ps1 | iex
#
# It downloads the Windows package from the GitHub release, checks it against
# the release's checksums.txt, puts TimbreBox into
# %LOCALAPPDATA%\Programs\TimbreBox and adds it to the Start menu. No
# administrator rights are needed and nothing else is changed. Your
# favorites, playlists, downloads and settings are never touched: they stay
# in TimbreBox's data folder whatever you install, upgrade or remove.
#
# Options, with
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/weikxs/timbrebox/main/install.ps1))) -Version v0.1.0
# (or the environment variables in brackets):
#   -Version <tag>   install this release, such as v0.1.0 [TIMBREBOX_VERSION]; default: the latest
#   -Dir <folder>    where TimbreBox goes [TIMBREBOX_INSTALL_DIR]; default: %LOCALAPPDATA%\Programs\TimbreBox
#   -NoShortcut      do not add TimbreBox to the Start menu
#   -Uninstall       remove TimbreBox and its Start menu entry (your data stays)
#
# Run it again to upgrade.

param(
  [string]$Version = $env:TIMBREBOX_VERSION,
  [string]$Dir = $env:TIMBREBOX_INSTALL_DIR,
  [switch]$NoShortcut,
  [switch]$Uninstall
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Windows PowerShell downloads far faster without the progress bar.

$Repo = 'weikxs/timbrebox'
$BaseUrl = if ($env:TIMBREBOX_BASE_URL) { $env:TIMBREBOX_BASE_URL.TrimEnd('/') } else { "https://github.com/$Repo/releases" }
$AppExe = 'timbrebox_app.exe'
$Shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'TimbreBox.lnk'
if (-not $Dir) { $Dir = Join-Path $env:LOCALAPPDATA 'Programs\TimbreBox' }

function Say([string]$Message) { Write-Information "timbrebox-install: $Message" -InformationAction Continue }
function Fail([string]$Message) { throw "timbrebox-install: error: $Message" }

# Releases are only fetched over HTTPS; a plain http:// TIMBREBOX_BASE_URL on
# this machine (a test server) is the only exception.
function Assert-SecureBase {
  if ($BaseUrl -like 'https://*') { return }
  if ($BaseUrl -like 'http://127.0.0.1:*' -or $BaseUrl -like 'http://localhost:*') { return }
  Fail "releases are only downloaded over https, not from $BaseUrl"
}

function Assert-Supported {
  if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    Fail 'this script is for Windows; on macOS and Linux use install.sh'
  }
  # Windows 11 on Arm runs the x64 app through its built-in emulation.
  $arch = $env:PROCESSOR_ARCHITECTURE
  if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
  if ($arch -ne 'AMD64' -and $arch -ne 'ARM64') {
    Fail "$arch Windows is not supported; TimbreBox for Windows runs on x64"
  }
}

# The tag of the newest release, read from where releases/latest redirects
# (no API call, so no rate limit).
function Get-LatestVersion {
  $request = [System.Net.HttpWebRequest]::Create("$BaseUrl/latest")
  $request.AllowAutoRedirect = $false
  $request.UserAgent = 'timbrebox-install'
  try {
    $response = $request.GetResponse()
    $location = $response.Headers['Location']
    $response.Close()
  } catch {
    Fail "could not reach $BaseUrl/latest"
  }
  $tag = ($location -split '/')[-1]
  if ($tag -notmatch '^v\d+\.\d+\.\d+') { Fail "could not find the latest release at $BaseUrl/latest" }
  return $tag
}

function Get-File([string]$Url, [string]$Path) {
  Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -UserAgent 'timbrebox-install'
}

# Downloads the package into $Work and stops unless its SHA-256 matches its
# line in the release's checksums.txt. Returns the package's path.
function Get-VerifiedPackage([string]$Tag, [string]$Work) {
  $number = $Tag.TrimStart('v')
  $file = "timbrebox_${number}_windows_amd64.zip"
  Say "downloading $file ($Tag)"
  try { Get-File "$BaseUrl/download/$Tag/$file" (Join-Path $Work $file) }
  catch { Fail "could not download $file; is $Tag a TimbreBox release?" }
  try { Get-File "$BaseUrl/download/$Tag/checksums.txt" (Join-Path $Work 'checksums.txt') }
  catch { Fail "could not download checksums.txt for $Tag" }
  $expected = $null
  foreach ($line in Get-Content (Join-Path $Work 'checksums.txt')) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $file) { $expected = $parts[0].ToLowerInvariant() }
  }
  if (-not $expected) { Fail "checksums.txt has no entry for $file" }
  $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $Work $file)).Hash.ToLowerInvariant()
  if ($expected -ne $actual) {
    Fail "checksum mismatch for $file (expected $expected, got $actual); nothing was installed"
  }
  Say 'checksum OK'
  return (Join-Path $Work $file)
}

function Assert-NotRunning {
  $exe = Join-Path $Dir $AppExe
  $running = Get-Process -Name 'timbrebox_app' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path -eq $exe }
  if ($running) { Fail 'TimbreBox is running; quit it and run this again' }
}

# Puts the unpacked app at $Dir in one step: the installed version is moved
# aside, the new one moved in, and the old one removed only then.
function Install-App([string]$Package, [string]$Work) {
  $unpacked = Join-Path $Work 'unpacked'
  Expand-Archive -Path $Package -DestinationPath $unpacked
  $app = Join-Path $unpacked 'TimbreBox'
  if (-not (Test-Path (Join-Path $app $AppExe))) { Fail "the package has no TimbreBox\$AppExe" }
  $parent = Split-Path $Dir -Parent
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $previous = "$Dir.previous"
  if (Test-Path $previous) { Remove-Item -Recurse -Force $previous }
  if (Test-Path $Dir) { Move-Item $Dir $previous }
  try {
    Move-Item $app $Dir
  } catch {
    if (Test-Path $previous) { Move-Item $previous $Dir }
    throw
  }
  if (Test-Path $previous) { Remove-Item -Recurse -Force $previous }
}

function Add-Shortcut {
  $shell = New-Object -ComObject WScript.Shell
  $link = $shell.CreateShortcut($Shortcut)
  $link.TargetPath = Join-Path $Dir $AppExe
  $link.WorkingDirectory = $Dir
  $link.Description = 'TimbreBox music player'
  $link.Save()
}

function Uninstall-App {
  Assert-NotRunning
  $removed = $false
  if (Test-Path $Shortcut) { Remove-Item -Force $Shortcut; $removed = $true }
  if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir; $removed = $true }
  if ($removed) { Say "removed TimbreBox from $Dir; your favorites, playlists and settings were kept" }
  else { Say "TimbreBox is not installed at $Dir" }
}

Assert-Supported
if ($Uninstall) {
  Uninstall-App
  return
}
Assert-SecureBase
# Windows PowerShell 5.1 may not offer TLS 1.2 by default.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
if (-not $Version) { $Version = Get-LatestVersion }
if ($Version -notmatch '^v\d+\.\d+\.\d+') { Fail "$Version is not a release tag such as v0.1.0" }
Assert-NotRunning
$work = Join-Path ([IO.Path]::GetTempPath()) ("timbrebox-install-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $package = Get-VerifiedPackage $Version $work
  Install-App $package $work
  if (-not $NoShortcut) { Add-Shortcut }
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
Say "installed TimbreBox $Version into $Dir"
if (-not $NoShortcut) { Say 'start it from the Start menu: TimbreBox' }
else { Say "start it with $(Join-Path $Dir $AppExe)" }
