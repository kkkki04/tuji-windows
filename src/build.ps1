# 序集 XUJI · 打包脚本
# 作用：下载 WebView2 SDK → 用系统自带 csc 编译出单文件 exe（图标来自 assets/icon.ico）
param(
  [string]$OutDir = '',
  [string]$ExeName = '序集.exe'
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

# ---------- 2. 应用图标 ----------
$icoPath = Join-Path $projectDir 'assets\icon.ico'
if (-not (Test-Path $icoPath)) {
  throw "找不到应用图标：$icoPath（请先运行 src/make-icons.ps1 生成）"
}

# ---------- 3. 编译 ----------
$html = Join-Path $projectDir 'index.html'
if (-not (Test-Path $html)) { throw "找不到 index.html：$html" }

$exe = Join-Path $OutDir $ExeName
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
