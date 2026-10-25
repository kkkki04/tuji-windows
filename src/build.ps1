# 图记 · 打包脚本
# 作用：下载 WebView2 SDK → 生成图标 → 用系统自带 csc 编译出单文件 exe
param(
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

$srcDir = $PSScriptRoot                       # ...\picnote\src
$projectDir = Split-Path $srcDir -Parent      # ...\picnote
if (-not $OutDir) { $OutDir = Split-Path $projectDir -Parent }   # ...\OP

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { throw "找不到 csc.exe：$csc" }

$work = Join-Path $env:LOCALAPPDATA 'TuJiBuild'
$sdkDir = Join-Path $work 'wv2'
$objDir = Join-Path $work 'obj'
New-Item -ItemType Directory -Force -Path $sdkDir, $objDir | Out-Null

# ---------- 1. 准备 WebView2 SDK ----------
$coreDll = Join-Path $sdkDir 'Microsoft.Web.WebView2.Core.dll'
$wfDll = Join-Path $sdkDir 'Microsoft.Web.WebView2.WinForms.dll'
$loaderDll = Join-Path $sdkDir 'WebView2Loader.dll'

if (-not (Test-Path $coreDll) -or -not (Test-Path $wfDll) -or -not (Test-Path $loaderDll)) {
  Write-Host '正在下载 WebView2 SDK…'
  $index = Invoke-RestMethod 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json'
  $version = $index.versions | Where-Object { $_ -notmatch '-' } | Select-Object -Last 1
  $nupkg = Join-Path $work "wv2.$version.zip"
  Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$version/microsoft.web.webview2.$version.nupkg" -OutFile $nupkg -UseBasicParsing

  $extract = Join-Path $work "pkg.$version"
  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  Expand-Archive $nupkg -DestinationPath $extract -Force

  Copy-Item (Join-Path $extract 'lib\net462\Microsoft.Web.WebView2.Core.dll') $coreDll -Force
  Copy-Item (Join-Path $extract 'lib\net462\Microsoft.Web.WebView2.WinForms.dll') $wfDll -Force
  Copy-Item (Join-Path $extract 'runtimes\win-x64\native\WebView2Loader.dll') $loaderDll -Force
  Write-Host "WebView2 SDK $version 就绪"
} else {
  Write-Host 'WebView2 SDK 已缓存'
}

# ---------- 2. 生成图标 ----------
$icoPath = Join-Path $objDir 'app.ico'
Add-Type -AssemblyName System.Drawing

$size = 256
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::Transparent)

$pad = 10; $d = $size - $pad * 2; $r = 54
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc($pad, $pad, $r, $r, 180, 90)
$path.AddArc($pad + $d - $r, $pad, $r, $r, 270, 90)
$path.AddArc($pad + $d - $r, $pad + $d - $r, $r, $r, 0, 90)
$path.AddArc($pad, $pad + $d - $r, $r, $r, 90, 90)
$path.CloseFigure()

$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  (New-Object System.Drawing.Point(0, 0)),
  (New-Object System.Drawing.Point($size, $size)),
  [System.Drawing.Color]::FromArgb(255, 16, 122, 113),
  [System.Drawing.Color]::FromArgb(255, 15, 84, 80))
$g.FillPath($brush, $path)

$font = New-Object System.Drawing.Font('Microsoft YaHei', 132, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$g.DrawString('图', $font, [System.Drawing.Brushes]::White,
  (New-Object System.Drawing.RectangleF(0, 8, $size, $size)), $sf)
$g.Dispose()

$pngStream = New-Object System.IO.MemoryStream
$bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
$png = $pngStream.ToArray()
$bmp.Dispose()
$pngStream.Dispose()

# 写 PNG 压缩格式的 ico（Windows Vista+ 支持）
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]1)
$bw.Write([Byte]0); $bw.Write([Byte]0); $bw.Write([Byte]0); $bw.Write([Byte]0)
$bw.Write([UInt16]1); $bw.Write([UInt16]32)
$bw.Write([UInt32]$png.Length); $bw.Write([UInt32]22)
$bw.Write($png)
$bw.Close(); $fs.Close()

# ---------- 3. 编译 ----------
$html = Join-Path $projectDir 'index.html'
if (-not (Test-Path $html)) { throw "找不到 index.html：$html" }

$exe = Join-Path $OutDir '图记.exe'
Write-Host "正在编译 → $exe"

$args = @(
  '/nologo', '/target:winexe', '/platform:x64', '/optimize+',
  "/win32icon:$icoPath",
  "/out:$exe",
  "/r:$coreDll",
  "/r:$wfDll",
  '/r:System.dll', '/r:System.Core.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll',
  "/resource:$html,index.html",
  "/resource:$loaderDll,WebView2Loader.dll",
  "/resource:$coreDll,Microsoft.Web.WebView2.Core.dll",
  "/resource:$wfDll,Microsoft.Web.WebView2.WinForms.dll",
  (Join-Path $srcDir 'Program.cs')
)

$output = & $csc @args 2>&1
if ($LASTEXITCODE -ne 0) {
  $output | ForEach-Object { Write-Host $_ }
  throw "编译失败（csc 退出码 $LASTEXITCODE）"
}
$output | ForEach-Object { Write-Host $_ }

$info = Get-Item $exe
Write-Host ("编译完成：{0}（{1:N1} KB）" -f $info.FullName, ($info.Length / 1KB))
