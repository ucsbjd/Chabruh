# Serves build/web at http://localhost:8060 (Ctrl+C to stop). Run build.ps1 first.
$Root = Split-Path -Parent $PSScriptRoot
python -I -m http.server 8060 --bind 127.0.0.1 -d "$Root\build\web"
