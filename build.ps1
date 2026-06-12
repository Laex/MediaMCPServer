# Entry point - delegates to scripts/build.ps1
& (Join-Path $PSScriptRoot 'scripts\build.ps1') @args
