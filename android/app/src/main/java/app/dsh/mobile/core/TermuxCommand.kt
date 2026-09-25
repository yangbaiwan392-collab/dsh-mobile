package app.dsh.mobile.core

/**
 * 生成要交给 Termux 执行的 bash 脚本正文（纯逻辑，可 JVM 单测）。
 *
 * 为什么需要它：早先的方案要求用户**把脚本文件拷进手机**（MTP/授权/路径……），
 * 真机上为此耗掉了好几轮排查。既然 app 本身能通过 Termux 的 RUN_COMMAND 执行命令，
 * 那就把脚本**打进 APK**、由 app 现场写进 Termux 家目录 —— 用户一次点击，零文件搬运。
 *
 * 关键手法：脚本内容放在**带引号的 heredoc**（`<<'标记'`）里，bash 不做任何展开，
 * 所以正文里的 `$`、反引号、单引号都原样落地，不需要逐字符转义。
 */
object TermuxCommand {

    // 注意：Kotlin 的块注释**可嵌套**，注释里别写「斜杠+星号」（例如写通配路径时），
    // 否则会打开一层嵌套注释、整个文件报 Unclosed comment。本文件踩过一次。
    /**
     * app 会在 Termux 家目录下建的目录。
     *
     * 用 `$HOME` 而不是 `~`：**bash 不在双引号里展开 `~`**，而生成的重定向一律带引号
     * （防路径里有空格），于是 `cat > "~/x"` 会去找一个名叫 `~` 的目录并失败 ——
     * 真机上表现为"目录建好了、文件是空的"（踩过）。
     */
    const val SCRIPT_DIR = "\$HOME/dsh-android"

    /**
     * 手机本地 `dsh web` 的默认端口 —— **单一真源**。
     *
     * 三处必须一致，改一处就全改：① 启动脚本里的 `PORT="${1:-3080}"`；
     * ② 自检脚本 [9] 的探活地址；③ app 侧"起来了没有"的实测探针（见 ui/MainActivity）。
     */
    const val LOCAL_PORT = 3080

    /** 一行干完：写好脚本 → 缺 DSH 就跑安装，否则直接启动。 */
    fun installAndStart(scripts: Map<String, String>): String = buildString {
        appendLine("set -e")
        // 全程留痕：Termux 后台执行（RUN_COMMAND）的输出本来谁也看不到，装失败时只能靠猜。
        // 这里把整个脚本的 stdout/stderr 重定向进文件，出问题可用 adb 直接读出来。
        appendLine("exec >>\"\$HOME/dsh-android-install.log\" 2>&1")
        appendLine("echo ''")
        appendLine("echo \"=== \$(date '+%F %T') 开始 ===\"")
        appendLine("echo \"Android \$(getprop ro.build.version.release) · 内核 \$(uname -r)\"")
        appendLine("mkdir -p \"$SCRIPT_DIR\"")
        for ((name, body) in scripts) writeFile("$SCRIPT_DIR/$name", body)
        appendLine("chmod +x \"$SCRIPT_DIR\"/*.sh")
        appendLine("echo \"==> 脚本已就位（$SCRIPT_DIR）\"")
        appendLine("DSH_BIN=\"\$HOME/dsh-install/node_modules/@deepseek-ai/dsh/lib/bin.js\"")
        appendLine("if [ -f \"\$DSH_BIN\" ]; then")
        // 已装过：这里补跑一次运行时修复（幂等），因为升级 DSH 后可能需要重新编译原生模块。
        // 首次安装那条分支**不要**在这里跑 —— 它需要 clang，而 clang 是 setup 阶段才装的；
        // setup-dsh.sh 末尾自己会调用修复脚本（真机踩过这个顺序问题）。
        appendLine("  [ -f \"$SCRIPT_DIR/fix-android-runtime.sh\" ] && bash \"$SCRIPT_DIR/fix-android-runtime.sh\" || true")
        appendLine("  echo '==> 检测到已安装的 DSH，直接启动'")
        appendLine("  exec bash \"$SCRIPT_DIR/start-dsh.sh\"")
        appendLine("else")
        appendLine("  echo '==> 首次运行：开始安装（Node / 编译 node-pty / wasm 版 sharp，慢是正常）'")
        appendLine("  exec bash \"$SCRIPT_DIR/setup-dsh.sh\"")
        appendLine("fi")
    }

    /**
     * 环境自检：把这条链路上真正会出问题的每一环都查一遍，结果既落文件也回传 app。
     *
     * 回传手法与入口地址回传同源：`am start -e dsh_diag "<报告>"`。
     * 这样用户不用连电脑、不用截图，就能看到"卡在哪一环、下一步该敲什么"。
     */
    fun diagnostics(packageName: String, activityClass: String): String = buildString {
        appendLine("R=''")
        appendLine("add() { printf -v R '%s%s\\n' \"\$R\" \"\$1\"; }")
        appendLine("add 'DSH 手机端 · 环境自检'")
        appendLine("add \"时间：\$(date '+%F %T')\"")
        appendLine("add ''")
        appendLine("add '—— Termux 侧 ——'")
        appendLine("add \"[1] 家目录：\$HOME\"")
        appendLine("add \"[2] 脚本目录 \$SCRIPT_DIR：\$( [ -d $SCRIPT_DIR ] && ls $SCRIPT_DIR | tr '\\n' ' ' || echo 不存在 )\"")
        appendLine("add \"[3] 允许外部应用执行：\$(grep -c '^allow-external-apps=true' ~/.termux/termux.properties 2>/dev/null || echo 0)（1=已开，0=没开）\"")
        appendLine("add \"[4] node：\$(command -v node >/dev/null 2>&1 && node -v || echo 未安装)\"")
        appendLine("add \"[5] dsh：\$( [ -f ~/dsh-install/node_modules/@deepseek-ai/dsh/lib/bin.js ] && echo 已安装 || echo 未安装 )\"")
        appendLine("add \"[6] node-pty 产物：\$( [ -f ~/dsh-install/node_modules/node-pty/build/Release/pty.node ] && echo 在 || echo '缺失（需 pkg install python clang make 后 npm rebuild node-pty）' )\"")
        appendLine("add \"[7] sharp(wasm)：\$( [ -d ~/dsh-install/node_modules/@img/sharp-wasm32 ] && echo 在 || echo '缺失（npm i @img/sharp-wasm32@0.35.4）' )\"")
        appendLine("add ''")
        appendLine("add '—— 服务与服务日志 ——'")
        appendLine("add \"[8] 进程：\$(pgrep -f 'dsh web' >/dev/null 2>&1 && echo 在跑 || echo 没跑)\"")
        appendLine("add \"[9] 本地 $LOCAL_PORT 探活：\$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://127.0.0.1:$LOCAL_PORT/ 2>/dev/null || echo 连不上)（200=已认证 / 401=在跑但未认证，都算正常；连不上=没在跑）\"")
        appendLine("add \"[10] 日志里的入口地址：\$(grep -m1 'dsh web: ' ~/.dsh-web.log 2>/dev/null || echo '暂无（说明还没成功启动过）')\"")
        appendLine("add ''")
        appendLine("add '—— 沙箱 / 能否执行命令 ——'")
        appendLine("add \"[11] 内核：\$(uname -r)\"")
        appendLine("add \"[12] Landlock：\$( [ -e /sys/kernel/security/landlock ] && echo '可用（工作区沙箱能工作）' || echo '不可用（内核 <5.13 或未启用 LSM）' )\"")
        appendLine("add \"[13] 结论：\$( [ -e /sys/kernel/security/landlock ] && echo '可以用 workspace-write 跑命令' || echo '要让 agent 跑命令，只能把沙箱模式设为 danger-full-access' )\"")
        appendLine("add ''")
        appendLine("add '—— 怎么看 ——'")
        appendLine("add '· [2] 空 → 回 app 菜单点「启动手机上的 DSH」，脚本会自动写进去'")
        appendLine("add '· [4]/[5] 未安装 → 同一按钮会自动装（首次几分钟）'")
        appendLine("add '· [6]/[7] 缺失 → 依赖没装全，重跑同一个按钮'")
        appendLine("add '· [8] 没跑 / [9] 连不上 → DSH 没在跑，点「启动手机上的 DSH」'")
        appendLine("add '· [9] 显示 401 是正常的：服务在跑，只是这个裸请求没带 cookie'")
        appendLine("printf '%s' \"\$R\" > ~/.dsh-diag.txt")
        // ① 剪贴板：唯一"后台也一定能送达"的通道（Android 10+ 会拦后台应用启动 Activity）。
        //    报告开头带固定标题，app 据此认出它（见 ClipboardIntake.DIAG_HEADER）。
        appendLine("if command -v termux-clipboard-set >/dev/null 2>&1; then")
        appendLine("  printf '%s' \"\$R\" | termux-clipboard-set >/dev/null 2>&1 || true")
        appendLine("fi")
        // ② am start：Termux 恰好在前台时能直接弹出来（后台时会被系统拦，属正常）
        appendLine("if command -v am >/dev/null 2>&1; then")
        appendLine("  am start -n $packageName/$activityClass -e dsh_diag \"\$R\" >/dev/null 2>&1 || true")
        appendLine("fi")
        appendLine("printf '%s' \"\$R\"")
    }

    /** 用带引号的 heredoc 落地一个文件；标记里带文件名，避免正文里恰好出现同名行。 */
    private fun StringBuilder.writeFile(target: String, body: String) {
        // 标记只留字母数字：文件名里的 `.` `-` 一律归一成 `_`（heredoc 标记允许连字符，
        // 但归一后更可读，也让"标记长什么样"有唯一形态）
        val stem = target.substringAfterLast('/').uppercase()
            .map { if (it.isLetterOrDigit()) it else '_' }
            .joinToString("")
        val marker = "DSH_EOF_$stem"
        append("cat > \"$target\" <<'$marker'\n")
        append(body.trimEnd('\n'))
        append("\n$marker\n")
    }
}
