# start-pc-model-services.ps1 — 把「手机能用的模型通路」两件套拉起来（幂等）
#
# 手机上的 DSH（Termux 里那个）本身不需要网络，它的「脑子」在家里这台 PC 上：
#
#   手机 ──(Tailscale 组网 / 家里局域网)──►  PC:8083  ──►  127.0.0.1:11434 (Ollama)
#                                            └ loopback-proxy.mjs 转发
#
# 两个进程都必须活着，缺一个手机就"没脑子"：
#   1) Ollama      监听 11434（启动文件夹里有 Ollama.lnk 自启，但被手动退出后不会自己回来）
#   2) 回环代理    监听 8083 → 转发到 11434（因为 dsh 只肯听 127.0.0.1 的做法在这里不适用，
#                  Ollama 默认只听 127.0.0.1，所以需要它把 11434 暴露给局域网/组网）
#
# 本脚本只做三件事，且**不会**改动任何自启项：探测 → 没起就起 → 复核并打印实测结果。
# 重复执行是安全的（已在跑就跳过）。
#
# 用法：双击本文件；或 powershell -ExecutionPolicy Bypass -File <本文件>
#      加 -ProxyOnly 则只拉起 8083 代理、完全不碰 Ollama —— **开机自启走的就是这一档**
#      （用户 2026-09-25 的决定：代理只占几十 MB 内存、不碰显存，值得常驻；Ollama 保持手动，
#        因为它一被请求就把 13 GB 往显存里塞，会跟出图抢卡。）

param(
  [switch]$ProxyOnly
)

$ErrorActionPreference = 'Continue'

$OllamaExe  = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'
# 按"本脚本所在目录"定位兄弟文件：写死绝对路径的话，别人 clone 下来直接就是错的
$ProxyScript = Join-Path $PSScriptRoot 'loopback-proxy.mjs'
$ProxyListen = '0.0.0.0:8083'
$ProxyTarget = '127.0.0.1:11434'

function Test-Port([int]$port) {
  return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-Port([int]$port, [int]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Port $port) { return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

Write-Host '== 拉起 PC 侧模型通路' -ForegroundColor Cyan
if ($ProxyOnly) { Write-Host '  （-ProxyOnly：只处理代理，不碰 Ollama）' }

# --- 1) Ollama ---
if ($ProxyOnly) {
  Write-Host '  [1/2] 跳过 Ollama（-ProxyOnly）。'
} elseif (Test-Port 11434) {
  Write-Host '  [1/2] Ollama 11434 已在监听，跳过。'
} else {
  if (-not (Test-Path $OllamaExe)) {
    Write-Warning "  找不到 Ollama 启动器：$OllamaExe"
  } else {
    Write-Host '  [1/2] 启动 Ollama …'
    Start-Process -FilePath $OllamaExe | Out-Null
    if (Wait-Port 11434 45) { Write-Host '        11434 已就绪。' -ForegroundColor Green }
    else { Write-Warning '        等了 45 秒仍没等到 11434，请手动打开 Ollama 看看。' }
  }
}

# --- 2) 回环代理 ---
if (Test-Port 8083) {
  Write-Host '  [2/2] 代理 8083 已在监听，跳过。'
} else {
  if (-not (Test-Path $ProxyScript)) {
    Write-Warning "  找不到代理脚本：$ProxyScript"
  } else {
    Write-Host "  [2/2] 启动代理 $ProxyListen → $ProxyTarget …"
    # 用 cmd 起，避免 powershell 退出时把子进程带走；日志写到本脚本同目录，便于事后追。
    $log = Join-Path $PSScriptRoot 'loopback-proxy.log'
    Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden `
      -ArgumentList @('/c', "node `"$ProxyScript`" --listen $ProxyListen --target $ProxyTarget >> `"$log`" 2>&1") | Out-Null
    if (Wait-Port 8083 20) { Write-Host '        8083 已就绪。' -ForegroundColor Green }
    else { Write-Warning '        等了 20 秒仍没等到 8083，看看 loopback-proxy.log。' }
  }
}

# --- 复核：真的能从"非回环地址"取到模型清单吗 ---
Write-Host ''
Write-Host '== 复核（实测，不是猜）' -ForegroundColor Cyan
if (-not (Test-Port 11434)) {
  Write-Host '  Ollama 没在跑（-ProxyOnly 的正常状态，或你还没开它）→ 代理在，但手机现在取不到模型。' -ForegroundColor Yellow
  Write-Host '  想让它完整可用：不带 -ProxyOnly 再跑一次本脚本。'
  return
}
$tailnetIp = (& 'C:\Program Files\Tailscale\tailscale.exe' ip -4 2>$null | Select-Object -First 1)
foreach ($addr in @('127.0.0.1', $tailnetIp) | Where-Object { $_ }) {
  try {
    $r = Invoke-RestMethod -Uri "http://${addr}:8083/api/tags" -TimeoutSec 8
    Write-Host ("  {0,-16} → {1} 个模型" -f $addr, $r.models.Count) -ForegroundColor Green
  } catch {
    Write-Host ("  {0,-16} → 取不到（{1}）" -f $addr, $_.Exception.Message) -ForegroundColor Yellow
  }
}
Write-Host ''
Write-Host '完成。手机端对应地址：http://<上面的组网 IP>:8083/v1'
