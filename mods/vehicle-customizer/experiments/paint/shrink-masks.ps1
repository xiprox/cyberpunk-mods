# Step 2b of the shop paints: each exported mask layer (cache/masks/**/<mask>_<n>.png) as 64 by 64 grey bytes beside it
# (<mask>_<n>.g64), for plan-paints.py to work out which layer covers the most of a body without a slow PNG reader.
$root = Join-Path $PSScriptRoot 'cache\masks'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
public static class Shrink {
    public static void Run(string png) {
        const int N = 64;
        using (var src = new Bitmap(png))
        using (var small = new Bitmap(N, N, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(small)) {
            g.InterpolationMode = InterpolationMode.HighQualityBilinear;
            g.DrawImage(src, new Rectangle(0, 0, N, N));
            var d = small.LockBits(new Rectangle(0, 0, N, N), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var bgra = new byte[N * N * 4];
            Marshal.Copy(d.Scan0, bgra, 0, bgra.Length);
            small.UnlockBits(d);
            var grey = new byte[N * N];
            for (int i = 0; i < grey.Length; i++) grey[i] = bgra[i * 4 + 1];
            File.WriteAllBytes(Path.ChangeExtension(png, ".g64"), grey);
        }
    }
}
'@
$n = 0
foreach ($f in Get-ChildItem $root -Recurse -File -Filter *.png) {
    [Shrink]::Run($f.FullName)
    $n++
}
"$n layers shrunk"
