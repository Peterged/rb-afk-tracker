param(
    [string]$Version = "",
    [string]$Message = "Release update",
    [switch]$BumpPatch = $false,
    [switch]$Push = $false,
    [switch]$SkipTests = $false
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$cscExe = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path $ahkExe)) {
    throw "AutoHotkey64.exe not found at $ahkExe"
}
if (-not (Test-Path $cscExe)) {
    throw "C# compiler not found at $cscExe"
}

# 1. Run syntax validation & unit test suite unless skipped
if (-not $SkipTests) {
    Write-Host "==> Validating RobloxAfkMonitor.ahk..." -ForegroundColor Cyan
    $valOut = & $ahkExe /ErrorStdOut /validate "$root\RobloxAfkMonitor.ahk" 2>&1 | Out-String
    if ($valOut.Trim() -ne "") {
        Write-Error $valOut
        throw "Syntax validation failed."
    }

    Write-Host "==> Running automated test suite..." -ForegroundColor Cyan
    $testOut = & $ahkExe /ErrorStdOut "$root\tests\RunTests.ahk" 2>&1 | Out-String
    Write-Host $testOut
    if ($testOut -notmatch "0 failed") {
        throw "Unit test suite failed."
    }
}

# 2. Resolve or bump semantic version in VERSION
$verFile = Join-Path $root "VERSION"
$curVer = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { "1.0.0" }

if ($Version -ne "") {
    $newVer = $Version.Trim()
} elseif ($BumpPatch) {
    $parts = $curVer.Split('.')
    $patch = [int]$parts[2] + 1
    $newVer = "$($parts[0]).$($parts[1]).$patch"
} else {
    $newVer = $curVer
}

[System.IO.File]::WriteAllText($verFile, "$newVer`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "==> Version: $newVer" -ForegroundColor Green

# 3. Auto-detect git remote origin (if set) and update default Update.Repo in Config.ahk if desired
$detectedRepo = ""
try {
    $remoteUrl = (git remote get-url origin 2>$null)
    if ($remoteUrl -match "github\.com[:/]([^/]+/[^/\.]+?)(?:\.git)?$") {
        $detectedRepo = $Matches[1]
        Write-Host "==> Detected GitHub repository: $detectedRepo" -ForegroundColor Cyan
    }
} catch { }

# 4. Generate SHA-256 manifest.json for RobloxAfkMonitor.ahk and lib/*
$trackedFiles = @("RobloxAfkMonitor.ahk")
Get-ChildItem (Join-Path $root "lib") -File | Sort-Object Name | ForEach-Object {
    $trackedFiles += "lib/$($_.Name)"
}

$entries = @()
foreach ($rel in $trackedFiles) {
    $full = Join-Path $root ($rel.Replace('/', '\'))
    $hash = (Get-FileHash -Path $full -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $full).Length
    $entries += "    { `"path`": `"$rel`", `"sha256`": `"$hash`", `"size`": $size }"
}

$manifestJson = "{`n  `"version`": `"$newVer`",`n  `"files`": [`n" + ($entries -join ",`n") + "`n  ]`n}`n"
$manifestPath = Join-Path $root "manifest.json"
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "==> Generated manifest.json ($($trackedFiles.Count) files hashed)" -ForegroundColor Cyan

# 5. Compile RobloxAfkMonitor.exe launcher
Write-Host "==> Compiling RobloxAfkMonitor.exe..." -ForegroundColor Cyan
& $cscExe /nologo /target:winexe /optimize+ /out:"$root\RobloxAfkMonitor.exe" /r:System.Windows.Forms.dll "$root\installer\Launcher.cs"
if ($LASTEXITCODE -ne 0) { throw "Failed to compile RobloxAfkMonitor.exe" }

# 6. Build payload.zip and compile standalone dist\Setup-RobloxAfkMonitor.exe
$distDir = Join-Path $root "dist"
$stagePayload = Join-Path $distDir ".payload_stage"
$payloadZip = Join-Path $distDir "payload.zip"

if (Test-Path $stagePayload) { Remove-Item -Recurse -Force $stagePayload }
if (Test-Path $payloadZip) { Remove-Item -Force $payloadZip }
New-Item -ItemType Directory -Path (Join-Path $stagePayload "bin") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagePayload "lib") -Force | Out-Null

# Bundle AutoHotkey64.exe inside bin\ so the friend never needs to install AutoHotkey
Copy-Item $ahkExe (Join-Path $stagePayload "bin\AutoHotkey64.exe") -Force
Copy-Item "$root\RobloxAfkMonitor.exe" (Join-Path $stagePayload "RobloxAfkMonitor.exe") -Force
Copy-Item "$root\RobloxAfkMonitor.ahk" (Join-Path $stagePayload "RobloxAfkMonitor.ahk") -Force
Copy-Item "$root\Start Roblox AFK Monitor.bat" (Join-Path $stagePayload "Start Roblox AFK Monitor.bat") -Force
Copy-Item "$root\VERSION" (Join-Path $stagePayload "VERSION") -Force
Copy-Item "$root\manifest.json" (Join-Path $stagePayload "manifest.json") -Force
Copy-Item "$root\README.md" (Join-Path $stagePayload "README.md") -Force
Copy-Item "$root\lib\*" (Join-Path $stagePayload "lib\") -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagePayload, $payloadZip)
Remove-Item -Recurse -Force $stagePayload

$setupExe = Join-Path $distDir "Setup-RobloxAfkMonitor.exe"
Write-Host "==> Compiling standalone installer dist\Setup-RobloxAfkMonitor.exe..." -ForegroundColor Cyan
& $cscExe /nologo /target:winexe /optimize+ /out:"$setupExe" `
    /r:System.Windows.Forms.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll `
    /resource:"$payloadZip,payload.zip" "$root\installer\Setup.cs"
if ($LASTEXITCODE -ne 0) { throw "Failed to compile Setup-RobloxAfkMonitor.exe" }
Remove-Item -Force $payloadZip

$sizeMb = [Math]::Round((Get-Item $setupExe).Length / 1MB, 2)
Write-Host "==> Built $setupExe ($sizeMb MB)" -ForegroundColor Green

# 7. Optional git commit & push
if ($Push) {
    Write-Host "==> Committing and pushing v$newVer to GitHub..." -ForegroundColor Cyan
    git add .gitignore .gitattributes VERSION manifest.json RobloxAfkMonitor.ahk RobloxAfkMonitor.exe "Start Roblox AFK Monitor.bat" lib/ installer/ tests/ README.md publish.ps1
    git commit -m "$Message (v$newVer)"
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
    git push -u origin main
    if ($LASTEXITCODE -ne 0) { throw "git push failed" }
    Write-Host "==> Pushed v$newVer to GitHub!" -ForegroundColor Green
}
