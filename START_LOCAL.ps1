# ASCII-only launcher to avoid Windows PowerShell encoding/parser errors.
$ErrorActionPreference = "Stop"

try {
  $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Homework Handwriting Generator" -ForegroundColor Cyan
Write-Host "  Web: http://localhost:8080" -ForegroundColor Cyan
Write-Host "  Backend: http://127.0.0.1:5005" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Force -Path `
  "$Root\ttf_files", `
  "$Root\logs", `
  "$Root\backend\temp", `
  "$Root\backend\textfileprocess", `
  "$Root\backend\imagefileprocess" | Out-Null

$pythonCmd = $null
$pythonArgs = @()
if (Get-Command py -ErrorAction SilentlyContinue) {
  foreach ($v in @("-3.11", "-3.12", "-3.10", "-3")) {
    & py $v -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) {
      $pythonCmd = "py"
      $pythonArgs = @($v)
      break
    }
  }
}
if (-not $pythonCmd -and (Get-Command python -ErrorAction SilentlyContinue)) {
  $pythonCmd = "python"
  $pythonArgs = @()
}
if (-not $pythonCmd) {
  Write-Host "Python was not found. Please install Python 3.10 or 3.11 and enable Add Python to PATH." -ForegroundColor Red
  Read-Host "Press Enter to exit"
  exit 1
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Write-Host "Node.js/npm was not found. Please install Node.js LTS." -ForegroundColor Red
  Read-Host "Press Enter to exit"
  exit 1
}

$envFile = "$Root\backend\.env"
# Privacy mode: never keep old DeepSeek keys in .env.
@"
DEEPSEEK_API_KEY=
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-chat
"@ | Set-Content -Path $envFile -Encoding UTF8

Write-Host "DeepSeek API Key is required in the web popup after the page opens. It is not saved to .env." -ForegroundColor Yellow
Write-Host ""

Write-Host "[1/4] Preparing Python virtual environment..." -ForegroundColor Green
$venvPython = "$Root\.venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
  & $pythonCmd @pythonArgs -m venv "$Root\.venv"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create Python virtual environment." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
  }
}

Write-Host "[2/4] Installing/checking backend dependencies..." -ForegroundColor Green
& $venvPython -c "import sys; print('Python', sys.version)"
& $venvPython -m pip cache purge | Out-Null
& $venvPython -m pip install -U pip setuptools wheel
& $venvPython -m pip install --prefer-binary -r "$Root\backend\requirements.txt"
if ($LASTEXITCODE -ne 0) {
  Write-Host "Default PyPI failed. Retrying with Tsinghua mirror..." -ForegroundColor Yellow
  & $venvPython -m pip install --prefer-binary -r "$Root\backend\requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Backend dependency installation failed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
  }
}
& $venvPython -m pip install --prefer-binary handrightbeta==8.7.0 --no-deps
if ($LASTEXITCODE -ne 0) {
  Write-Host "Installing handrightbeta failed. Retrying with Tsinghua mirror..." -ForegroundColor Yellow
  & $venvPython -m pip install --prefer-binary handrightbeta==8.7.0 --no-deps -i https://pypi.tuna.tsinghua.edu.cn/simple
  if ($LASTEXITCODE -ne 0) {
    Write-Host "handrightbeta installation failed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
  }
}

Write-Host "[3/4] Installing/checking frontend dependencies..." -ForegroundColor Green
Set-Location "$Root\frontend"
if (-not (Test-Path "$Root\frontend\node_modules")) {
  npm install
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Default npm registry failed. Retrying with npmmirror..." -ForegroundColor Yellow
    npm install --registry=https://registry.npmmirror.com
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Frontend dependency installation failed." -ForegroundColor Red
      Read-Host "Press Enter to exit"
      exit 1
    }
  }
}
Set-Location $Root

Write-Host "[4/4] Starting backend and frontend..." -ForegroundColor Green
$backendCmd = "`$env:FONT_ASSETS_DIR='$Root\ttf_files'; `$env:FONT_ASSETS_BUNDLED_DIR='$Root\backend\font_assets'; Set-Location -LiteralPath '$Root\backend'; & '$venvPython' app.py"
$frontendCmd = "Set-Location -LiteralPath '$Root\frontend'; npm run serve"

Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-Command',$backendCmd)
Start-Sleep -Seconds 3
Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-Command',$frontendCmd)
Start-Sleep -Seconds 8
Start-Process "http://localhost:8080"

Write-Host ""
Write-Host "Started. Browser should open: http://localhost:8080" -ForegroundColor Cyan
Write-Host "Put .ttf/.otf font files into: ttf_files" -ForegroundColor Cyan
Write-Host "Handwriting PDF samples are in: my_handwriting_samples_pdf" -ForegroundColor Cyan
Write-Host "To stop: close the two new PowerShell windows." -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to close this launcher window"
