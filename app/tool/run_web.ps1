# Run the Concord Flutter app in Chrome for local dev iteration.
#
# This is the browser-side "simulator" — the primary loop on Windows,
# where iOS Simulator isn't available. Backend (concord-backend.vercel.app)
# is hit directly; the deployed CORS helper now allows the localhost
# origin.
#
# Usage:
#   .\tool\run_web.ps1
#
# Env vars are read from `.env` (already present, gitignored) and forwarded
# as --dart-define. Web can't use the dotenv loader because there's no
# file system to read from in the browser bundle.
#
# On any Dart source change, hot reload is automatic (press `r`). On a
# `pubspec.yaml` change, press `R` for hot restart. Press `q` to quit.

$ErrorActionPreference = "Stop"
$envPath = Join-Path $PSScriptRoot ".." ".env"
if (-not (Test-Path $envPath)) {
    Write-Error ".env not found at $envPath. Copy .env.example to .env first."
    exit 1
}

# Locate the Flutter SDK. Default to D:\flutter (where this user installs it).
$flutterBin = "D:\flutter\bin\flutter.cmd"
if (-not (Test-Path $flutterBin)) {
    # Fall back to whatever's on PATH.
    $flutterBin = (Get-Command flutter.cmd -ErrorAction SilentlyContinue).Source
    if (-not $flutterBin) {
        Write-Error "Flutter not found at D:\flutter\bin\flutter.cmd or on PATH."
        exit 1
    }
}

# Read .env into a hashtable. Skip blank lines and comments.
$envVars = @{}
foreach ($line in Get-Content $envPath) {
    if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
    $parts = $line -split '=', 2
    if ($parts.Length -ne 2) { continue }
    $key = $parts[0].Trim()
    $val = $parts[1].Trim().Trim('"').Trim("'")
    $envVars[$key] = $val
}

# Build the --dart-define list. AppEnv prefers String.fromEnvironment over
# dotenv, so these are the source of truth on web.
$defines = @()
foreach ($key in @("SUPABASE_URL", "SUPABASE_ANON_KEY", "API_BASE_URL", "SENTRY_DSN_IOS", "POSTHOG_API_KEY", "POSTHOG_HOST")) {
    if ($envVars.ContainsKey($key) -and $envVars[$key]) {
        $defines += "--dart-define=$key=$($envVars[$key])"
    }
}

Write-Host ""
Write-Host "→ Launching Concord in Chrome at http://localhost:8080" -ForegroundColor Cyan
Write-Host "  Backend:    $($envVars['API_BASE_URL'])"
Write-Host "  Supabase:   $($envVars['SUPABASE_URL'])"
Write-Host "  Hot reload: enabled (press `r` to reload, `q` to quit)"
Write-Host ""

# Run flutter. --web-port keeps the port stable so bookmarked URLs work.
$port = 8080
& $flutterBin run -d chrome --web-port=$port @defines
