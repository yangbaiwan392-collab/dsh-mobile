# 发版流程（维护者用）

> 这份文档的目标：**让下一个人（包括三个月后的你）不用重新摸索。**
> 每一步都给了判定"成功没有"的依据，不靠"应该没问题"。

## 0. 一次性准备：正式签名密钥

仓库里的 `signing/debug.keystore` 是**调试**密钥（口令公开，见 `SECURITY.md`），只适合自己装。
要分发就先生成自己的：

```powershell
powershell -File tools/make-release-keystore.ps1
```

它会产生两个文件（**都在 .gitignore 覆盖范围内，不会进仓库**）：

| 文件 | 内容 |
|---|---|
| `android/signing/release.keystore` | 你的私钥 |
| `android/keystore.properties` | 口令与别名（Gradle 读它来决定 release 签名） |

> ⚠️ **立刻备份这两个文件到仓库之外。** 丢了 = 你再也无法给已安装的用户发升级包
> （Android 只接受同一把密钥签的升级包）。密钥泄漏 = 别人能以你的名义发包。
>
> 没生成也能跑 `assembleRelease`：Gradle 会**退回 debug 签名**并在日志里说明
> "产物仅供本地验证，不可分发"（见 `app/build.gradle.kts` 的 release 分支）。

## 1. 改版本号并记录改动

1. `android/app/build.gradle.kts`：`versionCode` **加一**（必须递增，否则手机不认升级）、`versionName` 改成新版本；
2. `CHANGELOG.md`：把 `[Unreleased]` 里的内容整理到新的版本小节，**带上日期**。

## 2. 出包

```powershell
powershell -File tools/build-apk.ps1 -Task assembleRelease
```

这条命令会依次做：契约检查 → Termux 脚本桩测试 → Gradle 构建 → 打印 APK 的 **SHA-256 与签名指纹**，
并把产物复制到 `dist/`。

**成功的判据**（别只看 exit code）：日志里 SHA-256 与指纹都打印出来了，且 `dist/` 下能看到
`dsh-mobile-<版本>-release.apk`。再确认签名不是 debug：

```powershell
& "$env:ProgramFiles\Android\Sdk\build-tools\34.0.0\apksigner.bat" verify --print-certs dist\dsh-mobile-<版本>-release.apk
# 指纹应与 tools/make-release-keystore.ps1 打印的那个一致
```

## 3. 提交、打 tag、推

```powershell
git add -A; git commit -m "release: v<版本>"
git tag v<版本>
git push origin main --tags
```

> 推 GitHub 时若报 `Recv failure: Connection was reset`（国内常见）：
> `git config --local http.proxy http://127.0.0.1:17897; git config --local http.version HTTP/1.1`
> 推完把 `http.proxy` 撤掉。详见 `notes/lessons.md`（本机笔记，不在本仓库）。

## 4. 发 GitHub Release 并附 APK

APK **不在仓库里**（`dist/` 被 gitignore）——它作为 Release 附件分发。

```powershell
gh release create v<版本> dist\dsh-mobile-<版本>-release.apk `
  --title "v<版本>" `
  --notes-file <把 CHANGELOG 里这一节写成的文件>
```

没有 `gh` 就在网页上：仓库 → Releases → Draft a new release → 选 tag → 拖入 APK → 写说明。

**发版说明里建议写清**：这一版能干什么、装的时候要什么（Android 13+ / Termux 版本）、
以及**签名来源**（正式签名还是 debug）；附上 SHA-256 供核对。

## 5. 发版后自检

- [ ] Release 页能下载到 APK，文件名与版本对得上；
- [ ] `README` 里的下载指引仍然成立（它写的是"Releases 页"）；
- [ ] CI 在 `main` 上是绿的（`.github/workflows/ci.yml`）；
- [ ] CHANGELOG 的日期与 tag 一致。

---

## 附：CI 与签名是什么关系

CI（`ci.yml`）**只出 debug 包**作为构建产物（artifact），**不做正式签名** ——
因为私钥不该进 CI，也不该为了发版把口令塞进流水线。正式包由维护者在本机签、手动上传 Release。

如果你想改成 CI 自动签：把 keystore 与口令放进仓库的 **Actions secrets**，
在 workflow 里还原成 `android/signing/release.keystore` + `android/keystore.properties` 再构建。
代价是：密钥从此躺在 GitHub 上（虽然加密），泄漏面变大 —— 自己权衡。
