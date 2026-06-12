# Entry point - delegates to scripts/install.ps1
& (Join-Path $PSScriptRoot 'scripts\install.ps1') @args
