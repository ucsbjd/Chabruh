# Exports the web build to build/web/index.html (needs the 4.7.2 export templates installed).
. "$PSScriptRoot\_godot.ps1"

New-Item -ItemType Directory -Force "$Root\build\web" | Out-Null
& $Godot --headless --path "$Root\game" --import | Out-Null
& $Godot --headless --path "$Root\game" --export-release 'Web' ../build/web/index.html
if (-not (Test-Path "$Root\build\web\index.html")) { throw 'Export failed: build/web/index.html was not written.' }

Get-ChildItem "$Root\build\web" | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } }
