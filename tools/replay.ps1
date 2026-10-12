# Replays a recorded calibration session through the game's input and rider code and prints what the surfer did.
# Usage: .\tools\replay.ps1 [-Session calibration\session-X.json]   (default: the newest session)
param([string]$Session = '', [string[]]$Set = @())
. "$PSScriptRoot\_godot.ps1"
if (-not $Session) {
    $Session = (Get-ChildItem "$Root\calibration\session-*.json" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
}
if (-not [IO.Path]::IsPathRooted($Session)) { $Session = Join-Path (Get-Location) $Session }
& $Godot --headless --path "$Root\game" --script res://tests/replay_calibration.gd -- "$Session" @Set 2>&1 | Where-Object { $_ -notmatch '^Godot Engine|^$' }
