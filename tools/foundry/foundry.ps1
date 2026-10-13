# One command: Blender renders the placeholder surfer, the packer builds the game frames, the checks run.
# Usage: tools\foundry\foundry.ps1 [-Frames 8]
param([int]$Frames = 8, [string]$Name = "placeholder")
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repo = Resolve-Path "$here\..\.."
$blender = Get-ChildItem "$env:ProgramFiles\Blender Foundation\Blender 4.5\blender.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $blender) { $blender = (Get-Command blender -ErrorAction Stop).Source } else { $blender = $blender.FullName }
$work = "$here\work\$Name"
$out = "$repo\game\assets\sprites\surfer"
New-Item -ItemType Directory -Force $work, $out | Out-Null
$clock = [Diagnostics.Stopwatch]::StartNew()
& $blender -b --python "$here\render_placeholder.py" -- $work $Frames | Where-Object { $_ -match "^foundry:|Error|Traceback" }
if ($LASTEXITCODE -ne 0) { throw "Blender failed" }
$render = $clock.Elapsed.TotalSeconds
uv run --project $here python "$here\pack_frames.py" $work $out $Frames $Name
uv run --project $here python "$here\check_frames.py" $out $Name $Frames "$work\contact.png"
if ($LASTEXITCODE -ne 0) { throw "checks failed" }
"render {0:N1} s for {1} frames, total {2:N1} s" -f $render, $Frames, $clock.Elapsed.TotalSeconds
