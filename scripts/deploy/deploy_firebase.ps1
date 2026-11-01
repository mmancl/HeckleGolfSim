<#
.SYNOPSIS
    Deploy Firebase Hosting, Firestore, Database, and/or Functions to Firebase project heckle-golf-sim.
.DESCRIPTION
    Wraps Firebase CLI to deploy website files, security rules, Realtime Database, and Cloud Functions.
.EXAMPLE
    .\deploy_firebase.ps1
    .\deploy_firebase.ps1 -Target hosting
    .\deploy_firebase.ps1 -Target firestore:rules
    .\deploy_firebase.ps1 -Target database
    .\deploy_firebase.ps1 -Target functions
    .\deploy_firebase.ps1 -Message "Updated rules and functions"
#>

[CmdletBinding()]
param(
    [ValidateSet("all", "hosting", "firestore:rules", "firestore", "database", "functions")]
    [string]$Target = "all",

    [string]$Project = "heckle-golf-sim",

    [string]$Message = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
Push-Location $repoRoot

try {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host " Heckle Golf Simulator - Firebase Deployment" -ForegroundColor Cyan
    Write-Host " Project: $Project | Target: $Target" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan

    $deployArgs = @("--project", $Project)

    if ($Target -ne "all") {
        $deployArgs += @("--only", $Target)
    }

    if ($Message) {
        $deployArgs += @("-m", $Message)
    }

    # Prefer local or global firebase CLI, fallback to npx
    if (Get-Command firebase -ErrorAction SilentlyContinue) {
        Write-Host "Running: firebase deploy $($deployArgs -join ' ')" -ForegroundColor Yellow
        & firebase deploy @deployArgs
    } elseif (Get-Command npx -ErrorAction SilentlyContinue) {
        Write-Host "Running: npx firebase-tools deploy $($deployArgs -join ' ')" -ForegroundColor Yellow
        & npx firebase-tools deploy @deployArgs
    } else {
        Write-Error "Firebase CLI or npx not found. Please install Node.js and run 'npm install -g firebase-tools'."
    }
} finally {
    Pop-Location
}
