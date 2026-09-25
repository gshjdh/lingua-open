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

本地构建另需安装 Python 3。首次运行脚本会生成缺少的原生工程并添加 Android 网络权限。

先安装 Flutter 3.22 或更新版本，以及对应平台工具链。Windows 开发需要 Visual Studio 的 **Desktop development with C++** 工作负载；Android 需要 Android Studio、Android SDK 和可用设备或模拟器。

```bash
python scripts/prepare_platforms.py
flutter pub get
flutter run -d windows
flutter devices
# 将下面的设备 ID 换成 flutter devices 列出的 Android 设备 ID
flutter run -d <设备ID>
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

首次启动点击“配置并连接”，选择翻译引擎：

- **腾讯云机器翻译**：在腾讯云控制台开通机器翻译，创建 SecretId/SecretKey，关闭后付费，然后在应用中填写这两个密钥。腾讯云当前为文本翻译提供每月免费字符额度；超出后关闭后付费即可自动停服。密钥只在本次运行期间保留。
- **LibreTranslate**：输入你部署或选择的兼容服务 HTTPS 地址。公共服务可能限流、收费或有隐私政策，请使用你信任的服务；翻译文本会发送到该服务。

腾讯云的请求使用官方 TC3-HMAC-SHA256 签名，应用在本地生成签名，不会把 SecretKey 发送给中间服务器。

## 项目结构

- `lib/main.dart`：界面、历史记录和设置流程
- `lib/translation.dart`：翻译引擎抽象、LibreTranslate HTTP 客户端和错误处理
- `pubspec.yaml`：依赖声明

## 开发建议

新增翻译服务时实现 `TranslationEngine` 的 `languages()` 和 `translate()`，再在设置流程注入新的实现。若需要真正离线翻译，可增加基于本地模型的实现，并为 Windows 和 Android 分别提供模型下载与存储策略。

### 腾讯云配置步骤

1. 登录腾讯云控制台并完成账号认证。
2. 开通“机器翻译”，进入 API 密钥管理，创建 SecretId 和 SecretKey。
3. 在机器翻译计费设置中关闭后付费，避免免费额度用完后产生扣费。
4. 启动 Lingua Open，点击设置，选择“腾讯云机器翻译（推荐）”，填写密钥并连接。

## 许可证

MIT，见 `LICENSE`。

## 当前验证状态与安装说明

此源码尚未在 Flutter SDK 下实际编译或运行。自动构建配置已补充原生工程生成、Android 网络权限及引擎测试；需以 GitHub Actions 的真实结果为准。

1. 解压本包，打开内部 `lingua_open` 目录。
2. GitHub 新建仓库，勾选创建 README；再进入仓库选择 Add file → Upload files。
3. 上传内部目录的内容，确保仓库顶层直接有 `pubspec.yaml`、`lib`、`scripts` 和 `.github`，不要上传 ZIP 或外层文件夹。
4. 如果网页拖放未上传 `.github`，用 Add file → Create new file 创建 `.github/workflows/build.yml`，粘贴本包中同名文件内容并提交。
5. Actions → Build Lingua Open → Run workflow。成功后在运行详情底部下载 Artifacts。
6. Windows 解压全部文件后运行 `lingua_open.exe`，保留旁边的 DLL 和 data 目录。
7. Android 解压产物后将 `app-release.apk` 传到手机，点击安装。此版本用于测试，沿用 Flutter 模板调试签名，尚未配置正式发布签名。不同构建间覆盖安装可能因签名变化失败；卸载旧版会删除本地历史。
8. 启动后仍需配置可用的 LibreTranslate HTTPS 服务；项目不附送翻译服务或 API 密钥。

GitHub 操作参考：https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
