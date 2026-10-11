# Runs the headless smoke tests. Exits non-zero if any check fails.
. "$PSScriptRoot\_godot.ps1"

& $Godot --headless --path "$Root\game" --import | Out-Null
& $Godot --headless --path "$Root\game" --script res://tests/run_tests.gd
exit $LASTEXITCODE
