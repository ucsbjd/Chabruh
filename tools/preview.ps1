# Deploys build/web to a temporary Firebase preview channel for checking on a phone.
# Usage: .\tools\preview.ps1 -Step 1   (prints a URL like https://chabruh-surf--step-1-xxxx.web.app)
param([Parameter(Mandatory)][int]$Step)

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
firebase hosting:channel:deploy "step-$Step" --project chabruh-surf --expires 7d
