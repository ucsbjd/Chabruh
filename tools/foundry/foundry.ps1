# One command: Blender renders the surfer in six poses, the packer builds the game frames, the checks run.
# Usage: tools\foundry\foundry.ps1 [-Frames 6]
param([int]$Frames = 6, [string]$Name = "surfer")
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repo = Resolve-Path "$here\..\.."
$blender = Get-ChildItem "$env:ProgramFiles\Blender Foundation\Blender 4.5\blender.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $blender) { $blender = (Get-Command blender -ErrorAction Stop).Source } else { $blender = $blender.FullName }
$work = "$here\work\$Name"
$decals = "$here\work\decals"
$out = "$repo\game\assets\sprites\surfer"
New-Item -ItemType Directory -Force $work, $out, $decals | Out-Null
$clock = [Diagnostics.Stopwatch]::StartNew()
uv run --project $here python "$here\make_decals.py" $decals
& $blender -b --python "$here\render_character.py" -- $work $decals $Frames | Where-Object { $_ -match "^foundry:|Error|Traceback" }
if ($LASTEXITCODE -ne 0) { throw "Blender failed" }
$render = $clock.Elapsed.TotalSeconds
uv run --project $here python "$here\pack_frames.py" $work $out $Frames $Name
uv run --project $here python "$here\check_frames.py" $out $Name $Frames "$work\contact.png" "$work\meta.json"
if ($LASTEXITCODE -ne 0) { throw "checks failed" }
"render {0:N1} s for {1} poses, total {2:N1} s" -f $render, $Frames, $clock.Elapsed.TotalSeconds
