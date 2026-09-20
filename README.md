# FabricLab · Flutter

项目主入口已迁移为 Flutter，iOS 和 Android 共用 `lib/` 中的页面和业务代码。原版 `test/*.swift` 与 `FabricLab.xcodeproj` 保留用于对照，不参与 Flutter 构建。

## 环境与启动

本次使用 Flutter **3.47.5 / Dart 3.13.4**。建议使用相同 stable 版本；平台模板来自该版本。项目内 `.tools/flutter` 是本机下载的 SDK，不提交到 Git。

```powershell
# 本机直接运行；其他电脑可将完整路径改成 flutter
.\.tools\flutter\bin\flutter.bat pub get
.\.tools\flutter\bin\flutter.bat analyze
.\.tools\flutter\bin\flutter.bat test
.\.tools\flutter\bin\flutter.bat devices
.\.tools\flutter\bin\flutter.bat run -d <设备ID>
```

Android 开发需要先安装 Android Studio / Android SDK、配置 SDK 路径并完成 `flutter doctor --android-licenses`。使用实体手机验证 BLE；Android 11 及以下扫描还需要开启系统定位服务并授予定位权限。Android 12 及以上使用“附近的设备”权限。

```sh
flutter build apk --debug
```

iOS 构建需要 macOS、Xcode、CocoaPods 和有效签名，打开的是 **`ios/Runner.xcworkspace`**。首次在 Mac 上执行：

```sh
flutter pub get
cd ios
pod install
cd ..
flutter run -d <iPhone设备ID>
# 签名配置完成后
flutter build ipa
```

iOS bundle ID 和 Android application ID 均为 `com.fabriceyes.fabriclab`。iOS 部署版本为 15.0；Android 使用 Flutter 模板的最低版本。Android release 当前沿用模板的调试签名，仅用于本地验证；上架前需要配置正式签名。

## 已迁移内容

- 登录、注册、手机号/邮箱分流、验证码冷却、自动登录与退出。
- 项目入口、附近设备列表、信号强度、设备绑定和分析模式选择。
- 单次扫描立即预测、多次扫描（2–9 次）、默认/手动参考校准、结果卡片。
- NIR 和 IR2210 蓝牙发现、连接、序列号、内置参考、分包采集、实体按键扫描、断线与超时处理。
- 我的设备、设备详情、历史用量图表、分享与撤销分享。
- 账户权限展示、中英文切换；复用原版 178 条中英文文案。
- 统一蓝紫色/青色主题、20px 圆角卡片、渐变背景、底部导航、响应式宽度与系统安全区。
- 复用原版应用图标。凭据存放在 iOS Keychain / Android 安全存储，不使用普通偏好存储保存令牌。

iOS 安全存储沿用原版 Keychain service/account；同一签名身份升级可尝试恢复旧会话，仍需真机验证。系统字体、键盘、权限弹窗和返回手势保留平台行为，应用页面本身由同一套 Flutter 组件绘制。

## 接口配置

默认继续使用原服务器；可在构建时覆盖，无需改源代码：

```sh
flutter run --dart-define=API_BASE_URL=https://your-server.example
```

`lib/services/api.dart` 保留旧接口路径、字段、`Bearer` 令牌、`Accept-Language`、NIR 字符串字节流与 IR2210 强度数组格式。401 会清除会话并返回登录页。不会绕过 HTTPS 证书验证。

## 目录

| 路径 | 用途 |
| --- | --- |
| `lib/main.dart` | 应用入口、导航、全局加载和错误提示 |
| `lib/ui/` | 登录、首页、测量、设备和账户页面 |
| `lib/app_model.dart` | 会话、扫描流程、权限和界面状态 |
| `lib/services/api.dart` | 登录、设备、预测和校准接口 |
| `lib/services/bluetooth.dart` | 两端共用 BLE 连接与操作状态机 |
| `lib/services/ble_protocol.dart` | 可独立测试的 NIR/IR2210 协议解析 |
| `assets/l10n/` | 中英文文案 |
| `android/`、`ios/` | Flutter 平台工程 |
| `test/*_test.dart` | Flutter 页面、状态、接口和协议测试 |
| `tool/ui_preview_test.dart` | 可选的本地页面截图工具，仅使用测试夹具 |

## 验证与边界

静态检查、自动化测试与本地页面渲染可在 Windows 执行。本机未安装 Android SDK、未连接设备，因此没有生成 APK；iOS 编译、签名及两端真实蓝牙通信尚未验证。接口测试使用 mock，不代表已与生产服务联调。截图使用本地测试数据，不会进入生产应用。

原版的“保存光谱”按钮和 IR2210 参数设置并未实际接通。Flutter 保留对应页面入口，参数页明确标注仅预览，写入/保存按钮禁用；没有编造设备写入协议或假装保存成功。

真机验收步骤见 [迁移记录](docs/flutter-migration.md)。

可选生成页面截图（`UI_FONT_PATH` 指向本机中英文字体，不会把系统字体打包进应用）：

```powershell
.\.tools\flutter\bin\flutter.bat test tool/ui_preview_test.dart --dart-define=UI_FONT_PATH=C:/Windows/Fonts/msyh.ttc
```

输出在 `build/previews/`，已被 Git 忽略。
