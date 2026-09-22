#!/usr/bin/env bash
# 验证"手机上装 DSH"的那条配方，并**原样打印**出来 —— 保证我发出去的那行 = 本机验过的那行。
#
# 背景（三条都是真机踩出来的）：
#   1) 上游 0.1.5-rc.3 发布树坏了（sidebar 有 rc.3、配套 documentpreview 没有，
#      ^0.1.5-rc.3 按 semver 只匹配 0.1.5 系列 → 全新安装必 ETARGET）→ 用 overrides 钉 rc.2。
#   2) npm 11.19+ 默认**不执行**未批准的安装脚本 → node-pty 的编译被跳过 → 用 package.json
#      的 allowScripts 预置白名单（等价于 npm install-scripts approve）。
#   3) 多行 heredoc 在 Termux 里粘贴会被截断（真机出过 0 字节 package.json → EJSONPARSE）
#      → 配方做成**单行**。
#
# 用法： "C:\Program Files\Git\bin\bash.exe" tools/verify-install-recipe.sh
set -uo pipefail

JSON='{"name":"dsh-install","private":true,"dependencies":{"@deepseek-ai/dsh":"0.1.5-rc.2"},"overrides":{"@deepseek-ai/dsh-client-ui-sidebar":"0.1.5-rc.2","@deepseek-ai/dsh-client-ui-sidebar-documentpreview":"0.1.5-rc.2","@deepseek-ai/dsh-web-app":"0.1.5-rc.2","@deepseek-ai/dsh-client-ui-chat":"0.1.5-rc.2"},"allowScripts":{"node-pty":true,"@deepseek-ai/dsh-subprocess-local":true,"koffi":true,"protobufjs":true}}'
# 用 `;` 而不是 `&&` 串起最后几步：即使 rebuild 报错，也要把"产物在不在"打出来（一次粘贴拿全证据）
RECIPE="mkdir -p ~/dsh-install && cd ~/dsh-install && rm -f ~/package.json && echo '$JSON' > package.json && npm install --no-audit --no-fund && npm rebuild node-pty @deepseek-ai/dsh-subprocess-local --foreground-scripts; ln -sf \"\$HOME/dsh-install/node_modules/.bin/dsh\" \"\$PREFIX/bin/dsh\"; hash -r; dsh --version; ls -l ~/dsh-install/node_modules/node-pty/build/Release/pty.node"

TMP="$(mktemp -d)"
cd "$TMP"

echo "$JSON" > package.json
echo "1) 生成的 package.json 大小：$(wc -c < package.json) 字节（0 字节 = 粘贴被截断）"

if command -v node >/dev/null 2>&1; then
  node -e '
    const j = require(process.cwd() + "/package.json");
    const needOv = ["@deepseek-ai/dsh-client-ui-sidebar","@deepseek-ai/dsh-client-ui-sidebar-documentpreview","@deepseek-ai/dsh-web-app","@deepseek-ai/dsh-client-ui-chat"];
    const needAl = ["node-pty","@deepseek-ai/dsh-subprocess-local","koffi","protobufjs"];
    const missOv = needOv.filter(k => !j.overrides[k]);
    const missAl = needAl.filter(k => !j.allowScripts[k]);
    if (missOv.length || missAl.length) {
      console.error("2) ✗ 缺 overrides: " + missOv.join(",") + " 缺 allowScripts: " + missAl.join(","));
      process.exit(1);
    }
    console.log("2) JSON 合法 ✓  deps=" + Object.keys(j.dependencies).join(",") + "  overrides=" + Object.keys(j.overrides).length + "  allowScripts=" + Object.keys(j.allowScripts).length);
  ' || { echo "2) ✗ JSON 校验失败"; rm -rf "$TMP"; exit 1; }
else
  echo "2) （没有 node，跳过 JSON 校验）"
fi

if [ "${SKIP_DRY_RUN:-0}" != "1" ] && command -v npm >/dev/null 2>&1; then
  echo "3) 解析依赖树（--dry-run，可能几十秒）…"
  if npm install --dry-run --no-audit --no-fund --registry=https://registry.npmmirror.com >"$TMP/dry.log" 2>&1; then
    echo "   ✓ $(grep -E 'added [0-9]+ package' "$TMP/dry.log" | tail -1)"
  else
    echo "   ✗ 解析失败："; grep 'npm error' "$TMP/dry.log" | head -4
  fi
else
  echo "3) （跳过 dry-run）"
fi

rm -rf "$TMP"

echo
echo "================= 手机 Termux 里粘贴这一行 ================="
echo "$RECIPE"
echo "=========================================================="
