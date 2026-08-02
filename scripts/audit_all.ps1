# audit_all.ps1 — Comprehensive audit wrapper for NOVA (Windows/PowerShell)
# Runs all quality gates in sequence and fails fast on any error.
$ErrorActionPreference = 'Stop'

function Step {
    param([string]$Name, [scriptblock]$Cmd)
    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    & $Cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $Name" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "PASSED: $Name" -ForegroundColor Green
}

Step "TypeScript type-check" { pnpm run lint }
Step "ESLint"                 { pnpm run lint:eslint }
Step "Prettier format check"  { pnpm run format:check }
Step "i18n validate"          { pnpm run i18n:validate }
Step "Capability gating"      { pnpm run verify:capabilities }
Step "Branding assets"        { pnpm run branding:verify }
Step "Installer audit"        { pnpm run audit:installer }
Step "Unit tests"             { pnpm test }

Write-Host ""
Write-Host "All audit gates passed." -ForegroundColor Green
