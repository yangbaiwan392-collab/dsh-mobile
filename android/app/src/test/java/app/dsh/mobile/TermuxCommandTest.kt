package app.dsh.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TermuxCommandTest {

    private val scripts = mapOf(
        "setup-dsh.sh" to "#!/usr/bin/env bash\nset -e\necho \"\$HOME 里带 \$ 和 ' 引号\"\n",
        "start-dsh.sh" to "#!/usr/bin/env bash\nPORT=\"\${1:-3080}\"\n",
        "tunnel-to-pc.sh" to "#!/usr/bin/env bash\n: \n",
    )

    @Test
    fun `每个脚本都用带引号的 heredoc 原样落地`() {
        val cmd = TermuxCommand.installAndStart(scripts)
        assertTrue(cmd.contains("<<'DSH_EOF_SETUP_DSH_SH'"))
        assertTrue(cmd.contains("<<'DSH_EOF_START_DSH_SH'"))
        assertTrue(cmd.contains("<<'DSH_EOF_TUNNEL_TO_PC_SH'"))
        // 正文里的 $ 与单引号必须原样出现（带引号的 heredoc 不做展开）
        assertTrue(cmd.contains("\$HOME 里带 \$ 和 ' 引号"))
        assertTrue(cmd.contains("PORT=\"\${1:-3080}\""))
    }

    @Test
    fun `写完后按 dsh 是否已安装决定安装还是直接启动`() {
        val cmd = TermuxCommand.installAndStart(scripts)
        assertTrue(cmd.contains("chmod +x \"\$HOME/dsh-android\"/*.sh"))
        assertTrue(cmd.contains("dsh-install/node_modules/@deepseek-ai/dsh/lib/bin.js"))
        assertTrue(cmd.contains("exec bash \"\$HOME/dsh-android/start-dsh.sh\""))
        assertTrue(cmd.contains("exec bash \"\$HOME/dsh-android/setup-dsh.sh\""))
        // 检查在启动之前
        assertTrue(cmd.indexOf("if [ -f \"\$DSH_BIN\" ]") < cmd.indexOf("exec bash \"\$HOME/dsh-android/start-dsh.sh\""))
    }

    @Test
    fun `自检覆盖每一环且会回传报告`() {
        val cmd = TermuxCommand.diagnostics("app.dsh.mobile", "app.dsh.mobile.ui.MainActivity")
        listOf(
            "allow-external-apps", "node -v", "node-pty", "sharp-wasm32",
            "pgrep -f 'dsh web'", "127.0.0.1:3080", ".dsh-web.log",
        ).forEach { assertTrue("自检应包含：$it", cmd.contains(it)) }
        assertTrue(cmd.contains("am start -n app.dsh.mobile/app.dsh.mobile.ui.MainActivity -e dsh_diag"))
        assertTrue(cmd.contains("~/.dsh-diag.txt"))
    }

    @Test
    fun `脚本目录与 Termux 侧约定一致`() {
        assertEquals("\$HOME/dsh-android", TermuxCommand.SCRIPT_DIR)
        assertTrue(TermuxCommand.installAndStart(scripts).contains("mkdir -p \"\$HOME/dsh-android\""))
    }

    @Test
    fun `绝不生成带引号的波浪号（bash 不在引号里展开 ~）`() {
        val cmd = TermuxCommand.installAndStart(scripts)
        // 真机踩过：`cat > "~/dsh-android/x.sh"` 会去找名为 ~ 的目录 → 目录建好了但文件是空的
        assertTrue("生成的命令里不应出现 \"~/（引号包住的波浪号不会展开）", !cmd.contains("\"~/"))
        assertTrue(cmd.contains("cat > \"\$HOME/dsh-android/setup-dsh.sh\""))
    }
}
