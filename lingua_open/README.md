# Lingua Open

一个面向 Windows 和 Android 的开源多语言翻译客户端。界面和业务代码使用 Flutter，共用同一套 Dart 代码；翻译服务采用可替换的 `TranslationEngine` 接口，当前内置 LibreTranslate 兼容服务。

## 功能

- 从服务端读取实际支持的语言及可用语言组合
- 自动识别原文语言，支持最多 5000 字符的纯文本翻译
- Windows / Android 共用界面
- 一键复制译文
- 可选的本地历史记录（最近 50 条，默认关闭）
- 服务地址和 API 密钥配置；密钥只保存在当前会话
- 不上传、不内置任何第三方密钥

## 运行

先安装 Flutter 3.22 或更新版本，以及对应平台工具链。Windows 开发需要 Visual Studio 的 **Desktop development with C++** 工作负载；Android 需要 Android Studio、Android SDK 和可用设备或模拟器。

```bash
flutter pub get
flutter run -d windows
flutter run -d android
```

构建发行版本：

```bash
flutter build windows --release
flutter build apk --release
```

## 自动生成安装包

把整个项目上传到 GitHub 后，打开仓库的 **Actions → Build Lingua Open → Run workflow**。完成后，在该次运行页面底部的 **Artifacts** 下载：

- `lingua-open-android-apk`：Android APK，复制到手机安装（可能需要允许安装未知来源应用）。
- `lingua-open-windows`：Windows 发布目录，下载并解压后运行 `lingua_open.exe`。Windows 版本目前是免安装目录版，不是 MSI 安装程序。

也可以创建版本标签（例如 `v0.1.0`）触发同一流程。首次发布建议在 GitHub 的 Releases 页面附上两个构建产物。

首次启动点击“配置并连接”，输入你部署的 LibreTranslate 兼容服务 HTTPS 地址。公用服务可能限流、收费或有隐私政策，请使用你信任的服务；翻译文本会发送到该服务。

## 项目结构

- `lib/main.dart`：界面、历史记录和设置流程
- `lib/translation.dart`：翻译引擎抽象、LibreTranslate HTTP 客户端和错误处理
- `pubspec.yaml`：依赖声明

## 开发建议

新增翻译服务时实现 `TranslationEngine` 的 `languages()` 和 `translate()`，再在设置流程注入新的实现。若需要真正离线翻译，可增加基于本地模型的实现，并为 Windows 和 Android 分别提供模型下载与存储策略。

## 许可证

MIT，见 `LICENSE`。
