# SenPlayer AirPlay Auto Sync

在 Mac 上使用 AirPort Express 或其他 AirPlay 音响播放视频时，声音可能比画面晚约 2 秒。

这不是局域网故障，而是 AirPlay 音频链路的缓冲延迟。Apple 在 [`AVAudioSession.outputLatency`](https://developer.apple.com/documentation/avfaudio/avaudiosession/outputlatency) 官方文档中明确说明：使用 AirPlay 音频设备可能产生 2 秒延迟。

普通音乐播放通常不容易察觉这个问题，因为没有画面需要同步；播放电影或视频时，口型、对白和画面之间的偏差会很明显。

## 这个 Skill 做什么

`senplayer-airplay-auto-sync` 会监听 macOS 当前的默认音频输出，并自动调整 SenPlayer 的全局音频延迟：

| 当前输出 | SenPlayer 补偿值 |
| --- | ---: |
| AirPort Express / AirPlay 音响 | `-2.0 秒` |
| Mac 扬声器、HDMI、USB 音频或耳机 | `0.0 秒` |

切换音响后不需要手动修改设置。只有目标补偿值发生变化，而且 SenPlayer 正在运行时，程序才会正常退出并重新打开 SenPlayer，让新设置立即生效。

`-2.0 秒` 是默认值，不代表所有 AirPlay 接收设备都完全相同。如果实际口型仍有少量偏差，可以安装时传入其他数值进行校准。

## 安装

要求：

- macOS
- 已安装并至少打开过一次 SenPlayer
- Apple Command Line Tools（用于在本机编译 Swift 监听器）

将仓库克隆到 Codex 的个人 skills 目录：

```bash
git clone https://github.com/tigerrrr2020/senplayer-airplay-auto-sync.git \
  ~/.codex/skills/senplayer-airplay-auto-sync
```

然后在 Codex 中说：

```text
使用 $senplayer-airplay-auto-sync 安装 AirPort/AirPlay 音频延迟自动切换。
```

Skill 会先检查 SenPlayer、Swift 编译器和当前音频设备，然后安装当前用户专用的后台 LaunchAgent。整个过程不需要管理员权限。

## 可选快捷指令

如果希望在“快捷指令”App 中看到一个具象化的手动入口，可以让 Codex 同时安装可选快捷指令：

```text
使用 $senplayer-airplay-auto-sync 安装自动切换，并添加快捷指令。
```

也可以直接运行：

```bash
bash scripts/manage.sh install --airplay-delay -2.0 --with-shortcut
```

系统会打开 Apple 的快捷指令导入页面，由用户确认添加 `SenPlayer · 自动同步`。

这个快捷指令用于一键启动或修复后台监听器。真正的音响识别和延迟切换仍由后台服务自动完成，日常切换 AirPlay 与本机扬声器时不需要点击快捷指令。

## 常用命令

```bash
# 只读检查当前环境和音频设备
bash scripts/manage.sh probe

# 安装自动切换，AirPlay 默认补偿 -2 秒
bash scripts/manage.sh install --airplay-delay -2.0

# 查看服务、当前输出、延迟和日志
bash scripts/manage.sh status

# 单独打开快捷指令导入页面
bash scripts/manage.sh install-shortcut

# 卸载后台服务（保留 SenPlayer 设置、日志和快捷指令）
bash scripts/manage.sh uninstall --yes
```

## 使用范围

- 只修改当前 Mac 上 SenPlayer 的 `kGlobalAudioDelay` 设置。
- 不修改 AirPort Express 固件或 macOS 的系统级音频延迟。
- 不影响 iPhone 或 iPad；iOS/iPadOS 上的 AirPlay 播放需要由相应 App 自己处理同步。
- AirPlay 延迟可能因接收设备、固件和播放链路略有差异，可以按实际情况调整补偿值。

更多诊断信息请参阅 [`references/troubleshooting.md`](references/troubleshooting.md)。
