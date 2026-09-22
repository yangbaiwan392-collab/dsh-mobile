# 探测"哪个 DSH 版本能从镜像解析安装" —— 官方某个发布可能引用不存在的子包版本（发坏了），
# 装错版本会在手机上卡在 npm ETARGET。本脚本用 --dry-run 只解析不下载，几秒出结论。
#
# 用法：powershell -File tools\probe-dsh-versions.ps1 [-Registry https://registry.npmmirror.com]
[CmdletBinding()]
param(
    [string]$Registry = 'https://registry.npmmirror.com',
    [string[]]$Versions = @('0.1.5-rc.2', '0.1.5-rc.1')
)

$ErrorActionPreference = 'Continue'
$probe = Join-Path $env:TEMP ('dsh-probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $probe | Out-Null
'{ "name": "probe", "version": "1.0.0", "private": true }' | Set-Content -Encoding ascii (Join-Path $probe 'package.json')

Write-Host "registry = $Registry"
$ok = @()
foreach ($v in $Versions) {
    Write-Host ("`n=== 试解析 @deepseek-ai/dsh@{0} ===" -f $v) -ForegroundColor Cyan
    Push-Location $probe
    $out = & npm i "@deepseek-ai/dsh@$v" --dry-run --no-audit --no-fund --registry=$Registry 2>&1
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -eq 0) {
        Write-Host "  ✓ 可以安装" -ForegroundColor Green
        $ok += $v
    } else {
        Write-Host "  ✗ 解析失败" -ForegroundColor Red
        $out | Select-String -Pattern 'npm error' | Select-Object -First 5 | ForEach-Object { Write-Host ("     " + $_.Line.Trim()) }
    }
}

Write-Host "`n可用的版本：" -ForegroundColor Yellow
if ($ok.Count -eq 0) { Write-Host "  （都装不上 —— 上游发布可能坏了，试试更早的版本或换 registry）" -ForegroundColor Red }
else { $ok | ForEach-Object { Write-Host "  @deepseek-ai/dsh@$_" } }

Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue
