# Runs the headless checks. Exits non-zero if any check fails or the engine prints an error.
#   1. the unit checks in game/tests/run_tests.gd
#   2. the real main scene for 120 frames; Godot prints shader and script errors but still
#      exits 0, so the output is scanned for them
. "$PSScriptRoot\_godot.ps1"

& $Godot --headless --path "$Root\game" --import | Out-Null

$unit = & $Godot --headless --path "$Root\game" --script res://tests/run_tests.gd 2>&1 | ForEach-Object { "$_" }
$unitExit = $LASTEXITCODE
$unit

$run = & $Godot --headless --path "$Root\game" --quit-after 120 2>&1 | ForEach-Object { "$_" }
$errors = $run | Where-Object { $_ -match 'SHADER ERROR|SCRIPT ERROR|Parse Error|^ERROR:' }
if ($errors) {
    'Running the main scene printed errors:'
    $errors
} else {
    'scene run: 120 frames, no errors'
}

exit ([int]($unitExit -ne 0 -or [bool]$errors))
