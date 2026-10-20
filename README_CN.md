# BaoCursor（Cursor Agent 分支）

[English](README.md) · **简体中文** · [日本語](README_JA.md) · [Français](README_FR.md) · [Español](README_ES.md)

**BaoCursor** 仅围绕 **[Cursor Agent CLI](https://cursor.com/docs/cli/overview)**（`agent acp`）提供桌面壳与内置 IDE，**不提供 Claude Code 内核**。本项目 fork 自 [BaoCode](https://github.com/baocode-dev/baocode)（GPL）。仓库名仍为 `baocode-cursor-agent`。安装与设置见 [CONTRIBUTING.md](CONTRIBUTING.md)，ACP 能力对照见 [docs/CURSOR_CLI_PARITY.md](docs/CURSOR_CLI_PARITY.md)。

[官网](https://baocode.dev) · [下载](https://baocode.dev/download) · [更新日志](https://baocode.dev/changelog)

一个出色、易用的 Cursor Agent 桌面界面，内置毫秒级响应的快速 IDE。

![BaoCursor 主窗口](site/shots/main.png)

> 本文是英文 README 的中文介绍；如内容有差异，以 [English](README.md) 为准。

## 为什么做 BaoCursor

终端适合运行编程智能体，却不适合阅读：长篇 diff 很容易滚出视野，先前的步骤难以重新找到，审查修改又需要切换应用。BaoCursor 是我们希望为 **Cursor Agent CLI** 提供的那个窗口。

BaoCursor 不包含自己的智能体。智能体是走 ACP 的 **Cursor Agent**；界面为阅读对话、审查修改和在 IDE 中协作而设计。

## 功能（本分支重点）

- **Cursor Agent（ACP）** — agent / plan / ask 模式、权限、提问、计划、待办、取消，以及在 CLI 支持时的会话加载。
- **为阅读而生的界面** — 在 IDE 中逐文件查看与审查修改。
- **快速 IDE** — 编辑器、终端、源代码管理；支持多种快捷键映射与语言服务器。
- **命名工作区** — 多仓库 Cursor CLI 工作区（见 [CONTRIBUTING.md](CONTRIBUTING.md)）。

上游 BaoCode 的完整功能列表（浏览器扩展、SSH 远程等）见 [BaoCode README](https://github.com/baocode-dev/baocode/blob/main/README.md)；其中部分仍假设 Claude Code，本分支的智能体界面仅为 Cursor。

## 系统要求

- macOS 12+、Windows 10+（x64），或 Linux（Ubuntu 22.04+ 等，x64/arm64）。
- 已安装 **[Cursor Agent CLI](https://cursor.com/docs/cli/installation)**（`PATH` 上有 `agent`，或在设置中配置 `cursorAgent.path`）：

  ```sh
  curl https://cursor.com/install -fsS | bash
  ```

## 从源码构建

```sh
flutter pub get
flutter run -d macos
```

macOS 安装包：`dart run tool/build_macos.dart` → `BaoCursor-<version>-{arm64,x64}.dmg`。

## 许可证

GPL-3.0-or-later，与 BaoCode 相同。见 [LICENSE](LICENSE)。
