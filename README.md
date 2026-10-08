# FabricLab

FabricLab 是 NIR / IR2210 织物分析应用，用 Flutter 同时覆盖 Android 和 iOS。页面、会话、接口和蓝牙协议都在 `lib/`，两端共用同一套业务代码。

当前版本：**Flutter 3.47.5 / Dart 3.13.4**。应用 ID（Android application ID 与 iOS bundle ID）均为 `com.fabriceyes.fabriclab`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `lib/main.dart` | 入口、导航、全局加载和错误提示 |
| `lib/app_model.dart` | 会话、扫描流程、权限和界面状态 |
| `lib/models.dart` | 设备、测量和账户数据模型 |
| `lib/ui/` | 登录、首页、测量、设备和账户页面 |
| `lib/services/api.dart` | 登录、设备、预测和校准接口 |
| `lib/services/bluetooth.dart` | 两端共用的 BLE 连接与操作状态机 |
| `lib/services/ble_protocol.dart` | NIR / IR2210 协议解析 |
| `assets/l10n/` | 中英文文案 |
| `android/` | Android 工程（Gradle） |
| `ios/` | iOS 工程；`ios/ci_scripts/ci_post_clone.sh` 供 Xcode Cloud 使用 |
| `docs/` | 登录、预测接口和蓝牙协议说明 |
| `test/` | Flutter 自动化测试（`*_test.dart`） |
| `FabricLab.xcodeproj`、`test/*.swift` | 原版 Swift 工程，当前发布不使用 |

## Android 编译

在 Windows 或 macOS 上本地编译。需要已安装 Flutter 3.47.5、Android Studio（含 Android SDK），并接受 SDK 许可。

在仓库根目录执行（不要进入 `.tools\flutter`，那里是 SDK 自身）：

```powershell
.\.tools\flutter\bin\flutter.bat doctor --android-licenses
.\.tools\flutter\bin\flutter.bat pub get
.\.tools\flutter\bin\flutter.bat build apk --debug
```

调试包输出在 `build/app/outputs/flutter-apk/app-debug.apk`。需要可安装的 release 包时：

```powershell
.\.tools\flutter\bin\flutter.bat build apk --release
```

当前 release 沿用调试签名，只适合本机验证。上架前要换成正式签名（`android/app/build.gradle.kts` 里的 `signingConfig`）。

连真机看蓝牙时：Android 12 及以上授予「附近的设备」；Android 11 及以下还要打开系统定位并授予定位权限。

接口地址可在编译时覆盖，不必改源码：

```powershell
.\.tools\flutter\bin\flutter.bat build apk --debug --dart-define=API_BASE_URL=https://your-server.example
```

`.tools/` 是本机 Flutter SDK，不提交到 Git。系统 PATH 里已有同版本 `flutter` 时，可以把上面的 `.\.tools\flutter\bin\flutter.bat` 换成 `flutter`。

## iOS 编译

iOS 由 **Xcode Cloud** 编译，本地不需要 Mac、Xcode 或 CocoaPods。签名、工作流和 `ios/Runner.xcworkspace`（Scheme `Runner`，Release）已经配好。

把代码推到已接入该工作流的分支后，云端会自动：

1. 拉取仓库。
2. 执行 `ios/ci_scripts/ci_post_clone.sh`：安装 Flutter 3.47.5、`flutter pub get`、`pod install`，再跑 `flutter build ios --config-only --release`。
3. 用 Xcode 归档并产出安装包。构建号取 Xcode Cloud 的 `CI_BUILD_NUMBER`。

需要指向其他服务器时，在工作流环境变量里设置 `API_BASE_URL`，脚本会把它传给 `--dart-define`。不设置则使用代码里的默认服务器。

iOS 部署版本为 15.0。

## 本地检查

改完 Dart 代码后，可在 Windows 上做静态检查和测试，再按上面的方式出 Android 包或推送触发 iOS 云编译：

```powershell
.\.tools\flutter\bin\flutter.bat pub get
.\.tools\flutter\bin\flutter.bat analyze
.\.tools\flutter\bin\flutter.bat test
```
