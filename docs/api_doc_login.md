# LoginPage 接口文档

用户登录、设备绑定与权限相关接口。Blueprint 前缀：`/apps/LoginPage`。

完整路径示例：`/apps/LoginPage/login`

**账号约定**：
- `t_users` 主键为自增 `user_id`；`openid` 可为空。
- 涉及用户标识的接口，`phone_number` / `phone_num` 与 `email` **二选一**（同时传时优先手机号）。手机号写入 `phone_num`，邮箱写入 `email`。
- 注册必填 `password`，库中存哈希；手机号/邮箱登录需校验密码。仅微信 `openid` 登录可不传密码。
- `t_devices_users` 通过 `user_id` 关联用户，不再存储手机号。

**鉴权约定**：
- `/login`、`/register`、`/getopenid`、`/getPhoneNumber`、`/decode`、`/GetNewNotice` 无需 token。
- 其余接口需登录。请求头带 `Authorization: Bearer <token>`，或 Cookie `token`。
- 登录/注册成功返回 `token`（有效期 7 天）。登录成功即可，不要求管理员权限。
- 未登录或 token 无效返回 HTTP 401，`{"status": false, "error": "..."}`。

---

## 1. /hello
- **方法**: GET
- **描述**: 鉴权健康检查（需登录）
- **参数**: 无（依赖登录态）
- **返回**: 纯文本 `hello`

---

## 2. /login
- **方法**: POST
- **描述**: 用户登录，更新最近登录时间
- **参数** (json):
  - openid: 微信 openid（可空）
  - phone_number / phone_num **或** email：openid 为空时必填其一
  - password：手机号/邮箱登录时必填；仅 openid 登录时可空。写入库的是哈希，不是明文
- **返回**:
  - status: `true` / `false`
  - permission / phone_number / email / username / is_admin / user_id / token（成功时）
  - error（失败时，如用户未注册 / 未提供账号 / 密码错误）

---

## 3. /register
- **方法**: POST
- **描述**: 注册；若用户已存在且密码正确则返回用户信息与 token
- **参数** (json):
  - openid（可空）
  - username
  - phone_num **或** email（二选一，必填；分别写入对应字段）
  - password（必填）
  - company
  - industry
- **返回**: JSON 字符串
  - UserDetail: 用户信息（不含 password）
  - is_exist: `0` 新注册 / `1` 已存在
  - token: JWT
  - status / error（未提供手机号、邮箱或密码，或用户已存在但密码不正确）

---

## 4. /getopenid
- **方法**: GET
- **描述**: 用微信 `js_code` 换取 session（含 openid）
- **参数** (query):
  - js_code: 小程序登录 code
- **返回**: 微信接口原始响应（JSON 字符串）

---

## 5. /getPhoneNumber
- **方法**: GET
- **描述**: 用微信手机号授权 code 换取手机号
- **参数** (query):
  - code: 微信 getPhoneNumber 返回的 code
- **返回**:
  - status: `true` / `false`
  - phoneNumber（成功时）
  - error（失败时）

---

## 6. /decode
- **方法**: POST
- **描述**: 解密微信加密数据
- **参数** (json):
  - appId
  - sessionKey
  - encryptedData
  - iv
- **返回**: 解密后的 JSON 字符串

---

## 7. /getDevices
- **方法**: GET
- **描述**: 按账号查询已绑定/分享的设备列表
- **参数** (query):
  - openid（可空）
  - phone_number **或** email
- **返回**:
  - status: `true` / `false`
  - devices: 设备信息列表（无设备时为 `{}`）；含 name、use_count_month、serial_number、use_history、purview_number、is_shareable
  - error（未提供账号或用户不存在时）

---

## 8. /getPermission
- **方法**: GET
- **描述**: 查询用户权限配置
- **参数** (query):
  - phone_number **或** email
- **返回**:
  - status: `true` / `false`
  - permission（成功时；无权限配置时为 `{}`）
  - error（失败时）

---

## 9. /shareDevice
- **方法**: POST
- **描述**: 将设备分享给其他用户
- **参数** (json):
  - phone_number **或** email: 操作者账号
  - serial_number
  - number_shared: 被分享用户手机号或邮箱
  - email_shared（可选）: `number_shared` 的邮箱别名
  - uuid（可选）
- **返回**:
  - status: `true` / `false`
  - error（失败时：设备不存在 / 被分享用户不存在 / 已分享 / 超过上限 / 未提供账号）

---

## 10. /deleteSharedDevice
- **方法**: POST
- **描述**: 取消设备分享
- **参数** (json):
  - phone_number **或** email
  - serial_number
  - number_shared: 被分享用户手机号或邮箱
  - email_shared（可选）
  - uuid（可选）
- **返回**:
  - status: `true` / `false`
  - error（失败时）

---

## 11. /getSharedUser
- **方法**: POST
- **描述**: 查询设备已分享用户列表
- **参数** (json):
  - phone_number **或** email
  - serial_number
  - uuid（可选）
- **返回**:
  - status: `true` / `false`
  - shared_user: 被分享账号列表（手机号或邮箱，成功时）
  - error（失败时）

---

## 12. /getDeviceInfo
- **方法**: POST
- **描述**: 查询普通 NIR 设备状态与可用模型权限；管理员可自动注册未入库设备
- **参数** (json):
  - phone_number **或** email
  - serial_number
  - mac_NIR
  - device_name
  - is_qt（可选）: `true` 时按 uuid 查询
  - uuid（可选）
- **返回**:
  - status: `true` / `false`
  - device_status: `1` 可用 / `0` 未绑定 / `-1` 不可用
  - permission（可用时）
  - info（不可用或即将到期时的提示）
  - error（未知状态等）

---

## 13. /getIR2210DeviceInfo
- **方法**: POST
- **描述**: 查询 IR2210 设备状态与权限；管理员可自动注册
- **参数** (json):
  - phone_number **或** email
  - serial_number
  - device_name
- **返回**:
  - status: `true` / `false`
  - device_status: `1` / `0` / `-1`
  - permission（可用时）
  - should_init（管理员新建设备时为 `true`）
  - info / error

---

## 14. /bindDevice
- **方法**: POST
- **描述**: 绑定设备到当前用户（设为 owner）
- **参数** (json):
  - phone_number **或** email
  - serial_number
  - is_qt（可选）
  - uuid（可选）
- **返回**:
  - status: `true` / `false`
  - permission（成功时）
  - error（失败时：未注册 / 已被绑定）

---

## 15. /GetNewNotice
- **方法**: POST
- **描述**: 读取服务端公告文案（`notice_text.json`）
- **参数**: 无
- **返回**:
  - notice_title
  - newNotice
  - notice_text

---
