# Puts a test run's close-up pictures side by side on labelled sheets, to look over many vehicles at once.
#   powershell -File tools/contact-sheet.ps1 -Run dev\runs\<time>_sweep
# Writes contact-1.jpg, contact-2.jpg, ... into the run's folder, PerSheet pictures each, named under each picture
# by its file name without "sweep_" and "_close".
param(
    [Parameter(Mandatory = $true)][string]$Run,
    [string]$Pattern = '*_close.jpg',
    [int]$Columns = 6,
    [int]$PerSheet = 48,
    [int]$Width = 420
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$files = @(Get-ChildItem $Run -Filter $Pattern | Sort-Object Name)
if ($files.Count -eq 0) { throw "no pictures matching $Pattern in $Run" }
$first = [System.Drawing.Image]::FromFile($files[0].FullName)
$height = [int]($Width * $first.Height / $first.Width)
$first.Dispose()
$label = 22
$font = New-Object System.Drawing.Font "Segoe UI", 10
$sheet = 0
for ($start = 0; $start -lt $files.Count; $start += $PerSheet) {
    $sheet++
    $batch = $files[$start..([Math]::Min($start + $PerSheet, $files.Count) - 1)]
    $rows = [Math]::Ceiling($batch.Count / $Columns)
    $bmp = New-Object System.Drawing.Bitmap ($Columns * $Width), ($rows * ($height + $label))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(24, 24, 24))
    $g.InterpolationMode = 'HighQualityBicubic'
    for ($i = 0; $i -lt $batch.Count; $i++) {
        $x = ($i % $Columns) * $Width
        $y = [Math]::Floor($i / $Columns) * ($height + $label)
        $img = [System.Drawing.Image]::FromFile($batch[$i].FullName)
        $g.DrawImage($img, $x, $y, $Width, $height)
        $img.Dispose()
        $name = $batch[$i].BaseName -replace '^sweep_', '' -replace '_close$', ''
        $g.DrawString($name, $font, [System.Drawing.Brushes]::White, $x + 4, $y + $height + 2)
    }
    $out = Join-Path $Run "contact-$sheet.jpg"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $g.Dispose(); $bmp.Dispose()
    "wrote $out ($($batch.Count) pictures)"
}
