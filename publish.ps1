# publish.ps1
# Builds a Windows release, packages it as MSIX, and rewrites the generated
# .appinstaller file so its Uri attributes point to GitHub Pages instead of
# local Windows paths.  Output lands in the gh-pages/ git worktree; push that
# branch to publish the update.
#
# Local usage:
#   .\publish.ps1              # full build + publish (uses cert from pubspec.yaml)
#   .\publish.ps1 -SkipBuild   # re-publish without rebuilding
#
# CI usage (GitHub Actions passes cert via secrets):
#   .\publish.ps1 -CertPath "path\to\cert.pfx" -CertPassword "secret"

param(
    [switch]$SkipBuild,
    [string]$CertPath     = "",
    [string]$CertPassword = ""
)

$ErrorActionPreference = "Stop"

$GithubPagesBase = "https://kwasiasante.github.io/UtilityBillsManager"
$PublishFolder   = Join-Path $PSScriptRoot "gh-pages"

# Set up the gh-pages worktree automatically if it doesn't already exist.
if (-not (Test-Path $PublishFolder)) {
    Write-Host "Setting up gh-pages worktree..." -ForegroundColor Cyan
    git worktree add gh-pages gh-pages
    if ($LASTEXITCODE -ne 0) { throw "Failed to add gh-pages worktree — does the gh-pages branch exist?" }
}

# 1. Build
if (-not $SkipBuild) {
    Write-Host "`nBuilding Windows release..." -ForegroundColor Cyan
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
}

# 2. Package + publish
# Remove stale .appinstaller and any old MSIX files so that:
#   - msix:publish skips its interactive version-bump prompt
#   - the versions/ folder contains only the freshly built MSIX (no stale LFS pointers)
Remove-Item (Join-Path $PublishFolder "*.appinstaller") -ErrorAction SilentlyContinue
$versionsFolder = Join-Path $PublishFolder "versions"
if (Test-Path $versionsFolder) {
    Remove-Item (Join-Path $versionsFolder "*.msix") -ErrorAction SilentlyContinue
}

Write-Host "`nPackaging and publishing MSIX..." -ForegroundColor Cyan

$msixArgs = @("run", "msix:publish")
if ($CertPath)     { $msixArgs += "--certificate-path",     $CertPath }
if ($CertPassword) { $msixArgs += "--certificate-password", $CertPassword }

& dart @msixArgs
if ($LASTEXITCODE -ne 0) { throw "msix:publish failed (exit $LASTEXITCODE)" }

# 3. Fix index.html install href: msix tool generates an absolute-root path (/file.appinstaller)
#    which breaks on GitHub Pages (served from a subdirectory). Make it relative instead.
$indexFile = Join-Path $PublishFolder "index.html"
if (Test-Path $indexFile) {
    $html = Get-Content $indexFile -Raw -Encoding UTF8
    # Change absolute-root href ('/file.appinstaller') to relative ('./file.appinstaller')
    $html = $html.Replace("a.href = '/", "a.href = './")
    Set-Content $indexFile $html -Encoding UTF8 -NoNewline
    Write-Host "Fixed install href in index.html" -ForegroundColor Green
}

# 4. Fix .appinstaller URIs: local Windows path -> GitHub Pages URL
$appInstallerFile = Get-ChildItem $PublishFolder -Filter "*.appinstaller" -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $appInstallerFile) {
    Write-Warning "No .appinstaller found in $PublishFolder -- skipping URI fix."
} else {
    $content = Get-Content $appInstallerFile.FullName -Raw -Encoding UTF8

    # Replace absolute path variant (CI / machines where docs/ didn't pre-exist)
    $content = $content.Replace($PublishFolder, $GithubPagesBase)

    # Replace relative path variant (local: msix package kept "gh-pages\" because
    # the folder already existed and it resolved as a valid relative path)
    $relativeName = Split-Path $PublishFolder -Leaf
    $content = $content -replace "Uri=`"$relativeName[/\\]", "Uri=`"$GithubPagesBase/"

    # Normalise any remaining backslashes inside https:// URL strings
    $pass = 0
    while ($content -match 'Uri="https://[^"]*\\' -and $pass -lt 10) {
        $content = $content -replace '(Uri="https://[^"]*?)\\', '$1/'
        $pass++
    }

    Set-Content $appInstallerFile.FullName $content -Encoding UTF8 -NoNewline
    Write-Host "Fixed URIs in $($appInstallerFile.Name)" -ForegroundColor Green
}

# 4. Summary
Write-Host "`n--- Done ---" -ForegroundColor Green
Write-Host ""
Write-Host "Commit and push the gh-pages branch to publish the update:" -ForegroundColor Yellow
Write-Host "  git -C gh-pages add ."
Write-Host '  git -C gh-pages commit -m "chore: release vX.Y.Z"'
Write-Host "  git -C gh-pages push origin gh-pages"
Write-Host ""
$endpoint = $GithubPagesBase + "/utility_bills_manager.appinstaller"
Write-Host "Auto-update endpoint:" -ForegroundColor Yellow
Write-Host "  $endpoint" -ForegroundColor Cyan
