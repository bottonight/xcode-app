# Flutter 迁移记录

## 页面对照

| SwiftUI | Flutter |
| --- | --- |
| AuthenticationView | AuthPage |
| ProjectGridView / DeviceDiscoveryView / ModeSelectionView | HomePage |
| MeasurementWorkbenchView / DeviceSettingsView | HomePage / DeviceSettingsPage |
| DeviceManagementView / ManagedDeviceDetailView | DevicesPage / DeviceDetailPage |
| DeviceSharingView / AccountView | SharingPage / AccountPage |
| FabricTheme / BrandCardModifier | fabricTheme / BrandCard |

保留原有导航顺序和权限门槛。单个分析模式直接进入工作台；多个模式先选择；LINE / REPORT 权限项不作为分析模式。未开放的三个项目继续禁用。

## 通信对照

- BLE 根据 NIR / IR2210 广播名前缀筛选；不强制服务 UUID 广播过滤，以兼容只广播名称的原有固件。
- NIR 按 UUID **及读/写/通知属性**选择特征值，兼容同 UUID 的写入和通知句柄。每次连接重新发现服务并订阅通知；先订阅再发命令。
- NIR 忽略编号 0 的元数据包，以编号 202 为终止包，要求恰好 3822 字节；内置参考仅在当前连接缓存。
- IR2210 使用 FFE0/FFE1/FFE2 协议，支持碎片帧、合并帧、校验和检查、按组号重组 64 组数据以及大端 256 点解码。
- 两种设备都保留实体扫描按键事件；后台停止发现，连接内的操作有超时，不声明未实现的后台恢复能力。
- 断线清除设备状态与测量缓存，丢弃断线期间尚未返回的预测结果，防止旧结果回填新页面。
- `should_init` 与原版一样未触发额外初始化；仓库没有可迁移的初始化实现。

## 依赖

Flutter 3.47.5；flutter_blue_plus 固定为 1.36.8（该发布版本为 BSD-3-Clause，避免无意切换到 2.x 的授权要求）；flutter_secure_storage 9.2.4；http；shared_preferences。提交 pubspec.lock 固定实际依赖解析结果。

官方参考：[Flutter iOS 配置](https://docs.flutter.dev/platform-integration/ios/setup)、[FlutterBluePlus 1.36.8](https://pub.dev/packages/flutter_blue_plus/versions/1.36.8)。协议以仓库 `docs/ble-uuid-mapping.md` 和原版 Swift 实现为准。

## 真机验收（尚未执行）

1. Android 11 和 Android 12+ 分别检查首次授权、拒绝授权、重新授权、蓝牙关闭、开启以及扫描空态；Android 11 及以下开启系统定位。
2. iPhone 检查蓝牙用途说明、权限拒绝后恢复、使用相同签名从旧版升级及会话恢复。
3. 用测试账户完成登录、注册、验证码、退出、重启自动登录、401 会话失效，以及手机号/邮箱接口字段。
4. 分别连接 NIR 与 IR2210，核对序列号、账号权限、未绑定提示、绑定后的分析模式。
5. 核对默认参考/手动校准、单次扫描、2 次与 9 次多点预测、清空和第 10 次限制。
6. 分别通过手机按钮、硬件按键扫描；在采集中、拉取参考中、预测中主动断开，确认没有挂起或旧结果回填。
7. 测试共享用户加载、添加、撤销、设备历史用量、语言切换和小屏/大字体布局。
8. 对照两端截图验证卡片、间距、颜色、底部导航和工作台；系统弹窗与字体允许平台差异。
9. 正式发布前配置 Android release 签名、iOS team/provisioning，并完成两端 release 构建。

## 原版已有的功能缺口

- 光谱保存入口保留提示，不发送保存请求。
- IR2210 参数与厂商/暗电流校准页面保留布局，明确预览状态，禁用尚无实现的设备写入。
- 不显示原版未开放的光谱查看页面；admin >= 1 可见扩展操作，admin >= 2 可见 IR2210 参数页。
