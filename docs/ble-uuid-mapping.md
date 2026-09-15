# 项目 BLE 接口与 UUID 对照

本文对照当前小程序代码（主要是 `utils/btdevice.js`）与设备文档，把**按下标访问的 GATT 服务/特征值**还原成实际 UUID。

主文档：`dlpu030g.pdf`（TI *DLP NIRscan Nano EVM User's Guide*，文献号 DLPU030G，附录 J）。

---

## 1. 项目里有三套 BLE 设备

扫描过滤名见 `utils/btdevice.js` 的 `onBluetoothDeviceFound`：`NIR*` / `VSPK*` / `IR2210*`。

| 设备名前缀 | 协议来源 | UUID 用法 |
| --- | --- | --- |
| `NIR` | `dlpu030g.pdf` 附录 J | **按下标**取 `services[n]`、`characteristics[m]` |
| `IR2210` | `IR2210蓝牙通讯协议`（已写进 `utils/ir2210_protocol.js`） | **直接写死 UUID** |
| `VSPK` | 扫描笔自定义帧（`0x3D` / `0x5A`），不在 DLPU030G 里 | 按下标，文档未给出 UUID |

下文第 3 节是 NIR 的核心对照。IR2210、VSPK 见第 4、5 节。

---

## 2. 微信小程序 BLE API（项目实际调用）

| API | 用途 | 主要位置 |
| --- | --- | --- |
| `wx.openBluetoothAdapter` | 打开蓝牙适配器 | `btdevice.deviceInit` |
| `wx.closeBluetoothAdapter` | 关闭适配器 | `btdevice.closeBluetoothAdapter` |
| `wx.onBluetoothAdapterStateChange` | 等待用户打开系统蓝牙 | `deviceInit` |
| `wx.startBluetoothDevicesDiscovery` | 扫描附近设备 | `startBluetoothDevicesDiscovery` |
| `wx.stopBluetoothDevicesDiscovery` | 停止扫描 | 连接前后、页面卸载 |
| `wx.onBluetoothDeviceFound` | 发现设备回调 | `onBluetoothDeviceFound` |
| `wx.createBLEConnection` | 连接 | `createBLEConnection` / 重连 |
| `wx.closeBLEConnection` | 断开 | `closeBLEConnection` |
| `wx.onBLEConnectionStateChange` | 断线监听 | `onDeviceConnectionState` |
| `wx.getBLEDeviceServices` | 枚举 GATT 服务 | NIR / VSPK / IR2210 发现流程 |
| `wx.getBLEDeviceCharacteristics` | 枚举特征值 | 同上 |
| `wx.readBLECharacteristicValue` | 读 | 电量、序列号、温湿度 |
| `wx.writeBLECharacteristicValue` | 写 | 启动扫描、拉光谱、校准 |
| `wx.notifyBLECharacteristicValueChange` | 订阅 Notify | 扫描完成、数据包、温湿度 |
| `wx.onBLECharacteristicValueChange` | 收 Notify/Read 结果 | 各业务回调 |
| `wx.offBLECharacteristicValueChange` | 取消监听 | 切换业务前 |

微信对 16-bit UUID 会展开成：

```text
0000XXXX-0000-1000-8000-00805F9B34FB
```

自定义 128-bit UUID 保持文档原样。大小写以设备/系统返回为准，比较时建议忽略大小写。

`wx.getBLEDeviceServices` **通常不返回** GAP `0x1800`、GATT `0x1801`。下面的下标都是按这个返回数组计算的。

---

## 3. NIR（NIRscan Nano）下标 → UUID

自定义 UUID 的 ASCII 含义：

- 服务：`SER` + 编号 + `DLP NIR Nano` → `534552xx-444C-5020-4E49-52204E616E6F`
- 特征值：`CHA` + 编号 + `DLP NIR Nano` → `434841xx-444C-5020-4E49-52204E616E6F`

附录 J 列出 8 个服务。结合代码实际使用的下标 `0 / 1 / 3 / 5 / 7`，`wx.getBLEDeviceServices` 的顺序如下。

### 3.1 服务总表 `app.globalData.services[i]`

| 下标 | 文档名称 | 16-bit / 128-bit UUID | 微信展开后的 UUID | 项目是否使用 |
| --- | --- | --- | --- | --- |
| `[0]` | Battery Service (BAS) Table J-2 | `0x180F` | `0000180F-0000-1000-8000-00805F9B34FB` | 是，电量 |
| `[1]` | Device Information (DIS) Table J-1 | `0x180A` | `0000180A-0000-1000-8000-00805F9B34FB` | 是，序列号 / 设备 UUID |
| `[2]` | GATT Command Service (GCS) Table J-8 | `0x53455202-...` | `53455202-444C-5020-4E49-52204E616E6F` | 否 |
| `[3]` | GATT General Information (GGIS) Table J-3 | `0x53455201-...` | `53455201-444C-5020-4E49-52204E616E6F` | 是，温度 / 湿度 |
| `[4]` | GATT Date and Time (GDTS) Table J-4 | `0x53455203-...` | `53455203-444C-5020-4E49-52204E616E6F` | 否 |
| `[5]` | GATT Calibration (GCIS) Table J-5 | `0x53455204-...` | `53455204-444C-5020-4E49-52204E616E6F` | 是，内置参考/校准 |
| `[6]` | GATT Scan Configuration (GSCIS) Table J-6 | `0x53455205-...` | `53455205-444C-5020-4E49-52204E616E6F` | 否 |
| `[7]` | GATT Scan Data (GSDIS) Table J-7 | `0x53455206-...` | `53455206-444C-5020-4E49-52204E616E6F` | 是，扫描与拉光谱 |

`[2][4][6]` 是为了让 `[0][1][3][5][7]` 同时对上文档而补全的；项目当前没有读写它们。若某固件插入了 GAP/GATT 或打乱顺序，下标会错位，应用 UUID 匹配而不是下标。

### 3.2 `services[0]` BAS — 电量

代码：`getBattery` / `getBatteryInfo` / `pages/normal/index.js` 读电量。

| 下标 | 名称 | UUID | 属性 | 代码行为 |
| --- | --- | --- | --- | --- |
| `characteristics[0]` | Battery Level | `00002A19-0000-1000-8000-00805F9B34FB`（`0x2A19`） | Read | 读 1 字节，0–100 |

### 3.3 `services[1]` DIS — 序列号与设备 UUID

代码：`getSerialnumbeAppend`、`getUUId`。

Table J-1 顺序：

| 下标 | 名称 | UUID | 属性 | 项目 |
| --- | --- | --- | --- | --- |
| `[0]` | Manufacturer Name | `00002A29-0000-1000-8000-00805F9B34FB`（`0x2A29`） | Read | 未用 |
| `[1]` | Model Number | `00002A24-0000-1000-8000-00805F9B34FB`（`0x2A24`） | Read | 未用 |
| `[2]` | Serial Number | `00002A25-0000-1000-8000-00805F9B34FB`（`0x2A25`） | Read | **使用**，`getSerialnumbeAppend` |
| `[3]` | Hardware Revision | `00002A27-0000-1000-8000-00805F9B34FB`（`0x2A27`） | Read | 未用 |
| `[4]` | Tiva Firmware Revision | `00002A26-0000-1000-8000-00805F9B34FB`（`0x2A26`） | Read | 未用 |
| `[5]` | Spectrum Library Revision | `00002A28-0000-1000-8000-00805F9B34FB`（`0x2A28`） | Read | 未用 |
| `[6]` | System ID（Table J-1 未列，常见 Bluetopia DIS 会带） | `00002A23-0000-1000-8000-00805F9B34FB`（`0x2A23`） | Read | **使用**，`getUUId`，当设备唯一 ID |

`[6]` 以固件实际枚举为准；若某机型 DIS 只有 6 项，这个下标会越界或读到别的特征。

### 3.4 `services[3]` GGIS — 温度 / 湿度

代码：`getTemperature`、`getHumidity`。温度、湿度都是 2 字节整数，**除以 100** 得到实际值（与 Table J-3 一致）。

| 下标 | 名称 | UUID | 属性 | 项目 |
| --- | --- | --- | --- | --- |
| `[0]` | Temperature measurement | `43484101-444C-5020-4E49-52204E616E6F` | Read + Notify | **使用** |
| `[1]` | Humidity measurement | `43484102-444C-5020-4E49-52204E616E6F` | Read + Notify | **使用** |
| `[2]` | Device status | `43484103-444C-5020-4E49-52204E616E6F` | Read + Notify | 未用 |
| `[3]` | Error status | `43484104-444C-5020-4E49-52204E616E6F` | Read + Notify | 未用 |
| `[4]` | Temperature threshold | `43484105-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[5]` | Humidity threshold | `43484106-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[6]` | Hours of use | `43484107-444C-5020-4E49-52204E616E6F` | Read | 未用 |
| `[7]` | Battery recharge cycles | `43484108-444C-5020-4E49-52204E616E6F` | Read | 未用 |
| `[8]` | Total lamp hours | `43484109-444C-5020-4E49-52204E616E6F` | Read | 未用 |
| `[9]` | Error log | `4348410A-444C-5020-4E49-52204E616E6F` | Read | 未用 |

### 3.5 `services[5]` GCIS — 内置参考 / 校准

代码：`getBuiltin`。流程与文档 5.4.2.3、Table J-5 一致：先订阅返回特征，再向请求特征写 1 字节，设备用多包 Notify 把参考校准系数推过来。

| 下标 | 名称 | UUID | 属性 | 项目 |
| --- | --- | --- | --- | --- |
| `[0]` | Request Spectrum Calibration Coefficients | `4348410D-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[1]` | Return Spectrum Calibration Coefficients | `4348410E-444C-5020-4E49-52204E616E6F` | Notify（多包） | 未用 |
| `[2]` | Request Reference Calibration Coefficients | `4348410F-444C-5020-4E49-52204E616E6F` | Write | **使用**，写入 `0x00` |
| `[3]` | Return Reference Calibration Coefficients | `43484110-444C-5020-4E49-52204E616E6F` | Notify（多包） | **使用** |
| `[4]` | Request Reference Calibration Matrix | `43484111-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[5]` | Return Reference Calibration Matrix | `43484112-444C-5020-4E49-52204E616E6F` | Notify（多包） | 未用 |

多包格式见 Table J-9。代码把首字节当包序号，`202`（`0xCA`）当最后一包。

### 3.6 `services[7]` GSDIS — 扫描与光谱数据

代码：`onScan`、`Scan`、`writeBLECharacteristicValue`，以及 `pages/normal/index.js`、`homepage/subpage/feedback/index.js`。

固件把部分 **Write + Notify 拆成两条同 UUID、不同属性的特征值**（TI 设备常见做法，iOS/微信会各列一项）。因此数组比 Table J-7 的“逻辑特征”更长，`[4]/[5]`、`[16]/[17]` 才能对上。

代码里 `handle: 133` / `handle: 135` 对应 Start Scan 的写句柄和 Notify 句柄。

| 下标 | 名称 | UUID | 属性 | 项目 |
| --- | --- | --- | --- | --- |
| `[0]` | Number of SD Card stored scans | `43484119-444C-5020-4E49-52204E616E6F` | Read | 未用 |
| `[1]` | Request stored scan indices list | `4348411A-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[2]` | Return stored scan indices list | `4348411B-444C-5020-4E49-52204E616E6F` | Notify（多包） | 未用 |
| `[3]` | Set scan name stub | `4348411C-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[4]` | Start scan（写） | `4348411D-444C-5020-4E49-52204E616E6F` | **Write** | **使用**（`Scan` / `ReScan`，写 `0x00` 表示不存 SD） |
| `[5]` | Start scan（通知） | `4348411D-444C-5020-4E49-52204E616E6F` | **Notify** | **使用**（扫描完成；首字节 `0xFF` + 4 字节 scan index） |
| `[6]` | Clear scan（写） | `4348411E-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[7]` | Clear scan（通知） | `4348411E-444C-5020-4E49-52204E616E6F` | Notify | 未用 |
| `[8]` | Request scan name | `4348411F-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[9]` | Return scan name | `43484120-444C-5020-4E49-52204E616E6F` | Notify | 未用 |
| `[10]` | Request scan type | `43484121-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[11]` | Return scan type | `43484122-444C-5020-4E49-52204E616E6F` | Notify | 未用 |
| `[12]` | Request scan date/time | `43484123-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[13]` | Return scan date/time | `43484124-444C-5020-4E49-52204E616E6F` | Notify | 未用 |
| `[14]` | Request packet format version | `43484125-444C-5020-4E49-52204E616E6F` | Write | 未用 |
| `[15]` | Return packet format version | `43484126-444C-5020-4E49-52204E616E6F` | Notify | 未用 |
| `[16]` | Request serialized scan data | `43484127-444C-5020-4E49-52204E616E6F` | Write | **使用**，写入 4 字节 scan index |
| `[17]` | Return serialized scan data | `43484128-444C-5020-4E49-52204E616E6F` | Notify（多包） | **使用**，首字节 `202` 表示收完 |

同一 UUID 出现两次时，必须按 **属性**（Write / Notify）区分，不能只按 UUID 取第一项。

### 3.7 NIR 业务与下标速查

| 业务 | 函数 | 服务下标 | 特征值下标 | 实际 UUID |
| --- | --- | --- | --- | --- |
| 读电量 | `getBattery` / `getBatteryInfo` | `services[0]` | `[0]` | 服务 `0000180F-...`，特征 `00002A19-...` |
| 读序列号 | `getSerialnumbeAppend` | `services[1]` | `[2]` | 服务 `0000180A-...`，特征 `00002A25-...` |
| 读设备 UUID | `getUUId` | `services[1]` | `[6]` | 服务 `0000180A-...`，特征多为 `00002A23-...` |
| 读温度 | `getTemperature` | `services[3]` | `[0]` | `43484101-444C-5020-4E49-52204E616E6F` |
| 读湿度 | `getHumidity` | `services[3]` | `[1]` | `43484102-444C-5020-4E49-52204E616E6F` |
| 拉内置参考 | `getBuiltin` | `services[5]` | 写 `[2]`，Notify `[3]` | `4348410F-...` / `43484110-...` |
| 监听扫描完成 | `onScan` | `services[7]` | `[5]` | `4348411D-...`（Notify） |
| APP 主动开扫 | `Scan` | `services[7]` | 写 `[4]`，Notify `[5]` | `4348411D-...` |
| 拉光谱数据 | `onScan` 完成回调 | `services[7]` | 写 `[16]`，Notify `[17]` | `43484127-...` / `43484128-...` |

---

## 4. IR2210（已用 UUID，不是下标）

`utils/ir2210_protocol.js` 已按《IR2210蓝牙通讯协议》写死：

| 角色 | UUID |
| --- | --- |
| Service | `0000FFE0-0000-1000-8000-00805F9B34FB` |
| Write（APP → 设备，Write Without Response） | `0000FFE1-0000-1000-8000-00805F9B34FB` |
| Notify（设备 → APP） | `0000FFE2-0000-1000-8000-00805F9B34FB` |

注意：`get_ir2210_sn` 仍会 `getBLEDeviceServices` 后访问 `services[0]`，真正读写走的是上面三个常量。只要 `services[0]` 不是 `FFE0`，发现步骤可能空转，但不影响后续 `readDeviceNumber` 等用 UUID 的调用。

---

## 5. VSPK 扫描笔

`pencil_scan` / `newBuild` / `get_sn` 使用：

- `services[0]`
- `characteristics[0]`：写命令
- `characteristics[1]`：Notify 回包

帧格式是自定义的（发送带 CRC 的 `0x3D ...`，回包 `0x5A...`），**不在 `dlpu030g.pdf` 中**。常见于串口透传模组（如 `FFE0/FFE1` 一类），但本仓库没有对应协议文档，不能根据 TI 附录推断 UUID。要用 UUID 访问，需要在真机上打印 `res.services` / `res.characteristics`。

---

## 6. 未使用但文档有的服务（NIR）

便于以后按 UUID 补功能，而不是再加下标：

| 服务 | UUID | 用途（附录 J） |
| --- | --- | --- |
| GCS | `53455202-444C-5020-4E49-52204E616E6F` | 通用命令；特征 `4348410B-444C-5020-4E49-52204E616E6F` |
| GDTS | `53455203-444C-5020-4E49-52204E616E6F` | 写设备日期时间；特征 `4348410C-444C-5020-4E49-52204E616E6F` |
| GSCIS | `53455205-444C-5020-4E49-52204E616E6F` | 扫描配置列表 / 激活配置（`43484113`–`43484118`） |

---

## 7. 建议

1. 新代码按 **UUID** 查找服务和特征值，不要再依赖 `services[7]` 这种下标。
2. GSDIS 的 Start Scan 等特征 UUID 重复时，用 `properties.notify` / `properties.write` 区分。
3. 比较 UUID 时统一转大写（或统一小写）。
4. 打印机相关混淆：`utils/JCAPI/JCAPIManager.js` 里也有微信 BLE API 字符串，那是打印 SDK，与 NIR/IR2210 无关。
