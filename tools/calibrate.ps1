# Opens the game in calibration mode: it asks for each move five times and records your trackpad or mouse.
# The result is calibration/session-*.json (gitignored: it is personal data); then run
#   python tools\analyze_calibration.py
# Usage: .\tools\calibrate.ps1 [-Resolution 1280x720]
param([string]$Resolution = '1280x720')
. "$PSScriptRoot\_godot.ps1"
Start-Process -FilePath $Godot -ArgumentList @('--path', "`"$Root\game`"", '--resolution', $Resolution, '--', '--calibrate')
