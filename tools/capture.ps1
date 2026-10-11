# Renders the game in a real window and saves a true-colour PNG (for judging looks).
# Usage: .\tools\capture.ps1 -Out shot.png [-Size 0.5] [-Hollow 0.5] [-Peel 0.45] [-Mood sunset] [-Frames 45]
param(
    [Parameter(Mandatory)][string]$Out,
    [double]$Size = 0.5,
    [double]$Hollow = 0.5,
    [double]$Peel = 0.45,
    [ValidateSet('golden', 'sunset', 'neon')][string]$Mood = 'sunset',
    [int]$Frames = 45
)
. "$PSScriptRoot\_godot.ps1"

$full = if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
& $Godot --path "$Root\game" --rendering-driver opengl3 --resolution 1280x720 --script res://tests/capture.gd -- "out=$full" "size=$Size" "hollow=$Hollow" "peel=$Peel" "mood=$Mood" "frames=$Frames"
