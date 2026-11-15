# Fetches the libraries into deps/ at the versions this was built with, then patches RNNoise for MSVC.
# RED4ext.SDK is shared between the mods: tools/fetch-red4ext-sdk.ps1 at the repo's root fetches it.
$deps = Join-Path $PSScriptRoot '..\deps'
New-Item -ItemType Directory -Force $deps | Out-Null

function Get-Library($Name, $Url, $Tag, $Commit) {
    $target = Join-Path $deps $Name
    if (Test-Path $target) { return }
    if ($Commit) {
        git init --quiet $target
        git -C $target fetch --quiet --depth 1 $Url $Commit
        git -C $target checkout --quiet FETCH_HEAD
    }
    else { git clone --quiet --depth 1 --branch $Tag $Url $target }
}

Get-Library 'opus' 'https://github.com/xiph/opus.git' 'v1.5.2'
# The commit Voice was built and tested with, so a release build on GitHub uses the same libjuice as this PC.
Get-Library 'libjuice' 'https://github.com/paullouisageneau/libjuice.git' -Commit 'abe8dd3f33e696106fe322b90b67fd11b1fe51ab'
Get-Library 'rnnoise' 'https://github.com/xiph/rnnoise.git' 'v0.1.1'
Get-Library 'speexdsp' 'https://github.com/xiph/speexdsp.git' 'SpeexDSP-1.2.1'
Get-Library 'monocypher' 'https://github.com/LoupVaillant/Monocypher.git' '4.0.2'

# MSVC has no variable-length arrays in C, which RNNoise uses in two files.
$rnn = Join-Path $deps 'rnnoise\src'
$lpc = Get-Content "$rnn\celt_lpc.c" -Raw
$lpc = $lpc.Replace('opus_val16 xx[n];', 'opus_val16 *xx = (opus_val16*)_alloca(sizeof(opus_val16)*n);')
if ($lpc -notmatch 'malloc\.h') { $lpc = "#include <malloc.h>`n" + $lpc }
Set-Content "$rnn\celt_lpc.c" $lpc -NoNewline -Encoding ascii

$pitch = Get-Content "$rnn\pitch.c" -Raw
$pitch = $pitch.Replace('opus_val16 x_lp4[len>>2];', 'opus_val16 *x_lp4 = (opus_val16*)_alloca(sizeof(opus_val16)*(len>>2));')
$pitch = $pitch.Replace('opus_val16 y_lp4[lag>>2];', 'opus_val16 *y_lp4 = (opus_val16*)_alloca(sizeof(opus_val16)*(lag>>2));')
$pitch = $pitch.Replace('opus_val32 xcorr[max_pitch>>1];', 'opus_val32 *xcorr = (opus_val32*)_alloca(sizeof(opus_val32)*(max_pitch>>1));')
$pitch = $pitch.Replace('opus_val32 yy_lookup[maxperiod+1];', 'opus_val32 *yy_lookup = (opus_val32*)_alloca(sizeof(opus_val32)*(maxperiod+1));')
if ($pitch -notmatch 'malloc\.h') { $pitch = "#include <malloc.h>`n" + $pitch }
Set-Content "$rnn\pitch.c" $pitch -NoNewline -Encoding ascii
