import Foundation

private struct LoginRequest: Encodable {
    let openid: String
    let password: String
    let phoneNumber: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case openid, email, password
        case phoneNumber = "phone_number"
        case phoneNum = "phone_num"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(openid, forKey: .openid)
        try container.encode(password, forKey: .password)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNum)
        try container.encodeIfPresent(email, forKey: .email)
    }
}

private struct RegisterRequest: Encodable {
    let openid: String
    let username: String
    let password: String
    let company: String
    let industry: String
    let phoneNumber: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case openid, username, password, company, industry, email
        case phoneNumber = "phone_num"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(openid, forKey: .openid)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(company, forKey: .company)
        try container.encode(industry, forKey: .industry)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(email, forKey: .email)
    }
}

private struct AuthUserDetail: Decodable {
    let userID: FlexibleID?
    let username: String?
    let phoneNumber: String?
    let email: String?
    let isAdmin: FlexibleInt?

    enum CodingKeys: String, CodingKey {
        case username, email
        case userID = "user_id"
        case phoneNumber = "phone_num"
        case phoneNumberAlt = "phone_number"
        case isAdmin = "is_admin"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userID = try values.decodeIfPresent(FlexibleID.self, forKey: .userID)
        username = try values.decodeIfPresent(String.self, forKey: .username)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        isAdmin = try values.decodeIfPresent(FlexibleInt.self, forKey: .isAdmin)
        phoneNumber = try values.decodeIfPresent(String.self, forKey: .phoneNumber)
            ?? values.decodeIfPresent(String.self, forKey: .phoneNumberAlt)
    }
}

private struct LoginResponse: Decodable {
    let status: Bool?
    let error: String?
    let token: String?
    let username: String?
    let phoneNumber: String?
    let email: String?
    let userID: FlexibleID?
    let isAdmin: FlexibleInt?
    let userDetail: AuthUserDetail?

    enum CodingKeys: String, CodingKey {
        case status, error, token, username, email
        case phoneNumber = "phone_number"
        case userID = "user_id"
        case isAdmin = "is_admin"
        case userDetail = "UserDetail"
    }
}

private struct RegisterResponse: Decodable {
    let status: Bool?
    let error: String?
    let token: String?
    let userDetail: AuthUserDetail?

    enum CodingKeys: String, CodingKey {
        case status, error, token
        case userDetail = "UserDetail"
    }
}

private struct FlexibleID: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = String(value)
        } else {
            self.value = ""
        }
    }
}

private struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(Bool.self) {
            self.value = value ? 1 : 0
        } else if let value = try? container.decode(String.self), let number = Int(value) {
            self.value = number
        } else {
            self.value = 0
        }
    }
}

@MainActor
final class LegacyAuthAPI: AuthServicing {
    private let configuration: LegacyAPIConfiguration
    private let urlSession: URLSession

    init(
        configuration: LegacyAPIConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func login(account: AccountIdentifier, password: String) async throws -> UserSession {
        let response: LoginResponse = try await post(
            "/apps/LoginPage/login",
            body: LoginRequest(
                openid: "",
                password: password,
                phoneNumber: account.phoneNumber,
                email: account.email
            )
        )
        guard response.status != false else {
            throw AppServiceError.unavailable(response.error ?? "登录失败")
        }
        return try Self.session(
            token: response.token,
            userID: response.userID?.value ?? response.userDetail?.userID?.value,
            username: response.username ?? response.userDetail?.username,
            phoneNumber: response.phoneNumber ?? response.userDetail?.phoneNumber,
            email: response.email ?? response.userDetail?.email,
            adminLevel: response.isAdmin?.value ?? response.userDetail?.isAdmin?.value,
            fallback: account
        )
    }

    func register(
        username: String,
        account: AccountIdentifier,
        password: String,
        company: String,
        industry: String
    ) async throws -> UserSession {
        let response: RegisterResponse = try await post(
            "/apps/LoginPage/register",
            body: RegisterRequest(
                openid: "",
                username: username,
                password: password,
                company: company,
                industry: industry,
                phoneNumber: account.phoneNumber,
                email: account.email
            ),
            unwrapJSONString: true
        )
        guard response.status != false else {
            throw AppServiceError.unavailable(response.error ?? "注册失败")
        }
        return try Self.session(
            token: response.token,
            userID: response.userDetail?.userID?.value,
            username: response.userDetail?.username ?? username,
            phoneNumber: response.userDetail?.phoneNumber,
            email: response.userDetail?.email,
            adminLevel: response.userDetail?.isAdmin?.value,
            fallback: account
        )
    }

    private func post<Response: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        unwrapJSONString: Bool = false
    ) async throws -> Response {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppServiceError.unavailable("服务器响应无效")
        }
        guard 200 ..< 300 ~= http.statusCode else {
            throw AppServiceError.unavailable("接口请求失败（HTTP \(http.statusCode)）")
        }

        let payload = unwrapJSONString ? Self.unwrapJSONString(data) : data
        do {
            return try JSONDecoder().decode(Response.self, from: payload)
        } catch {
            throw AppServiceError.unavailable("服务器返回数据格式不正确")
        }
    }

    private static func unwrapJSONString(_ data: Data) -> Data {
        if let text = try? JSONDecoder().decode(String.self, from: data),
           let inner = text.data(using: .utf8) {
            return inner
        }
        return data
    }

    private static func session(
        token: String?,
        userID: String?,
        username: String?,
        phoneNumber: String?,
        email: String?,
        adminLevel: Int?,
        fallback: AccountIdentifier
    ) throws -> UserSession {
        guard let token, !token.isEmpty else {
            throw AppServiceError.unavailable("登录成功但未返回 token")
        }
        return UserSession(
            userID: userID.flatMap { $0.isEmpty ? nil : $0 } ?? fallback.value,
            phoneNumber: phoneNumber ?? fallback.phoneNumber ?? "",
            email: email ?? fallback.email ?? "",
            username: username.flatMap { $0.isEmpty ? nil : $0 } ?? "用户",
            authToken: token,
            adminLevel: adminLevel ?? 0,
            canViewSpectrum: false
        )
    }
}
