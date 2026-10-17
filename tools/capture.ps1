# Renders the game in a real window and saves a true-colour PNG (for judging looks), and prints the
# average frame time. Add -Perf to turn vsync off, so the frame time shows what the GPU can sustain
# (give it plenty of -Frames). The run is killed after 2 minutes, so a broken scene cannot hang.
# Usage: .\tools\capture.ps1 -Out shot.png [-Size 0.5] [-Hollow 0.5] [-Peel 3.0] [-Mood sunset] [-Frames 45]
#                           [-Resolution 1280x720] [-Perf] [-Pose ride] [-Gallery]
#                           [-Snaps 60,90] saves extra frames as <out>-60.png; [-Burst '0.8@70'] fires a spray burst
#                           [-Carve 3] carves up and down the face, one cycle every 3 s; [-Readout] shows the debug readout
#                           [-Ride cycle] drop, bottom turn, hit the lip, every 4.4 s; [-Ride stall] steer back 3 s, let go
#                           [-Ride cutback] the C key's cutback; [-Ride chase] pumping; [-Ride floater] along the top
#                           [-Move lip_hit|cutback|floater|tube|pump] plays a hotkey move over and over
#                           [-Solar 2.9] the evening at that time, with its tide; [-Events 'bowl@0,wipeout@200'] test events
#                           [-Reef] lets sections come by themselves; [-NoOverlay] hides the test buttons
# -Peel is how many meters ahead of the peel point the surfer is (negative is behind it, in the barrel).
param(
    [Parameter(Mandatory)][string]$Out,
    [double]$Size = 0.5,
    [double]$Hollow = 0.5,
    [double]$Peel = 3.0,
    [ValidateSet('golden', 'sunset', 'neon', 'dusk', 'bioluminescent')][string]$Mood = 'sunset',
    [int]$Frames = 45,
    [string]$Resolution = '1280x720',
    [string]$Pose = 'ride',
    [string]$Snaps = '',
    [string]$Burst = '',
    [string]$Height = '',
    [string]$Surfer3d = '',
    [int]$Cycle = 0,
    [double]$Carve = 0,
    [switch]$Readout,
    [ValidateSet('', 'cycle', 'stall', 'cutback', 'chase', 'floater')][string]$Ride = '',
    [ValidateSet('', 'lip_hit', 'cutback', 'floater', 'tube', 'pump')][string]$Move = '',
    [double]$Camera = 0,
    [string]$Solar = '',
    [string]$Events = '',
    [switch]$Reef,
    [switch]$NoOverlay,
    [switch]$Gallery,
    [switch]$Perf
)
. "$PSScriptRoot\_godot.ps1"

$full = if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
# A fixed 60 frames a second of game time, so frame N is always the same moment of the ride however fast the GPU is.
$arguments = @('--path', "`"$Root\game`"", '--rendering-driver', 'opengl3', '--resolution', $Resolution, '--fixed-fps', '60')
if ($Perf) { $arguments += '--disable-vsync' }
$arguments += @('--quit-after', ($Frames + 300), '--script', 'res://tests/capture.gd', '--',
    "`"out=$full`"", "size=$Size", "hollow=$Hollow", "peel=$Peel", "mood=$Mood", "frames=$Frames", "pose=$Pose", "gallery=$(if ($Gallery) { 'yes' } else { 'no' })", "snaps=$Snaps", "burst=$Burst", "height=$Height", "s3d=$Surfer3d", "cycle=$Cycle", "carve=$Carve", "readout=$(if ($Readout) { 'yes' } else { 'no' })", "ride=$Ride", "move=$Move", "camera=$Camera", "solar=$Solar", "events=$Events", "reef=$(if ($Reef) { 'on' } else { 'off' })", "overlay=$(if ($NoOverlay) { 'no' } else { 'yes' })")

$process = Start-Process -FilePath $Godot -ArgumentList $arguments -NoNewWindow -PassThru
if (-not $process.WaitForExit(120000)) {
    $process.Kill()
    Write-Error 'capture timed out after 2 minutes and was stopped'
    exit 1
}
exit $process.ExitCode
