# 小橘桌宠

一个使用真实小猫照片制作的 macOS 透明桌面宠物。应用不占用 Dock，常驻菜单栏。

## 下载

前往 [Releases](https://github.com/miczhang2023/cat-desktop-pet-macos/releases) 下载最新版 DMG。应用为 Apple Silicon 与 Intel 通用版本。

支持 macOS 12.0 或更高版本；“开机启动”功能需要 macOS 13.0 或更高版本。

## 功能

- 透明、无边框、始终置顶，可拖动
- 鼠标靠近时，在八个真实头颈姿态之间平滑切换，视线覆盖上下左右和四个斜方向
- 呼吸、自然眨眼和轻微待机动作
- 单击弹跳并播放声音
- 双击切换休息/互动状态
- 鼠标滚轮缩放，或在右键/菜单栏菜单中选择放大、缩小
- 右键或菜单栏控制显示、暂停、开机启动（macOS 13+）和退出
- 支持多桌面与全屏空间

## 使用

打开 DMG 后将 `小橘桌宠.app` 拖入“应用程序”，然后双击运行。首次运行如果 macOS 阻止打开，可以在 Finder 中右键应用并选择“打开”，或执行：

```sh
xattr -dr com.apple.quarantine "/Applications/小橘桌宠.app"
```

## 构建

需要 macOS 12 或更高版本，以及 Apple Command Line Tools。

```sh
zsh scripts/build.sh
zsh scripts/package_dmg.sh
```

构建产物位于 `build/`。

## 替换照片

`Resources/cat-open.png` 是正面完整猫咪，`Resources/cat-blink.png` 是同尺寸闭眼帧；`Resources/Directions/` 保存八个透明方向姿态。所有图片需要使用相同画布尺寸、位置和比例。

应用使用临时签名，可以在本机直接运行。面向他人分发时，需要 Apple Developer ID 证书完成正式签名和公证。
