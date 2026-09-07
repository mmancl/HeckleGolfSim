<#
.SYNOPSIS
    Signs an Android App Bundle (.aab) with jarsigner for Google Play Store upload.
.DESCRIPTION
    Signs the specified .aab file using SHA256withRSA signature algorithm and verifies
    the resulting bundle signature.
.PARAMETER AabPath
    Path to the .aab bundle file (default: "HeckleGolfSim.aab").
.PARAMETER KeystorePath
    Path to the keystore file (default: "release.keystore").
.PARAMETER Alias
    Key alias within the keystore (default: "hecklegolf").
.PARAMETER Password
    Keystore password. If omitted, you will be prompted securely.
#>

param(
    [string]$AabPath = "HeckleGolfSim.aab",
    [string]$KeystorePath = "release.keystore",
    [string]$Alias = "hecklegolf",
    [string]$Password = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - Android AAB Bundle Signer" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

# Resolve AAB Path
$resolvedAabPath = if ([System.IO.Path]::IsPathRooted($AabPath)) { $AabPath } else { Join-Path $scriptDir $AabPath }
if (-not (Test-Path $resolvedAabPath)) {
    Write-Host "[ERROR] AAB file not found at: $resolvedAabPath" -ForegroundColor Red
    Write-Host "Please build the AAB first using .\build_aab.ps1" -ForegroundColor Yellow
    exit 1
}

# Resolve Keystore Path
$resolvedKeystorePath = if ([System.IO.Path]::IsPathRooted($KeystorePath)) { $KeystorePath } else { Join-Path $scriptDir $KeystorePath }
if (-not (Test-Path $resolvedKeystorePath)) {
    # Check ~/.android/debug.keystore as fallback notice
    Write-Host "[WARNING] Keystore not found at: $resolvedKeystorePath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If you do not have a release keystore yet, generate one now using:" -ForegroundColor Cyan
    Write-Host "  .\generate_keystore.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Or specify your existing keystore path:" -ForegroundColor Cyan
    Write-Host "  .\sign_aab.ps1 -KeystorePath 'C:\path\to\your.keystore' -Alias 'your-alias'" -ForegroundColor White
    exit 1
}

# Locate jarsigner
$jarsignerCmd = "jarsigner"
$found = Get-Command $jarsignerCmd -ErrorAction SilentlyContinue
if (-not $found) {
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\jarsigner.exe")) {
        $jarsignerCmd = "$env:JAVA_HOME\bin\jarsigner.exe"
    } else {
        Write-Host "[ERROR] jarsigner was not found in PATH or JAVA_HOME." -ForegroundColor Red
        Write-Host "Please ensure OpenJDK 17+ or JDK 21 is installed." -ForegroundColor Yellow
        exit 1
    }
}

# Prompt for password if not provided
if (-not $Password) {
    if ($env:ANDROID_KEYSTORE_PASS) {
        $Password = $env:ANDROID_KEYSTORE_PASS
    } else {
        $secPass = Read-Host "Enter password for keystore '$resolvedKeystorePath'" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
        $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

if (-not $Password) {
    Write-Host "[ERROR] Keystore password cannot be empty." -ForegroundColor Red
    exit 1
}

Write-Host "Signing bundle: $resolvedAabPath" -ForegroundColor Green
Write-Host "Keystore:       $resolvedKeystorePath" -ForegroundColor Gray
Write-Host "Key Alias:      $Alias" -ForegroundColor Gray
Write-Host ""

# Strip any existing signatures so Google Play does not reject the bundle for having multiple certificate chains
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($resolvedAabPath, [System.IO.Compression.ZipArchiveMode]::Update)
$existingSigs = @($zip.Entries | Where-Object { 
    $_.FullName -like "META-INF/*.SF" -or 
    $_.FullName -like "META-INF/*.RSA" -or 
    $_.FullName -like "META-INF/*.DSA" -or 
    $_.FullName -like "META-INF/*.EC" 
})
if ($existingSigs.Count -gt 0) {
    Write-Host "Clearing $($existingSigs.Count) existing signature file(s) to guarantee a single certificate chain..." -ForegroundColor Yellow
    foreach ($sigEntry in $existingSigs) {
        $sigEntry.Delete()
    }
}
$zip.Dispose()

# Sign with jarsigner
& $jarsignerCmd -sigalg SHA256withRSA -digestalg SHA-256 -keystore $resolvedKeystorePath -storepass $Password $resolvedAabPath $Alias

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] jarsigner failed to sign the bundle. Please verify your password and key alias." -ForegroundColor Red
    exit 1
}

# Verify signature
Write-Host ""
Write-Host "Verifying signature..." -ForegroundColor Cyan
& $jarsignerCmd -verify $resolvedAabPath

if ($LASTEXITCODE -eq 0) {
    $fileItem = Get-Item $resolvedAabPath
    $sizeMB = [math]::Round($fileItem.Length / 1MB, 2)
    
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "[SUCCESS] AAB Bundle is signed and verified!" -ForegroundColor Green
    Write-Host "  File: $resolvedAabPath" -ForegroundColor White
    Write-Host "  Size: $sizeMB MB" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ready to upload to Google Play Console:" -ForegroundColor Cyan
    Write-Host "1. Open Google Play Console (https://play.google.com/console)." -ForegroundColor White
    Write-Host "2. Navigate to Testing -> Closed testing (or Internal testing)." -ForegroundColor White
    Write-Host "3. Create a new release and upload '$resolvedAabPath'." -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "[WARNING] jarsigner verification reported a warning or error." -ForegroundColor Yellow
}
