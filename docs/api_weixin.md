# Weixin 接口文档

## 账号与鉴权约定

**数据库**：账号资料在 `USER.t_users`（`user_tel`、`openid_gsm`、`company`、`email`、`password`、`user_name`、`last_login`、`days_online`）。克重仪小程序 openid 写入 `openid_gsm`。原表 `t_user` 只使用 `user_id`（与 `t_users.user_id` 相同）和 `is_admin`，不改这两个字段。

**请求账号字段**：`phone_number` / `phone_num` / `user_tel`（均写入 `user_tel`）与 `email` **二选一**，同时传时优先手机号。

**注册**：
- 可带 `password`：须验证码（`/getPhoneVC` 或 `/getEmailVC`）。
- 无 `password`：须同时提供 **手机号 + openid**（微信注册），不校验验证码。

**登录**：
- 手机号/邮箱登录须 `password`。
- 仅 `openid` 登录可不传 `password`。

**Token**（有效期 7 天）：
- 登录/注册成功返回 `token`。
- 其余接口请求头：`Authorization: Bearer <token>`，或 Cookie `token`。
- 未登录或无效：HTTP **401**，`{"status": false, "error": "..."}`。

**无需 token 的接口**：`/login`、`/register`、`/updatePassword`、`/getPhoneVC`、`/getEmailVC`、`/getopenid`、`/getPhoneNumber`。

---

## 1. /weixin/getPhoneNumber
- **方法**: GET
- **鉴权**: 否
- **描述**: 获取微信用户手机号（注册时调用）
- **参数**: code (query)
- **返回**: status, phoneNumber / error

---

## 2. /weixin/getopenid
- **方法**: GET
- **鉴权**: 否
- **描述**: 获取微信 openid
- **参数**: js_code (query)
- **返回**: status, openid / error

---

## 3. /weixin/getPhoneVC
- **方法**: POST
- **鉴权**: 否
- **描述**: 发送手机验证码
- **参数** (json): phone_number 或 phone_num
- **返回**: status / error

---

## 4. /weixin/getEmailVC
- **方法**: POST
- **鉴权**: 否
- **描述**: 发送邮箱验证码
- **参数** (json): email
- **返回**: status / error

---

## 5. /weixin/login
- **方法**: POST
- **鉴权**: 否
- **描述**: 用户登录
- **参数** (json):
  - openid（可选）
  - phone_number / phone_num / email（与 openid 至少一种）
  - password（手机号/邮箱登录必填；仅 openid 登录可不填）
- **返回** (成功): status, user_id, user_tel, email, user_name, company, is_admin, **token**

---

## 6. /weixin/register
- **方法**: POST
- **鉴权**: 否
- **描述**: 用户注册（已存在且密码正确时直接返回 token）
- **参数** (json):
  - openid（可选）
  - phone_number / phone_num / email（必填其一）
  - company（可选）
  - password（可选）
  - verification_code 或 code（有 password 时必填）
- **返回** (成功): 同 login，含 **token**

---

## 7. /weixin/updatePassword
- **方法**: POST
- **鉴权**: 否
- **描述**: 修改密码
- **参数** (json): phone_number/phone_num 或 email、password、verification_code/code
- **返回**: status / error

---

## 8. /weixin/getUrlLink
- **方法**: POST
- **鉴权**: 是
- **参数** (json): path
- **返回**: status, url_link / error

---

## 9. /weixin/getDevices
- **方法**: POST
- **鉴权**: 是
- **描述**: 当前登录用户绑定的设备列表（分页）
- **参数** (json): page, page_size（可选）
- **返回**: status, devices, total / error

---

## 10. /weixin/bindDevice
- **方法**: POST
- **鉴权**: 是
- **参数** (json): device_id
- **返回**: status, message / error

---

## 11. /weixin/shareDevice
- **方法**: POST
- **鉴权**: 是
- **参数** (json): device_id, share_tel / number_shared / email_shared（被分享用户）
- **返回**: status, message / error

---

## 12. /weixin/getSharedPhones
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id (query)
- **返回**: status, phones / error

---

## 13. /weixin/cancelShare
- **方法**: POST
- **鉴权**: 是
- **参数** (json): device_id, 被分享用户 phone_number/phone_num 或 email
- **返回**: status, message / error

---

## 14. /weixin/getHistory
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id, page, page_size (query)
- **返回**: status, datas, total / error

---

## 15. /weixin/modifyDeviceName
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id, new_name (query)
- **返回**: status, message / error

---

## 16. /weixin/getDeviceName
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id (query)
- **返回**: status, device_name / error

---

## 17. /weixin/getFavorite
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id, page, page_size (query)
- **返回**: status, datas, total / error

---

## 18. /weixin/addFavorite
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id, id (query)
- **返回**: status, message / error

---

## 19. /weixin/removeFavorite
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id, id (query)
- **返回**: status, message / error

---

## 20. /weixin/getBindStatus
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id (query)
- **返回**: status, bindings（user_tel 列表）/ error

---

## 21. /weixin/deleteBindStatus
- **方法**: GET
- **鉴权**: 是
- **参数**: device_id (query)
- **返回**: status, message / error

---

## 22. /weixin/addExtraData
- **方法**: POST
- **鉴权**: 是
- **参数** (json): id, extra_data
- **返回**: status, message / error

---

## 23. /weixin/getDataById
- **方法**: GET
- **鉴权**: 是
- **参数**: data_id (query)
- **返回**: status, data / error

---

## 24. /weixin/deleteData
- **方法**: POST
- **鉴权**: 是
- **参数** (json): device_id, data_ids（数组）
- **返回**: status, message / error

---

## 25. /weixin/uploadFindSupplier
- **方法**: POST
- **鉴权**: 是
- **参数** (json): data, images, contact_type, contact_value, contact_name
- **返回**: status, message, id / error

---

## 26. /weixin/getFindSupplierList
- **方法**: GET
- **鉴权**: 是
- **参数**: page, page_size, status (query)
- **返回**: status, total, page, page_size, list / error

---

## 27. /weixin/updateFindSupplierStatus
- **方法**: POST
- **鉴权**: 是
- **描述**: 更新处理状态。处理人取当前登录用户，并写入处理时间
- **参数** (json): id, status（0未处理，1已处理）
- **返回**: status, message, processor_id, processing_time / error

---
