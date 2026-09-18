# LoginPage 接口文档

用户登录、设备绑定与权限相关接口。Blueprint 前缀：`/apps/LoginPage`。

完整路径示例：`/apps/LoginPage/login`

**账号约定**：
- `t_users` 主键为自增 `user_id`；`openid` 可为空。
- 涉及用户标识的接口，`phone_number` / `phone_num` 与 `email` **二选一**（同时传时优先手机号）。手机号写入 `phone_num`，邮箱写入 `email`。
- 注册必填 `password` 和验证码；库中存密码哈希。有手机号则校验短信验证码，否则校验邮箱验证码。手机号/邮箱登录需校验密码。仅微信 `openid` 登录可不传密码。
- `t_devices_users` 通过 `user_id` 关联用户，不再存储手机号。

**鉴权约定**：
- `/login`、`/register`、`/getPhoneVC`、`/getEmailVC`、`/getopenid`、`/getPhoneNumber`、`/decode`、`/GetNewNotice` 无需 token。
- 其余接口需登录。请求头带 `Authorization: Bearer <token>`，或 Cookie `token`。
- 登录/注册成功返回 `token`（有效期 7 天）。登录成功即可，不要求管理员权限。
- 未登录或 token 无效返回 HTTP 401，`{"status": false, "error": "..."}`。

**语言约定**：
- 请求头带 `Accept-Language: zh-Hans` 或 `en`。`error` / `info` 等提示按该语言返回。
- 未传或无法识别时默认简体中文（`zh-Hans`）。`zh` / `zh-CN` 视为中文，`en-US` 等视为英文。

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
- **描述**: 注册；服务端校验短信/邮箱验证码通过后才建号。若用户已存在且密码正确则返回用户信息与 token
- **参数** (json):
  - openid（可空）
  - username
  - phone_num **或** email（二选一，必填；分别写入对应字段）
  - password（必填）
  - verification_code / code（必填；有手机号则校验短信验证码，否则校验邮箱验证码）
  - company
  - industry
- **返回**: JSON 字符串
  - UserDetail: 用户信息（不含 password）
  - is_exist: `0` 新注册 / `1` 已存在
  - token: JWT
  - status / error（未提供手机号、邮箱、密码或验证码，验证码错误/过期，或用户已存在但密码不正确）

---

## 4. /getPhoneVC
- **方法**: POST
- **描述**: 向手机号发送短信验证码（有效期 5 分钟，60 秒内不可重复发送）。校验在 `/register` 中完成，不单独暴露校验接口
- **参数** (json):
  - phone_number / phone_num（必填）
- **返回**:
  - status: `true` / `false`
  - error（失败时，如未提供手机号 / 发送失败 / 发送过于频繁）

---

## 5. /getEmailVC
- **方法**: POST
- **描述**: 向邮箱发送验证码（有效期 5 分钟，60 秒内不可重复发送）。校验在 `/register` 中完成，不单独暴露校验接口
- **参数** (json):
  - email（必填）
- **返回**:
  - status: `true` / `false`
  - error（失败时，如未提供邮箱 / 发送失败 / 发送过于频繁）

---

## 6. /getopenid
- **方法**: GET
- **描述**: 用微信 `js_code` 换取 session（含 openid）
- **参数** (query):
  - js_code: 小程序登录 code
- **返回**: 微信接口原始响应（JSON 字符串）

---

## 7. /getPhoneNumber
- **方法**: GET
- **描述**: 用微信手机号授权 code 换取手机号
- **参数** (query):
  - code: 微信 getPhoneNumber 返回的 code
- **返回**:
  - status: `true` / `false`
  - phoneNumber（成功时）
  - error（失败时）

---

## 8. /decode
- **方法**: POST
- **描述**: 解密微信加密数据
- **参数** (json):
  - appId
  - sessionKey
  - encryptedData
  - iv
- **返回**: 解密后的 JSON 字符串

---

## 9. /getDevices
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

## 10. /getPermission
- **方法**: GET
- **描述**: 查询用户权限配置
- **参数** (query):
  - phone_number **或** email
- **返回**:
  - status: `true` / `false`
  - permission（成功时；无权限配置时为 `{}`）
  - error（失败时）

---

## 11. /shareDevice
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

## 12. /deleteSharedDevice
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

## 13. /getSharedUser
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

## 14. /getDeviceInfo
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

## 15. /getIR2210DeviceInfo
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

## 16. /bindDevice
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

## 17. /GetNewNotice
- **方法**: POST
- **描述**: 读取服务端公告文案（`notice_text.json`）
- **参数**: 无
- **返回**:
  - notice_title
  - newNotice
  - notice_text

---
