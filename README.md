<p align="center">
  <img src="docs/images/hero.svg" alt="Bili3x：B站客户端三倍速，更新后自动维护" width="900">
</p>

<p align="center">
  <a href="https://github.com/fate456/bilibili-desktop-3x-speed/releases/latest"><img src="docs/images/download.svg" alt="下载最新版"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=flat-square" alt="Windows 10 / 11">
  <img src="https://img.shields.io/badge/PowerShell-5.1-5391FE?style=flat-square" alt="系统自带 PowerShell 5.1">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-34B27B?style=flat-square" alt="MIT License"></a>
  <a href="https://github.com/fate456/bilibili-desktop-3x-speed/actions/workflows/verify.yml"><img src="https://github.com/fate456/bilibili-desktop-3x-speed/actions/workflows/verify.yml/badge.svg" alt="源码与隐私检查"></a>
</p>

<p align="center"><strong>给 Windows 哔哩哔哩客户端加上 3 倍速。装一次，兼容的更新自动补回。</strong></p>
<p align="center"><a href="https://github.com/fate456/bilibili-desktop-3x-speed/releases/latest"><strong>⬇ 下载 Bili3x.zip</strong></a> · <a href="#三步开始">三步开始</a> · <a href="使用说明.md">完整说明</a> · <a href="https://github.com/fate456/bilibili-desktop-3x-speed/issues">反馈问题</a></p>

## 它解决什么问题？

B站桌面客户端的倍速不够用，手工补丁又容易被更新覆盖。**Bili3x** 在播放器倍速菜单中加入 **3.0x**（替换 0.75x），并自动维护安装包与热更新包。

| 你想做的事 | Bili3x 怎么处理 |
| --- | --- |
| 用 3 倍速看视频 | 直接在客户端原来的倍速菜单选择 **3.0x**。 |
| 客户端更新后继续用 | 检测资源变化，退出后台且文件稳定后自动补回，下次打开生效。 |
| 不想折腾开发环境 | 下载、完整解压、双击入口；无需 Python、Node.js。 |
| 随时恢复 | 保留原版快照，核对当前版本后恢复；先停止自动维护。 |

## 三步开始

1. 从 **[最新版下载页](https://github.com/fate456/bilibili-desktop-3x-speed/releases/latest)** 下载 `Bili3x.zip`，**完整解压**。
2. 从 B站托盘菜单彻底退出客户端，再双击 **`启用自动补丁.bat`**，允许管理员权限提示。
3. 等待几秒后照常打开 B站，在原来的倍速菜单选择 **3.0x**。可用 **`查看状态.bat`** 确认已处理。

<p align="center"><img src="docs/images/quickstart.svg" alt="操作示意：完整解压 → 双击启用自动补丁 → 重新打开B站选3.0x；更新后彻底退出后台自动维护" width="900"></p>

*上图为操作示意，不是客户端截图。工具没有额外的播放器界面，你仍使用原来的 B站客户端。*

### 以后更新怎么办？

后台任务每 5 秒检查文件属性。**客户端和更新程序彻底退出、变化文件稳定至少 5 秒后**自动修补，下次打开客户端生效。关闭窗口后如果仍在托盘运行，还需要从托盘退出。

如果新版改变了倍速菜单结构，工具会报告不支持，保留文件并等待适配。自动维护针对已确认兼容的结构，不能保证所有未来版本都兼容。

## 常用入口

| 双击这个文件 | 用途 |
| --- | --- |
| **启用自动补丁.bat** | 首次安装、启动自动维护；以后登录时自动运行。 |
| **应用补丁.bat** | 启用自动维护，并在客户端已退出时立即检查。 |
| **查看状态.bat** | 只读检查任务、待处理情况和资源完整性。 |
| **关闭自动补丁.bat** | 停止自动维护，保留当前 3 倍速。 |
| **回滚.bat** | 停止自动维护，用匹配版本的快照恢复原版。 |

## 写入之前先检查

- **保持包结构**：等长替换菜单，保留偏移及其他字节；精确更新目标文件的 SHA256 与分块哈希。
- **保存恢复资料**：先保存原版，再验证候选包，以原子替换提交，并复查结果。
- **拒绝不确定的修改**：运行中、结构未知、完整性不符或数据重叠时延后或拒绝处理。
- **轻量检查**：未变化的包只查询文件属性；一个隐藏的 PowerShell 进程执行维护。
- **运行资料留在本机**：日志、快照和运行文件在 `%LOCALAPPDATA%\Bili3x`；发布包不包含账户、设备名、个人路径、客户端或登录资料。

支持 **Windows 10 / 11、系统自带 Windows PowerShell 5.1 与 .NET Framework**。启用自动任务需要当前账户具备管理员权限。本项目是社区工具，与哔哩哔哩官方无关联。

## 验证与反馈

已完成 **14 项关键验证**，覆盖更新覆盖、自动修复、精确回滚、并发停止与独立运行目录。另在本机真实热更新包上模拟更新覆盖，后台修复后的完整文件与先前补丁字节一致。

这些记录验证补丁与维护流程；未覆盖所有客户端版本、视频和播放场景。GitHub Actions 检查语法、核心编译、源文件哈希和发布内容隐私，不运行需要交互式桌面的完整计划任务测试。

查看 [关键验证记录](artifacts/verification.json)、[本机脱敏验收](artifacts/live-acceptance.json)、[代码审查](artifacts/code-review.txt) 和 [隐私扫描](artifacts/privacy-review.json)。源码与更多细节见 [使用说明](使用说明.md)。

如果遇到不支持的新版本，请在 [Issues](https://github.com/fate456/bilibili-desktop-3x-speed/issues) 提供客户端版本及脱敏后的错误提示。发截图前遮住昵称、头像和个人路径。

**如果它省去了你每次更新后手动打补丁的麻烦，欢迎点个 ⭐ Star，方便下次找到，也让更多人搜到。**

---

**English:** Bili3x adds **3x playback speed** to the Windows Bilibili desktop client (replacing 0.75x). A per-user maintenance task reapplies compatible patches after updates, once the client and updater exit and the files settle. Download the release ZIP, extract everything, and run `启用自动补丁.bat` once. Includes integrity verification and version-aware rollback. Unknown menu layouts are left untouched.
