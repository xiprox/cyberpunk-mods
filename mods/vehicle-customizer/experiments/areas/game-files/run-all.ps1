# Runs every probe in order and saves its output to results/, dated.
# Run with: powershell -File experiments/areas/game-files/run-all.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$date = Get-Date -Format 'yyyy-MM-dd'
New-Item -ItemType Directory -Force "$here\data", "$here\results" | Out-Null
$probes = 'scan-paths', 'parts', 'appearances', 'part-classes', 'sizes-and-crystalcoat', 'options-per-car', 'paints', 'bikes', 'test-car', 'test-bike', 'record-ids', 'hella-wheels', 'sectors', 'garages'
foreach ($probe in $probes) {
    python -I "$here\$probe.py" | Out-File -Encoding utf8 "$here\results\$probe-$date.txt"
    "$probe exit $LASTEXITCODE"
}
