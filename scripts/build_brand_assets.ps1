# Build transparent brand assets from the founder's two JPEGs.
#
# "LOGO WITHOUT BACKGROUND.jpeg" is a near-white mark on pure black. That is
# mathematically the mark composited on black == premultiplied alpha, so the
# true transparent mark is recovered exactly by:
#     alpha = max(R,G,B)          (luminance of a white-on-black mask)
#     RGB'  = RGB / alpha * 255   (un-premultiply, restores the soft shading)
# Un-premultiplying matters: taking RGB as-is would leave a dark halo on every
# antialiased edge once the mark is composited on the navy disc.

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root "design/brand/logo-mark-on-black.jpeg"
$srcB = Join-Path $root "design/brand/logo-with-background.jpeg"
$out  = Join-Path $root "assets/icon"

function Get-ArgbBytes($bmp) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $len = [Math]::Abs($data.Stride) * $bmp.Height
    $buf = New-Object byte[] $len
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $len)
    $bmp.UnlockBits($data)
    return @{ Bytes = $buf; Stride = $data.Stride }
}

# ---------------------------------------------------------------- mask -> ARGB
$srcBmp = [System.Drawing.Bitmap]::FromFile($src)
Write-Output "source: $($srcBmp.Width)x$($srcBmp.Height)"
$g = Get-ArgbBytes $srcBmp
$buf = $g.Bytes; $stride = $g.Stride
$w = $srcBmp.Width; $h = $srcBmp.Height

$minX = $w; $minY = $h; $maxX = -1; $maxY = -1
for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $stride
    for ($x = 0; $x -lt $w; $x++) {
        $i = $row + $x * 4
        $b = $buf[$i]; $gr = $buf[$i+1]; $r = $buf[$i+2]
        $a = $b; if ($gr -gt $a) { $a = $gr }; if ($r -gt $a) { $a = $r }
        if ($a -gt 12) {
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
            # un-premultiply against black, then store as straight alpha
            $buf[$i]   = [byte][Math]::Min(255, [int](255 * $b  / $a))
            $buf[$i+1] = [byte][Math]::Min(255, [int](255 * $gr / $a))
            $buf[$i+2] = [byte][Math]::Min(255, [int](255 * $r  / $a))
            $buf[$i+3] = [byte]$a
        } else {
            $buf[$i] = 0; $buf[$i+1] = 0; $buf[$i+2] = 0; $buf[$i+3] = 0
        }
    }
}
Write-Output "mark bbox: x $minX..$maxX  y $minY..$maxY"

$maskBmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$md = $maskBmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
                        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $md.Scan0, $buf.Length)
$maskBmp.UnlockBits($md)

$cropW = $maxX - $minX + 1
$cropH = $maxY - $minY + 1
$cropRect = New-Object System.Drawing.Rectangle $minX, $minY, $cropW, $cropH

# Render the cropped mark centred on a transparent square canvas, occupying
# $fill of the canvas's longest side.
function Render-Mark([int]$canvas, [double]$fill, [string]$path) {
    $bmp = New-Object System.Drawing.Bitmap $canvas, $canvas, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.Clear([System.Drawing.Color]::Transparent)
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gfx.PixelOffsetMode  = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $target = $canvas * $fill
    $scale = [Math]::Min($target / $cropW, $target / $cropH)
    $dw = $cropW * $scale; $dh = $cropH * $scale
    $dest = New-Object System.Drawing.RectangleF (($canvas - $dw) / 2), (($canvas - $dh) / 2), $dw, $dh
    $gfx.DrawImage($maskBmp, $dest, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    $gfx.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $kb = [int]((Get-Item $path).Length / 1KB)
    Write-Output "wrote $path  ($canvas x $canvas, fill $fill, $kb KB)"
}

# In-app mark: matches how the old wordmark filled its tiles (~86%).
Render-Mark 1024 0.86 (Join-Path $out "logo.png")
# Android adaptive foreground: ~60% keeps the mark clear of round/squircle masks.
Render-Mark 1024 0.60 (Join-Path $out "app_icon_foreground.png")

# ------------------------------------------------- square store / iOS icon
# Sample the founder's blue from the supplied "with background" artwork so the
# generated square icon matches it rather than a colour I invented.
$bgBmp = [System.Drawing.Bitmap]::FromFile($srcB)
$c1 = $bgBmp.GetPixel([int]($bgBmp.Width * 0.20), [int]($bgBmp.Height * 0.14))
$c2 = $bgBmp.GetPixel([int]($bgBmp.Width * 0.82), [int]($bgBmp.Height * 0.86))
Write-Output ("sampled brand blue: #{0:X2}{1:X2}{2:X2} -> #{3:X2}{4:X2}{5:X2}" -f $c1.R,$c1.G,$c1.B,$c2.R,$c2.G,$c2.B)
$bgBmp.Dispose()

$icon = New-Object System.Drawing.Bitmap 1024, 1024, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$ig = [System.Drawing.Graphics]::FromImage($icon)
$ig.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$ig.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$full = New-Object System.Drawing.Rectangle 0, 0, 1024, 1024
# Full-bleed gradient: iOS and Play apply their own corner mask, so the square
# must NOT carry the artwork's own rounded corners or it gets black corners.
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point 0, 0),
    (New-Object System.Drawing.Point 1024, 1024), $c1, $c2)
$ig.FillRectangle($brush, $full)
$scale2 = [Math]::Min((1024 * 0.62) / $cropW, (1024 * 0.62) / $cropH)
$dw2 = $cropW * $scale2; $dh2 = $cropH * $scale2
$dest2 = New-Object System.Drawing.RectangleF ((1024 - $dw2) / 2), ((1024 - $dh2) / 2), $dw2, $dh2
$ig.DrawImage($maskBmp, $dest2, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
$ig.Dispose(); $brush.Dispose()
$iconPath = Join-Path $out "app_icon.png"
$icon.Save($iconPath, [System.Drawing.Imaging.ImageFormat]::Png)
$icon.Dispose()
Write-Output "wrote $iconPath ($([int]((Get-Item $iconPath).Length / 1KB)) KB)"

$maskBmp.Dispose(); $srcBmp.Dispose()
Write-Output "DONE"
