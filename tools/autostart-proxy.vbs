' DSH 模型代理（8083）自启包装器 —— 无窗口后台启动，避免每次登录弹黑框
' 目标：**与本文件同目录**的 start-pc-model-services.ps1 -ProxyOnly
'       （刻意不写死绝对路径：别人 clone 到别的盘也能直接用）
'
' 为什么只起代理、不起 Ollama（2026-09-25 用户拍板）：
'   代理只占几十 MB 内存、不碰显存，常驻代价可以忽略；而 Ollama 一旦被请求就会把
'   十几 GB 往显存里塞，跟出图抢卡，所以保持手动。
'
' 它做的是：把 PC 的 11434（Ollama）转发到 0.0.0.0:8083，供局域网 / Tailscale 组网内的
' 手机访问（手机 DSH 的模型地址 = http://<本机组网 IP>:8083/v1）。
'
' 要停：结束那个监听 8083 的 node 进程；或在任务管理器→启动应用里禁用本项。
' 手动跑一次：直接双击同目录的 start-pc-model-services.ps1
Option Explicit
Dim fso, sh, ps, here, script
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
ps   = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
here = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(here, "start-pc-model-services.ps1")
If Not fso.FileExists(script) Then
    WScript.Quit 1
End If
sh.Run """" & ps & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """ -ProxyOnly", 0, False
