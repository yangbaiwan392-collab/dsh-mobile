#!/usr/bin/env bash
# 验证"手机上装 DSH"的那条配方，并**原样打印**出来 —— 保证我发出去的那行 = 本机验过的那行。
#
# 背景：上游 0.1.5-rc.3 发布树坏了（sidebar 有 rc.3、配套 documentpreview 没有，
# ^0.1.5-rc.3 按 semver 只匹配 0.1.5 系列 → 全新安装必 ETARGET）。
# 绕法：装进项目目录 + overrides 钉 rc.2 组合 + npm link。
#
# 为什么做成**单行**：手机 Termux 里粘贴多行 heredoc 极易被截断（真机踩过：
# cat 写出了一个 0 字节的 package.json，npm 报 EJSONPARSE "parsing empty string"）。
#
# 用法： "C:\Program Files\Git\bin\bash.exe" tools/verify-install-recipe.sh
set -uo pipefail

# --- 配方本体（单行；只含单引号包裹的 JSON，内部无单引号、无 $ 展开）---
JSON='{"name":"dsh-install","private":true,"dependencies":{"@deepseek-ai/dsh":"0.1.5-rc.2"},"overrides":{"@deepseek-ai/dsh-client-ui-sidebar":"0.1.5-rc.2","@deepseek-ai/dsh-client-ui-sidebar-documentpreview":"0.1.5-rc.2","@deepseek-ai/dsh-web-app":"0.1.5-rc.2","@deepseek-ai/dsh-client-ui-chat":"0.1.5-rc.2"}}'
RECIPE="mkdir -p ~/dsh-install && cd ~/dsh-install && rm -f ~/package.json && echo '$JSON' > package.json && npm install --no-audit --no-fund && npm link @deepseek-ai/dsh && dsh --version"

TMP="$(mktemp -d)"
cd "$TMP"

# 1) 用完全相同的 echo 写法生成 package.json
echo "$JSON" > package.json
echo "1) 生成的 package.json 大小：$(wc -c < package.json) 字节（0 字节就是粘贴被截断了）"

# 2) JSON 必须合法，且字段齐全
if command -v node >/dev/null 2>&1; then
  node -e '
    const j = require(process.cwd() + "/package.json");
    const need = ["@deepseek-ai/dsh-client-ui-sidebar","@deepseek-ai/dsh-client-ui-sidebar-documentpreview","@deepseek-ai/dsh-web-app","@deepseek-ai/dsh-client-ui-chat"];
    const missing = need.filter(k => !j.overrides[k]);
    if (missing.length) { console.error("2) ✗ overrides 缺：" + missing.join(", ")); process.exit(1); }
    console.log("2) JSON 合法 ✓  deps=" + Object.keys(j.dependencies).join(",") + "  overrides=" + Object.keys(j.overrides).length + " 项");
  ' || { echo "2) ✗ JSON 校验失败"; rm -rf "$TMP"; exit 1; }
else
  echo "2) （没有 node，跳过 JSON 校验）"
fi

# 3) 可选：真的解析一遍依赖树（需要网络；失败不算配方错，只提示）
if [ "${SKIP_DRY_RUN:-0}" != "1" ] && command -v npm >/dev/null 2>&1; then
  echo "3) 解析依赖树（--dry-run，可能几十秒）…"
  if npm install --dry-run --no-audit --no-fund --registry=https://registry.npmmirror.com >"$TMP/dry.log" 2>&1; then
    echo "   ✓ $(grep -E 'added [0-9]+ package' "$TMP/dry.log" | tail -1)"
  else
    echo "   ✗ 解析失败（看下面几行）"; grep 'npm error' "$TMP/dry.log" | head -4
  fi
else
  echo "3) （跳过 dry-run）"
fi

rm -rf "$TMP"

echo
echo "================= 手机 Termux 里粘贴这一行 ================="
echo "$RECIPE"
echo "=========================================================="
