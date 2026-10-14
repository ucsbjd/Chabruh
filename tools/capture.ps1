# Renders the game in a real window and saves a true-colour PNG (for judging looks), and prints the
# average frame time. Add -Perf to turn vsync off, so the frame time shows what the GPU can sustain
# (give it plenty of -Frames). The run is killed after 2 minutes, so a broken scene cannot hang.
# Usage: .\tools\capture.ps1 -Out shot.png [-Size 0.5] [-Hollow 0.5] [-Peel 3.0] [-Mood sunset] [-Frames 45]
#                           [-Resolution 1280x720] [-Perf] [-Pose ride] [-Gallery]
#                           [-Snaps 60,90] saves extra frames as <out>-60.png; [-Burst '0.8@70'] fires a spray burst
# -Peel is how many meters ahead of the peel point the surfer is (negative is behind it, in the barrel).
param(
    [Parameter(Mandatory)][string]$Out,
    [double]$Size = 0.5,
    [double]$Hollow = 0.5,
    [double]$Peel = 3.0,
    [ValidateSet('golden', 'sunset', 'neon')][string]$Mood = 'sunset',
    [int]$Frames = 45,
    [string]$Resolution = '1280x720',
    [string]$Pose = 'ride',
    [string]$Snaps = '',
    [string]$Burst = '',
    [string]$Height = '',
    [string]$Surfer3d = '',
    [switch]$Gallery,
    [switch]$Perf
)
. "$PSScriptRoot\_godot.ps1"

$full = if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
$arguments = @('--path', "`"$Root\game`"", '--rendering-driver', 'opengl3', '--resolution', $Resolution)
if ($Perf) { $arguments += '--disable-vsync' }
$arguments += @('--quit-after', ($Frames + 300), '--script', 'res://tests/capture.gd', '--',
    "`"out=$full`"", "size=$Size", "hollow=$Hollow", "peel=$Peel", "mood=$Mood", "frames=$Frames", "pose=$Pose", "gallery=$(if ($Gallery) { 'yes' } else { 'no' })", "snaps=$Snaps", "burst=$Burst", "height=$Height", "s3d=$Surfer3d")

$process = Start-Process -FilePath $Godot -ArgumentList $arguments -NoNewWindow -PassThru
if (-not $process.WaitForExit(120000)) {
    $process.Kill()
    Write-Error 'capture timed out after 2 minutes and was stopped'
    exit 1
}
exit $process.ExitCode
