# SUDA Wi-Fi 自动登录

Windows 上的苏大 Wi-Fi 自动连接与认证脚本。`suda_wifi_autologin.ps1` 检查能否直连公网；断网时关闭红魔馆与 Clash Verge、清理系统代理、连接 `SUDA_WIFI_5G`，再调用无头 Chrome 登录校园网。`wlan_radio_recovery.ps1` 独立负责打开 WLAN 软件无线电。

## 准备

1. 安装 Python 和 Chrome，在项目目录创建虚拟环境：`py -m venv .venv`。
2. 安装 Selenium：`.\.venv\Scripts\python.exe -m pip install selenium`。
3. 将 `suda_wifi_config.example.json` 复制为 `suda_wifi_config.json`，填写各运营商的账号密码，并用 `active_carrier` 指定当前运营商。默认选择中国移动。真实配置文件已被 Git 忽略。
4. Selenium 可以自动管理 ChromeDriver。也可将与 Chrome 兼容的 `chromedriver.exe` 放在项目目录，脚本会优先使用它。驱动文件不会提交到仓库。

## 注册 Windows 计划任务

在**管理员 PowerShell** 中进入项目目录，执行：

```powershell
.\register_windows_tasks.ps1
```

脚本会注册两个隐藏任务，以 SYSTEM 身份运行，无需用户登录：

- `SUDA-WiFi-AutoLogin`：开机后 30 秒运行，之后每 5 分钟运行一次。
- `SUDA-WLAN-RadioRecovery`：开机后 15 秒运行，之后每分钟运行一次。

两者均设置为“已有实例运行时忽略新实例”，防止并发断开 Wi-Fi。登录任务检测外网时直接连接公共 HTTPS 站点；只有外网不可用才会关闭代理软件、清除系统代理并尝试重连。系统代理的目标用户 SID 在注册任务时自动写入任务参数。

如需一并注册 UU 远程进程守护任务，可运行：

```powershell
.\register_windows_tasks.ps1 -IncludeUuRemote
```

`UU-Remote-Watchdog` 每分钟检查一次 UU 远程是否运行，缺失时启动。它使用当前用户的交互式会话，并通过 `wscript.exe` 静默启动；用户未登录时不会运行。UU 远程安装路径从 Windows 的已安装程序信息中读取。

运行日志分别写入项目目录中的 `suda_wifi_autologin.log`、`wlan_radio_recovery.log` 和 `uu_remote_watchdog.log`，均被 Git 忽略。
