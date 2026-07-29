<#
get_scrcpy_release.ps1
PowerShell helper to download the latest scrcpy Windows release (.zip) and extract into ./bin
Requires: PowerShell 5+ (Expand-Archive available)
#>
param(
    [string]$OutDir = "bin"
)

$api = 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

Write-Host "Querying $api ..."
$rel = Invoke-RestMethod -Uri $api -UseBasicParsing
$asset = $null
foreach ($a in $rel.assets) {
    $name = $a.name.ToLower()
    if ($name -like '*win*' -and $name -like '*.zip') { $asset = $a; break }
}
if (-not $asset) {
    foreach ($a in $rel.assets) { if ($a.name -like '*.zip') { $asset = $a; break } }
}
if (-not $asset) { Write-Error "No zip asset found in release. Visit https://github.com/Genymobile/scrcpy/releases"; exit 2 }

$url = $asset.browser_download_url
$zip = Join-Path $env:TEMP "scrcpy_release.zip"
Write-Host "Downloading $($asset.name) ..."
Invoke-WebRequest -Uri $url -OutFile $zip
Write-Host "Extracting to $OutDir ..."
Expand-Archive -Path $zip -DestinationPath $OutDir -Force
Remove-Item $zip -Force
Write-Host "Done. Files in: $OutDir"
