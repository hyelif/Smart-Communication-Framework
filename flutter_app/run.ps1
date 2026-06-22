<#
.SYNOPSIS
    Run SmartPonic Flutter app with Turso tokens from .env file.

.DESCRIPTION
    Reads SMARTPONIC_TURSO_* variables from the .env file and passes them
    as --dart-define flags to flutter run. This keeps tokens out of source
    control while keeping the app fully functional.

    Usage:
        .\run.ps1                    # Run with .env tokens
        .\run.ps1 -- --verbose       # Pass extra flags to flutter run
        .\run.ps1 -Build             # Run flutter build instead of run

.EXAMPLE
    .\run.ps1
    .\run.ps1 -- --dart-define=SMARTPONIC_ENV=staging
    .\run.ps1 -Build -Flavor release
#>

param(
    [switch]$Build,
    [string]$Flavor
)

$envFile = Join-Path $PSScriptRoot ".env"

if (-not (Test-Path $envFile)) {
    Write-Error "❌ .env file not found at $envFile"
    Write-Error ""
    Write-Error "   Copy .env.example to .env and fill in your Turso tokens:"
    Write-Error "   Copy-Item .env.example .env"
    exit 1
}

# Parse .env file (skip comments and blank lines)
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2 -and $parts[1].Length -gt 0) {
            $envVars[$parts[0]] = $parts[1]
        }
    }
}

# Validate required tokens
$required = @('SMARTPONIC_TURSO_URL', 'SMARTPONIC_TURSO_READ_TOKEN', 'SMARTPONIC_TURSO_WRITE_TOKEN')
$missing = $required | Where-Object { -not $envVars.ContainsKey($_) -or [string]::IsNullOrEmpty($envVars[$_]) }

if ($missing.Count -gt 0) {
    Write-Error "❌ Missing required environment variables in .env:"
    $missing | ForEach-Object { Write-Error "   - $_" }
    exit 1
}

# Build --dart-define arguments
$defines = $envVars.Keys | ForEach-Object { "--dart-define=$_=$($envVars[$_])" }

Write-Host "🚀 Running SmartPonic with tokens from .env" -ForegroundColor Cyan
Write-Host "   URL: $($envVars['SMARTPONIC_TURSO_URL'])" -ForegroundColor Gray
Write-Host ""

# Collect extra args (everything after --)
$extraArgs = @()
$foundSeparator = $false
foreach ($arg in $args) {
    if ($arg -eq '--') { $foundSeparator = $true; continue }
    if ($foundSeparator) { $extraArgs += $arg }
}

# Build argument list
if ($Build) {
    $allArgs = @('build') + $defines + $extraArgs
    if ($Flavor) { $allArgs += "--$Flavor" }
} else {
    $allArgs = @('run') + $defines + $extraArgs
}

Write-Host "> flutter $($allArgs -join ' ')" -ForegroundColor DarkGray
& flutter @allArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Flutter exited with code $LASTEXITCODE"
    exit $LASTEXITCODE
}
