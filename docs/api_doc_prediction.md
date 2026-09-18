# PredictionPage 接口文档

近红外成分预测、校准与波形采集相关接口。Blueprint 前缀：`/apps/PredictionPage`。

完整路径示例：`/apps/PredictionPage/Prediction`

**账号约定**：
- `openid` 可为空。为空时需传 `phone_number` / `phone_num` **或** `email`（二选一）以识别用户。
- 手机号、邮箱分别对应 `t_users.phone_num`、`t_users.email`。

**鉴权约定**：
- 业务接口需登录，请求头带 `Authorization: Bearer <token>`，或 Cookie `token`。
- `/ComponentLabel`、`/test` 除外。
- 登录成功即可，不要求管理员权限。未登录或 token 无效返回 HTTP 401。

**语言约定**：
- 请求头带 `Accept-Language: zh-Hans` 或 `en`。`error` / `info` 等提示按该语言返回。
- 未传或无法识别时默认简体中文（`zh-Hans`）。

**扫描数据格式**：

### NIR `data`（`/Prediction`、`/viewSpectrum`、`/reScan`）

普通设备是 **一维字节数组**，每次扫描固定 **3822** 个点，多次扫描首尾拼接（不是二维数组）。元素为 0–255 的整数。

单次（长度 3822）：

```json
{ "data": [12, 34, 56] }
```

`data` 共 3822 个 0–255 整数。多次 N 次则把 N 段 3822 点 **首尾拼成一条一维数组**，长度 `3822 * N`。

`is_qt=true` 时不是字节流，而是波长/强度：

```json
{
  "data": {
    "w": [900.0],
    "i": [1200]
  }
}
```

- `w`：228 个波长（多次扫描复用前 228 个）
- `i`：单次 228 个强度；多次为 `228 * N` 拼接

### IR2210 `intensity`（`/IR2210Prediction`）

已是强度值，固定 **256** 点。单次一维，多次二维。用 `intensity[0]` 是数字还是数组来区分。波长不随请求传，使用设备参考光谱中的 `w`。

单次（一维，长度 256）：

```json
{ "intensity": [1024, 1100, 980] }
```

多次 N 次（二维，`N × 256`）：

```json
{
  "intensity": [
    [1024, 1100],
    [998, 1050]
  ]
}
```

### SaveWave `wave`

- `/SaveWaveTI` 的 `wave`：与 NIR 原始扫描同结构（3822 点字节流）。单次一维；多次为二维（每条 3822），**不是**首尾拼接。
- `/SaveWaveOP` 的 `wave`：与 IR2210 `intensity` 同结构（256 点强度）。单次一维；多次为二维（每条 256）。

详见第 16、17 节。

---

## 1. /SetReference
- **方法**: POST
- **描述**: 设置/更新设备参考光谱（校准）
- **参数** (json):
  - data: 参考光谱。普通设备为单次 NIR 原始字节流（长度 3822，见文首「扫描数据格式」）；`is_qt=true` 时直接作为 `{w, i}` 写入
  - mac_NIR
  - serial_number（可选，优先用于查找）
  - uuid（可选）
  - is_qt（可选）
- **返回**:
  - status: `succeed`
  - error: `null`

---

## 2. /SetIR2210DefaultRef
- **方法**: POST
- **描述**: 设置 IR2210 默认校准（TI / OP）
- **参数** (json):
  - intensity: 256 点强度数组
  - serial_number
  - device_type: `0`=TI 校准片，`1`=OP 校准片
- **返回**:
  - status: `true` / `false`
  - error

---

## 3. /SetIR2210UserRef
- **方法**: POST
- **描述**: 设置 IR2210 用户手动校准参考
- **参数** (json):
  - intensity: 256 点强度数组
  - serial_number
- **返回**:
  - status: `true` / `false`
  - error

---

## 4. /SetIR2210Dark
- **方法**: POST
- **描述**: 设置 IR2210 暗电流参考
- **参数** (json):
  - intensity
  - serial_number
- **返回**:
  - status: `true` / `false`
  - error

---

## 5. /SetIR2210Coefficient
- **方法**: POST
- **描述**: 设置 IR2210 波长系数（a/b/c/d）
- **参数** (json):
  - serial_number
  - a / b / c / d（或整体系数结构，以实现为准）
- **返回**:
  - status: `true` / `false`
  - error

---

## 6. /viewSpectrum
- **方法**: POST
- **描述**: 查看光谱图（吸光度/反射率），返回 base64 图片
- **参数** (json):
  - data: 扫描光谱，格式见文首「NIR `data`」（单次 3822，多次 `3822 * N` 拼接；QT 为 `{w, i}`）
  - mac_NIR / serial_number / is_builtin / builtin / uuid / is_qt 等（与 `/Prediction` 类似）
  - openid（可空）
  - phone_number **或** email（openid 为空时必填其一）
- **返回**:
  - status
  - plot_a / plot_r（base64 图）
  - error

---

## 7. /Prediction
- **方法**: POST
- **描述**: 通用成分预测（走模型透传服务 `NIR_model_url1`）
- **参数** (json):
  - data: 扫描光谱，格式见文首「NIR `data`」（单次 3822 点；多次为 `3822 * N` 一维拼接）
  - mac_NIR
  - model_name: 如 `JYS` / `S` 等
  - openid（可空）
  - phone_number **或** email（openid 为空时必填其一）
  - serial_number
  - is_builtin / builtin（可选）
  - view_spectrum（可选）: 是否返回光谱图
  - uuid / is_qt（QT 场景）
- **返回**:
  - result: 中文成分字符串（经 Decoder）
  - pre_id
  - status: `true` / `false`
  - model_name / use_count_month
  - plot_a / plot_r（可选）
  - error

---

## 8. /IR2210Prediction
- **方法**: POST
- **描述**: IR2210 设备成分预测；支持特征对齐适配器
- **参数** (json):
  - intensity: 256 点强度，格式见文首「IR2210 `intensity`」（单次一维；多次为 `N × 256` 二维数组）
  - serial_number
  - model_name
  - openid（可空）
  - phone_number **或** email（openid 为空时必填其一）
  - is_default_ref: `true` 用 TI 默认参考，否则用用户参考
  - is_adapter（可选）: `true` 时调用 OPTC 特征对齐适配器服务（`GeneralConfig.NIR_optc_adapter_url`），否则走原 TI 透传
- **返回**:
  - result: 中文成分字符串
  - status: `true` / `false`
  - model_name / use_count_month
  - error（适配器失败时返回服务 detail）

---

## 9. /getIR2210ReferenceTime
- **方法**: POST
- **描述**: 查询 IR2210 用户参考最近修改时间
- **参数** (json):
  - serial_number
- **返回**:
  - status: `true` / `false`
  - user_modify_time
  - error

---

## 10. /ReferenceTime
- **方法**: POST
- **描述**: 查询普通设备校准创建/修改时间
- **参数** (json):
  - mac_NIR
  - uuid / is_qt（可选）
- **返回**:
  - create_time / modify_time
  - status: `succeed`
  - error

---

## 11. /ComponentLabel
- **方法**: POST
- **描述**: 返回成分中文标签列表
- **参数**: 无
- **返回**:
  - labels: 成分名列表
  - status: `succeed`
  - error: `null`

---

## 12. /reScan
- **方法**: POST
- **描述**: 重扫预测并与原预测对比出图
- **参数** (json):
  - data: 扫描光谱，格式见文首「NIR `data`」
  - mac_NIR / model_name / is_builtin / builtin
  - t_preid: 原预测 id
  - openid（可空）
  - phone_number **或** email（openid 为空时必填其一）
  - components_truth（可选）
- **返回**:
  - result / status / error（以及对比图相关字段，以实现为准）

---

## 13. /DataCollection
- **方法**: POST
- **描述**: 保存普通数据采集记录
- **参数** (json):
  - label / components / data / tel / device_id / name
- **返回**:
  - status: `true`
  - id
  - error: `null`

---

## 14. /NirScanCollect
- **方法**: POST
- **描述**: NIR 扫描采集入库（需内置校准）
- **参数** (json):
  - label / components / data / buildIn / tel / device_id / name
- **返回**:
  - status: `true` / `false`
  - id（成功时）
  - error

---

## 15. /DeleteData
- **方法**: POST
- **描述**: 删除采集数据
- **参数** (json):
  - id
  - is_nir: `true` 删 `NirDataCollection`，否则删 `DataCollection`
- **返回**:
  - status: `true` / `false`
  - error

---

## 16. /SaveWaveTI
- **方法**: POST
- **描述**: 保存 TI（普通 NIR）设备波形，可附带样品图。参考光谱按 `serial_number` 从参考表读取（`is_default_ref=true` 用内置校准 `wave_builtin`，否则用手动校准 `wave`）。
- **参数** (json):
  - serial_number: 设备序列号
  - device_name: 设备名（可选）
  - wave: 原始扫描字节流，**与 `/Prediction` 的 NIR `data` 点数相同（每次 3822），但多次扫描用二维数组，不要首尾拼接**
    - 单次：一维数组，长度 3822
    - 多次：二维数组，`N × 3822`，每条单独入库
  - openid（可空）
  - phone_number **或** email（openid 为空时用于记录 creator）
  - is_default_ref（可选）: `true` 用内置参考，否则用用户参考
  - components_pre（可选）: 预测成分结果
  - components_tag（可选）: 成分标签
  - fabric_id（可选）: 布样编号
  - remark（可选）: 备注
  - battery_percent（可选）: 电量
  - integration_time_us（可选）: 积分时间（微秒）
  - image_base64 / image（可选）: 样品图，支持纯 base64 或 `data:image/...;base64,` 前缀
- **wave 示例**:

单次：

```json
{
  "serial_number": "TI-001",
  "device_name": "NIR-A",
  "wave": [12, 34, 56],
  "is_default_ref": true,
  "openid": "",
  "email": "user@example.com"
}
```

`wave` 长度为 3822。多次：

```json
{
  "serial_number": "TI-001",
  "wave": [
    [12, 34, 56],
    [78, 90, 12]
  ]
}
```

每个内层数组长度 3822。
- **返回**:
  - status: `"succeed"` / `false`
  - error
  - saved: 成功写入条数

---

## 17. /SaveWaveOP
- **方法**: POST
- **描述**: 保存 OP/IR2210 波形。`wave` 为 256 点强度（与 `/IR2210Prediction` 的 `intensity` 相同）。保存前做光强过低、谱线异常检测；异常谱写入异常表并返回失败，需重扫后再保存。
- **参数** (json):
  - serial_number: 设备序列号
  - device_name: 设备名（可选）
  - wave: 256 点强度数组
    - 单次：一维数组，长度 256
    - 多次：二维数组，`N × 256`，每条单独入库
  - openid（可空）
  - phone_number **或** email（openid 为空时用于记录 creator）
  - is_default_ref（可选）: `true` 用 TI 默认参考 `ref_ti`，否则用用户参考 `ref_user`
  - components_pre / components_tag / fabric_id / remark / battery_percent / integration_time_us（可选，含义同 `/SaveWaveTI`）
  - image_base64 / image（可选）
- **wave 示例**:

单次：

```json
{
  "serial_number": "OP-001",
  "device_name": "IR2210-A",
  "wave": [1024, 1100, 980],
  "is_default_ref": false,
  "phone_number": "13800138000"
}
```

`wave` 长度为 256。多次：

```json
{
  "serial_number": "OP-001",
  "wave": [
    [1024, 1100, 980],
    [998, 1050, 970]
  ]
}
```

每个内层数组长度 256。
- **返回**:
  - 成功: `status` 为 `"succeed"`，`saved` 为写入条数，`error` 为 `null`
  - 谱线异常: `status` 为 `false`，`error` 为原因说明，`saved_error` 为写入异常表的条数

---

## 18. /SetBuild
- **方法**: POST
- **描述**: 设置内置校准光谱到参考表
- **参数** (json):
  - data / mac_NIR / serial_number 等
- **返回**:
  - status: `true` / `false`
  - error

---

## 19. /PencilPredict
- **方法**: POST
- **描述**: 铅笔硬度等相关预测（外部模型服务）
- **参数** (json): 以实现为准
- **返回**:
  - status / result / error

---

## 20. /Prediction_test、/Prediction_test1、/Prediction_test2、/Prediction_err_test、/test
- **方法**: POST / GET（见代码）
- **描述**: 调试/测试接口，生产慎用
- **参数 / 返回**: 以实现与调试需求为准

---
