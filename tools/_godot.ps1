# Dot-source this from the other scripts: . "$PSScriptRoot\_godot.ps1"
# Gives you $Root (repo root) and $Godot (path to the console build of Godot).
$Root = Split-Path -Parent $PSScriptRoot
$onPath = Get-Command godot_console -ErrorAction SilentlyContinue
$Godot = if ($onPath) { $onPath.Source } else { Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot_console.exe' }
if (-not (Test-Path $Godot)) {
    throw 'Godot not found. Install it with: winget install -e --id GodotEngine.GodotEngine'
}
