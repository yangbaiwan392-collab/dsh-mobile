# 新手机开箱：一条命令把「3 个 APK + 一键装 DSH + 用 PC 的 Ollama」全办完。
#
# 用法（手机已开无线调试并与 PC 同网）：
#   powershell -File tools\new-phone-setup.ps1 -Ip 192.168.0.104 -Port 46393
#   powershell -File tools\new-phone-setup.ps1 -PcIp 192.168.0.105 -OllamaProxyPort 8083   # 只配「用 PC 的 Ollama」
#
# 前置（PC 侧，一条命令，见 docs/02 §四）：
#   node tools\loopback-proxy.mjs --listen 0.0.0.0:8083 --target 127.0.0.1:11434
#
# 设计原则：
#   · 幂等：装过的跳过、已配的合并（不覆盖用户已有的 llm-pi-ai 段）；
#   · 只碰该碰的：settings.yaml 改前先备份；
#   · 需要人动手的地方**明确说出来**（Termux 的权限弹窗、首次编译要几分钟）。
[CmdletBinding()]
param(
    [string]$Ip,
    [string]$Port,
    [string]$PcIp = '192.168.0.105',
    [int]$OllamaProxyPort = 8083,
    [switch]$SkipApk,
    [switch]$SkipOllama
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\toolchain-env.ps1"
$adb = Join-Path $PlatformTools 'adb.exe'
$repo = Split-Path -Parent $PSScriptRoot
$phoneDir = Join-Path $repo 'phone'
$th = '/data/data/com.termux/files/home'

function Adb { & $adb @args }
function Sh([string]$cmd) { & $adb shell $cmd }

if ($Ip) {
    Write-Host "==> 连接 $Ip`:$Port" -ForegroundColor Cyan
    & $adb connect "$Ip`:$Port" 2>&1 | Out-Null
}
$devices = (& $adb devices) -join "`n"
if ($devices -notmatch '\sdevice\s*$' -and $devices -notmatch '\sdevice\s') { throw '没有可用设备（先 adb connect，或插 USB）' }
$model = (Sh 'getprop ro.product.model').Trim()
$rel = (Sh 'getprop ro.build.version.release').Trim()
$kernel = (Sh 'uname -r').Trim()
Write-Host "    设备：$model · Android $rel · 内核 $kernel" -ForegroundColor Green

# ---------- 1. 装三个 APK ----------
if (-not $SkipApk) {
    Write-Host "`n==> 1/5 安装三个 APK" -ForegroundColor Cyan
    $apks = @('dsh-mobile-*-debug.apk', 'termux-app_v0.118.3+github-debug_arm64-v8a.apk', 'termux-api-app_v0.53.0+github.debug.apk')
    foreach ($pattern in $apks) {
        $file = Get-ChildItem (Join-Path $phoneDir $pattern) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $file) { Write-Host "    跳过（找不到 $pattern）" -ForegroundColor Yellow; continue }
        $out = & $adb install -r $file.FullName 2>&1 | Select-Object -Last 1
        Write-Host ("    {0,-46} {1}" -f $file.Name, $out)
    }
}

# ---------- 2. 权限 + 电池白名单 ----------
Write-Host "`n==> 2/5 Termux 执行权限与电池白名单" -ForegroundColor Cyan
Sh "pm grant app.dsh.mobile com.termux.permission.RUN_COMMAND" | Out-Null
Sh "dumpsys deviceidle whitelist +com.termux" | Out-Null
$wl = (Sh 'dumpsys deviceidle whitelist').ToString() -match 'com\.termux'
Write-Host ("    RUN_COMMAND 已授权；电池白名单：{0}" -f $(if ($wl) { '已加入 ✓' } else { '未确认 ✗' }))

# ---------- 3. 提示点一次按钮（Termux 侧的安装只能由 Termux 自己跑） ----------
Write-Host "`n==> 3/5 需要在手机上点一次：菜单 →「启动手机上的 DSH」" -ForegroundColor Yellow
Write-Host "    （它会写脚本、装 Node、现编 node-pty / flock / landlock-run、装 wasm sharp，首次 3–10 分钟）"
Write-Host "    完成后 Termux 会把入口地址经剪贴板交给 app，列表里出现「手机本地」。"
Write-Host "    —— 若你更想让我代劳：保持无线调试开启，并跑 tools\tap-by-text.ps1 -Key 82 -Text '启动手机上的 DSH'"

# ---------- 4. 等 DSH 起来 ----------
Write-Host "`n==> 4/5 轮询等待手机上的 DSH 就绪（最多 15 分钟）" -ForegroundColor Cyan
$ok = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 10
    $code = (Sh "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -o /dev/null -m 4 -w '%{http_code}' http://127.0.0.1:3080/").Trim()
    if ($code -match '^(200|401)$') { $ok = $true; Write-Host "    ✓ 已就绪（HTTP $code）" -ForegroundColor Green; break }
    if ($i % 6 -eq 5) { Write-Host "    …仍在安装/启动（HTTP $code）" }
}
if (-not $ok) { Write-Host "    ✗ 15 分钟内没起来：看 Termux 窗口的输出，或跑 app 菜单里的「环境自检」" -ForegroundColor Red }

# ---------- 5. 让手机上的 DSH 用 PC 的 Ollama ----------
if (-not $SkipOllama) {
    Write-Host "`n==> 5/5 配置「手机 DSH 用 PC 的 Ollama」" -ForegroundColor Cyan
    $settings = "$th/.dsh/settings.yaml"
    $hasBlock = (Sh "run-as com.termux grep -c '^llm-pi-ai:' $settings 2>/dev/null || echo 0").Trim()
    if ($hasBlock -ne '0') {
        Write-Host "    settings.yaml 里已有 llm-pi-ai 段 —— 为避免破坏你的配置，我不自动合并。" -ForegroundColor Yellow
        Write-Host "    请把 docs/02 §四 的那段 provider 手工并进去（或告诉我，我按你现有的结构改）。"
    } else {
        $snippet = @"
llm-pi-ai:
  providers:
    ollama-pc:
      displayName: Ollama (家里的 PC)
      apiKeyEnv: DSH_OLLAMA_KEY
      api: openai-completions
      baseURL: http://${PcIp}:${OllamaProxyPort}/v1
      models:
        - id: qwen2.5:7b-instruct
          name: qwen2.5:7b-instruct
          contextWindow: 32768
          input:
            - text
        - id: qwen3-vl:8b-instruct
          name: qwen3-vl:8b-instruct
          contextWindow: 262144
          input:
            - text
            - image
        - id: gemma3:27b
          name: gemma3:27b
          contextWindow: 131072
          input:
            - text
            - image
"@
        # 备份 → 追加。用 base64 传，避免 PowerShell 管道给 YAML 加 BOM（踩过）。
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($snippet))
        Sh "run-as com.termux cp $settings $settings.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" | Out-Null
        $b64 | & $adb shell "run-as com.termux sh -c 'cat > $th/.settings-snippet.b64'"
        Sh "run-as com.termux sh -c 'tail -c +4 $th/.settings-snippet.b64 | base64 -d >> $settings'" | Out-Null
        Sh "run-as com.termux rm -f $th/.settings-snippet.b64" | Out-Null
        Write-Host "    已追加 provider（原文件已备份为 settings.yaml.bak-*）" -ForegroundColor Green
        Write-Host "    还需重启 DSH 才生效：app 菜单 →「启动手机上的 DSH」"
    }
    Write-Host "`n  别忘了 PC 侧代理还开着：node tools\loopback-proxy.mjs --listen 0.0.0.0:$OllamaProxyPort --target 127.0.0.1:11434"
}

Write-Host "`n==> 完成。手机上打开 app 首页点「手机本地」即可对话。" -ForegroundColor Green
Write-Host "    想让 agent 跑 shell 命令：先看「环境自检」的 [12] Landlock 结论。" -ForegroundColor DarkGray
