# 端到端验证模式 B：回环改写代理能不能让"非 loopback 的 Host"访问到 DSH。
#
# 全部用**隔离的 DSH_HOME + 隔离端口**，绝不碰用户正在跑的 3080（那是本 agent 自己坐的树枝）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-mode-b.ps1
[CmdletBinding()]
param(
    [int]$DshPort = 3099,
    [int]$ProxyPort = 8081,
    [string]$FakeLanIp = '192.168.1.104'
)

$ErrorActionPreference = 'Continue'   # 子进程会把版本/错误写到 stderr，别让它中断脚本
$root   = Split-Path -Parent $PSScriptRoot
$home_  = 'E:\dsh-verify-android'
$log    = "$home_\_web.log"
$proxyLog = "$home_\_proxy.log"
New-Item -ItemType Directory -Force -Path $home_ | Out-Null
Remove-Item $log, $proxyLog -ErrorAction SilentlyContinue

function Wait-ForPattern([string]$path, [string]$pattern, [int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (Test-Path $path) {
            # 空文件时 Get-Content -Raw 返回 $null，直接丢给 [regex]::Match 会抛 ArgumentNullException
            $raw = Get-Content $path -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $m = [regex]::Match($raw, $pattern)
                if ($m.Success) { return $m }
            }
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

$results = [ordered]@{}
$dsh = $null; $proxy = $null
try {
    # ---------- 1. 隔离实例：loopback 绑定（这是 DSH 唯一允许的方式） ----------
    $env:DSH_HOME = $home_
    $dsh = Start-Process cmd.exe -ArgumentList '/c', "dsh web --port $DshPort --no-open > `"$log`" 2>&1" -PassThru -WindowStyle Hidden
    $m = Wait-ForPattern $log 'dsh web: (http://127\.0\.0\.1:\d+/\?token=\S+)' 60
    if (-not $m) { throw "隔离实例没在 60s 内打印 token URL，看 $log" }
    $authenticatedUrl = $m.Groups[1].Value
    $token = ([regex]::Match($authenticatedUrl, 'token=(\S+)')).Groups[1].Value
    $results['1. 隔离实例启动'] = "ok  $authenticatedUrl"

    # ---------- 2. 栅栏对照：直接拿"伪 LAN Host"打 loopback ----------
    $codeDirect = & curl.exe -s -o NUL -w '%{http_code}' -H "Host: ${FakeLanIp}:$DshPort" "http://127.0.0.1:$DshPort/?token=$token"
    $codeDirectNoToken = & curl.exe -s -o NUL -w '%{http_code}' -H "Host: ${FakeLanIp}:$DshPort" "http://127.0.0.1:$DshPort/"
    $codeDirectOrigin = & curl.exe -s -o NUL -w '%{http_code}' -H "Host: ${FakeLanIp}:$DshPort" -H "Origin: http://evil.example" "http://127.0.0.1:$DshPort/"
    $results['2a. 伪 Host + token'] = "HTTP $codeDirect"
    $results['2b. 伪 Host 无 token'] = "HTTP $codeDirectNoToken"
    $results['2c. 伪 Host + 跨站 Origin'] = "HTTP $codeDirectOrigin"

    # ---------- 3. 起代理，模拟手机从 LAN 进来 ----------
    $proxy = Start-Process cmd.exe -ArgumentList '/c', "node `"$root\tools\loopback-proxy.mjs`" --listen 0.0.0.0:$ProxyPort --target 127.0.0.1:$DshPort > `"$proxyLog`" 2>&1" -PassThru -WindowStyle Hidden
    if (-not (Wait-ForPattern $proxyLog 'loopback-proxy 监听' 20)) { throw "代理没起来，看 $proxyLog" }
    $results['3. 代理启动'] = "ok  :$ProxyPort -> 127.0.0.1:$DshPort"

    # ---------- 4. 经代理做 token 交换（手机看到的就是这一步） ----------
    $headers = & curl.exe -s -D - -o NUL -H "Host: ${FakeLanIp}:$ProxyPort" "http://127.0.0.1:$ProxyPort/?token=$token"
    $status = ($headers | Select-String -Pattern '^HTTP/\S+ (\d+)' | Select-Object -First 1).Matches.Groups[1].Value
    $setCookie = ($headers | Select-String -Pattern '^set-cookie:' | Select-Object -First 1)
    $cookiePair = if ($setCookie) { ($setCookie.Line -replace '^set-cookie:\s*', '') -replace ';.*$', '' } else { $null }
    $results['4. 经代理交换 token'] = "HTTP $status；Set-Cookie=$(if ($cookiePair) { '已下发' } else { '无' })"

    # ---------- 5. 带 cookie 拉首页（app 里 WebView 真正要的东西） ----------
    if ($cookiePair) {
        $bodyFile = "$home_\_index.html"
        $codeIndex = & curl.exe -s -o $bodyFile -w '%{http_code}' -H "Host: ${FakeLanIp}:$ProxyPort" -H "Cookie: $cookiePair" "http://127.0.0.1:$ProxyPort/"
        $body = Get-Content $bodyFile -Raw -ErrorAction SilentlyContinue
        $len = if ($body) { $body.Length } else { 0 }
        $looksLikeShell = ($body -match '__DSH_BOOT__') -or ($body -match '<div id="root"') -or ($body -match '<script[^>]+src=')
        $head = if ($body) { ($body -replace '\s+', ' ').Substring(0, [Math]::Min(90, $len)) } else { '(空)' }
        $results['5. 带 cookie 取首页'] = "HTTP $codeIndex；长度=$len；外壳=$(if ($looksLikeShell) { '像 SPA' } else { '可疑' })"
        $results['5b. 首页开头'] = $head
    } else {
        $results['5. 带 cookie 取首页'] = '跳过（第 4 步没拿到 cookie）'
    }
}
finally {
    foreach ($p in @($proxy, $dsh)) {
        if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 300 }
    }
}

Write-Host "`n=== 模式 B 验证结果 ===" -ForegroundColor Yellow
$results.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-28} {1}" -f $_.Key, $_.Value) }
