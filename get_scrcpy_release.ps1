<# get_scrcpy_release.ps1 #>
param(
    [string]$OutDir = "bin"
)

$api = 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

Write-Host "Querying $api ..."
try {
    $rel = Invoke-RestMethod -Uri $api -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Error "Failed to query GitHub API: $_"
    exit 2
}

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
try {
    Invoke-WebRequest -Uri $url -OutFile $zip -ErrorAction Stop
} catch {
    Write-Error "Download failed: $_"
    exit 3
}

Write-Host "Extracting to $OutDir ..."
try {
    Expand-Archive -Path $zip -DestinationPath $OutDir -Force -ErrorAction Stop
    Remove-Item $zip -Force
} catch {
    Write-Error "Extraction failed: $_"
    exit 4
}
Write-Host "Done. Files in: $OutDir"
