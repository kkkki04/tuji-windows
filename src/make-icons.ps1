# 序集 XUJI · 图标生成（Windows）
# 从 assets/logo-source.jpg 生成透明圆角的 assets/logo.png 和多尺寸 assets/icon.ico
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $root 'assets'
$srcPath = Join-Path $assets 'logo-source.jpg'
if (-not (Test-Path $srcPath)) { throw "找不到源图：$srcPath" }
New-Item -ItemType Directory -Force -Path $assets | Out-Null

$src = [System.Drawing.Bitmap]::FromFile($srcPath)

function Test-Green($c) { return ($c.G -gt 95 -and $c.G -gt ($c.R + 18) -and $c.G -gt ($c.B + 28)) }

$cx = [int]($src.Width / 2); $cy = [int]($src.Height / 2)
$left = 0; for ($x = 0; $x -lt $src.Width; $x++) { if (Test-Green $src.GetPixel($x, $cy)) { $left = $x; break } }
$right = $src.Width - 1; for ($x = $src.Width - 1; $x -ge 0; $x--) { if (Test-Green $src.GetPixel($x, $cy)) { $right = $x; break } }
$top = 0; for ($y = 0; $y -lt $src.Height; $y++) { if (Test-Green $src.GetPixel($cx, $y)) { $top = $y; break } }
$bottom = $src.Height - 1; for ($y = $src.Height - 1; $y -ge 0; $y--) { if (Test-Green $src.GetPixel($cx, $y)) { $bottom = $y; break } }
$cropRect = New-Object System.Drawing.Rectangle($left, $top, ($right - $left + 1), ($bottom - $top + 1))

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function New-TileBitmap([int]$Size) {
  $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $r = [float]($Size * 0.225)
  $path = New-RoundedPath 0 0 $Size $Size $r
  $g.SetClip($path, [System.Drawing.Drawing2D.CombineMode]::Replace)
  $dest = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
  $g.DrawImage($src, $dest, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
  $g.ResetClip(); $path.Dispose(); $g.Dispose()
  return $bmp
}

$master = New-TileBitmap 1024
$master.Save((Join-Path $assets 'logo.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()

$sizes = @(16,24,32,48,64,128,256)
$pngData = @()
foreach ($s in $sizes) {
  $b = New-TileBitmap $s
  $ms = New-Object System.IO.MemoryStream
  $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngData += ,$ms.ToArray()
  $b.Dispose(); $ms.Dispose()
}
$icoPath = Join-Path $assets 'icon.ico'
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $len = $pngData[$i].Length
  $bw.Write([Byte]$(if ($s -ge 256) { 0 } else { $s }))
  $bw.Write([Byte]$(if ($s -ge 256) { 0 } else { $s }))
  $bw.Write([Byte]0); $bw.Write([Byte]0)
  $bw.Write([UInt16]1); $bw.Write([UInt16]32)
  $bw.Write([UInt32]$len); $bw.Write([UInt32]$offset)
  $offset += $len
}
foreach ($d in $pngData) { $bw.Write($d) }
$bw.Close(); $fs.Close()
$src.Dispose()
Write-Host ("已生成：{0} / {1}" -f (Join-Path $assets 'logo.png'), $icoPath)
