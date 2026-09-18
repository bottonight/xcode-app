import Foundation

private struct DevicePermissionDTO: Decodable {
    let name: String
    let modelName: String
    let useCountMonth: Int

    enum CodingKeys: String, CodingKey {
        case name
        case modelName = "model_name"
        case useCountMonth = "use_count_month"
    }

    var mode: AnalysisMode {
        AnalysisMode(id: modelName, name: name, monthlyUseCount: useCountMonth)
    }
}

private struct DeviceInfoResponse: Decodable {
    let status: Bool
    let deviceStatus: Int?
    let permission: [DevicePermissionDTO]?
    let shouldInitialize: Bool?
    let info: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, permission, info, error
        case deviceStatus = "device_status"
        case shouldInitialize = "should_init"
    }
}

private struct BindResponse: Decodable {
    let status: Bool
    let permission: [DevicePermissionDTO]?
    let error: String?
}

private struct ManagedDeviceDTO: Decodable {
    let name: String?
    let serialNumber: String
    let useCountMonth: Int?
    let useHistory: [String: Int]?
    let isShareable: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case serialNumber = "serial_number"
        case useCountMonth = "use_count_month"
        case useHistory = "use_history"
        case isShareable = "is_shareable"
    }

    var model: ManagedDevice {
        ManagedDevice(
            id: serialNumber,
            name: name ?? serialNumber,
            serialNumber: serialNumber,
            monthlyUseCount: useCountMonth ?? 0,
            usageHistory: useHistory ?? [:],
            isShareable: isShareable ?? false
        )
    }
}

private struct DeviceListResponse: Decodable {
    let status: Bool
    let devices: [ManagedDeviceDTO]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, devices, error
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decode(Bool.self, forKey: .status)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        devices = (try? values.decode([ManagedDeviceDTO].self, forKey: .devices)) ?? []
    }
}

private struct SharedUsersResponse: Decodable {
    let status: Bool
    let sharedUser: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, error
        case sharedUser = "shared_user"
    }
}

private struct StatusResponse: Decodable {
    let status: Bool
    let error: String?
}

private struct NIRDeviceInfoRequest: Encodable {
    let phoneNumber: String?
    let email: String?
    let serialNumber: String
    let macNIR: String?
    let deviceName: String
    let uuid: String?

    enum CodingKeys: String, CodingKey {
        case uuid, email
        case phoneNumber = "phone_number"
        case serialNumber = "serial_number"
        case macNIR = "mac_NIR"
        case deviceName = "device_name"
    }

    init(session: UserSession, identity: DeviceIdentity) {
        phoneNumber = session.requestPhoneNumber
        email = session.requestEmail
        serialNumber = identity.serialNumber
        macNIR = identity.macNIR
        deviceName = identity.name
        uuid = identity.uuid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encodeIfPresent(macNIR, forKey: .macNIR)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encodeIfPresent(uuid, forKey: .uuid)
    }
}

private struct IRDeviceInfoRequest: Encodable {
    let phoneNumber: String?
    let email: String?
    let serialNumber: String
    let deviceName: String

    enum CodingKeys: String, CodingKey {
        case email
        case phoneNumber = "phone_number"
        case serialNumber = "serial_number"
        case deviceName = "device_name"
    }

    init(session: UserSession, identity: DeviceIdentity) {
        phoneNumber = session.requestPhoneNumber
        email = session.requestEmail
        serialNumber = identity.serialNumber
        deviceName = identity.name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encode(deviceName, forKey: .deviceName)
    }
}

private struct BindDeviceRequest: Encodable {
    let phoneNumber: String?
    let email: String?
    let serialNumber: String
    let uuid: String?

    enum CodingKeys: String, CodingKey {
        case uuid, email
        case phoneNumber = "phone_number"
        case serialNumber = "serial_number"
    }

    init(session: UserSession, identity: DeviceIdentity) {
        phoneNumber = session.requestPhoneNumber
        email = session.requestEmail
        serialNumber = identity.serialNumber
        uuid = identity.uuid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encodeIfPresent(uuid, forKey: .uuid)
    }
}

private struct SharedDeviceRequest: Encodable {
    let phoneNumber: String?
    let email: String?
    let serialNumber: String
    let sharedPhoneNumber: String?
    let uuid: String?

    enum CodingKeys: String, CodingKey {
        case uuid, email
        case phoneNumber = "phone_number"
        case serialNumber = "serial_number"
        case sharedPhoneNumber = "number_shared"
    }

    init(session: UserSession, device: ManagedDevice, sharedPhoneNumber: String?, uuid: String?) {
        phoneNumber = session.requestPhoneNumber
        email = session.requestEmail
        serialNumber = device.serialNumber
        self.sharedPhoneNumber = sharedPhoneNumber
        self.uuid = uuid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encodeIfPresent(sharedPhoneNumber, forKey: .sharedPhoneNumber)
        try container.encodeIfPresent(uuid, forKey: .uuid)
    }
}

@MainActor
final class LegacyDeviceAPI: DeviceAPIServicing {
    private let configuration: LegacyAPIConfiguration
    private let urlSession: URLSession

    init(
        configuration: LegacyAPIConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func inspect(
        _ device: NearbyDevice,
        identity: DeviceIdentity,
        session: UserSession
    ) async throws -> DeviceInspection {
        let response: DeviceInfoResponse
        switch device.kind {
        case .nir:
            response = try await post(
                "/apps/LoginPage/getDeviceInfo",
                body: NIRDeviceInfoRequest(session: session, identity: identity)
            )
        case .ir2210:
            response = try await post(
                "/apps/LoginPage/getIR2210DeviceInfo",
                body: IRDeviceInfoRequest(session: session, identity: identity)
            )
        }

        guard response.status else {
            throw AppServiceError.unavailable(response.error ?? L10n.t("error.device_info"))
        }

        let availability: DeviceAvailability
        switch response.deviceStatus {
        case 1: availability = .available
        case 0: availability = .unbound
        default: availability = .blocked(response.info ?? response.error ?? L10n.t("error.device_unavailable"))
        }
        return DeviceInspection(
            availability: availability,
            modes: Self.modes(from: response.permission),
            shouldInitialize: response.shouldInitialize ?? false
        )
    }

    func bind(
        _ device: NearbyDevice,
        identity: DeviceIdentity,
        session: UserSession
    ) async throws -> [AnalysisMode] {
        let response: BindResponse = try await post(
            "/apps/LoginPage/bindDevice",
            body: BindDeviceRequest(session: session, identity: identity)
        )
        guard response.status else {
            throw AppServiceError.unavailable(response.error ?? L10n.t("error.bind_failed"))
        }
        return Self.modes(from: response.permission)
    }

    func managedDevices(for session: UserSession) async throws -> [ManagedDevice] {
        let response: DeviceListResponse = try await get(
            "/apps/LoginPage/getDevices",
            query: [session.accountQueryItem]
        )
        guard response.status else {
            throw AppServiceError.unavailable(response.error ?? L10n.t("error.device_list"))
        }
        return response.devices.map(\.model)
    }

    func sharedUsers(for device: ManagedDevice, session: UserSession) async throws -> [SharedUser] {
        let response: SharedUsersResponse = try await post(
            "/apps/LoginPage/getSharedUser",
            body: SharedDeviceRequest(
                session: session,
                device: device,
                sharedPhoneNumber: nil,
                uuid: nil
            )
        )
        guard response.status else {
            throw AppServiceError.unavailable(response.error ?? L10n.t("error.shared_users"))
        }
        return (response.sharedUser ?? []).map(SharedUser.init(phoneNumber:))
    }

    func share(_ device: ManagedDevice, with phoneNumber: String, session: UserSession) async throws {
        let response: StatusResponse = try await post(
            "/apps/LoginPage/shareDevice",
            body: SharedDeviceRequest(
                session: session,
                device: device,
                sharedPhoneNumber: phoneNumber,
                uuid: nil
            )
        )
        guard response.status else {
            throw AppServiceError.unavailable(response.error ?? L10n.t("error.share_failed"))
        }
    }

    func revoke(_ device: ManagedDevice, from phoneNumber: String, session: UserSession) async throws {
        let response: StatusResponse = try await post(
            "/apps/LoginPage/deleteSharedDevice",
            body: SharedDeviceRequest(
                session: session,
                device: device,
                sharedPhoneNumber: phoneNumber,
                uuid: nil
            )
        )
        guard response.status else {
            throw AppServiceError.unavailable(response.error ?? L10n.t("error.revoke_failed"))
        }
    }

    private static func modes(from permission: [DevicePermissionDTO]?) -> [AnalysisMode] {
        (permission ?? [])
            .map(\.mode)
            .filter { $0.id != "LINE" && $0.id != "REPORT" }
    }

    private func post<Response: Decodable, Body: Encodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyAPIHeaders(token: configuration.authStore.token)
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func get<Response: Decodable>(
        _ path: String,
        query: [URLQueryItem]
    ) async throws -> Response {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
        guard let url = components?.url else {
            throw AppServiceError.unavailable(L10n.t("error.invalid_url"))
        }
        var request = URLRequest(url: url)
        request.applyAPIHeaders(token: configuration.authStore.token)
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppServiceError.unavailable(L10n.t("error.invalid_response"))
            }
            if http.statusCode == 401 {
                throw AppServiceError.unauthorized
            }
            guard 200 ..< 300 ~= http.statusCode else {
                let message = http.statusCode >= 500
                    ? L10n.t("error.http_500", http.statusCode)
                    : L10n.t("error.http", http.statusCode)
                throw AppServiceError.unavailable(message)
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as AppServiceError {
            throw error
        } catch let error as DecodingError {
            throw AppServiceError.unavailable(L10n.t("error.decode_detail", error.localizedDescription))
        } catch {
            throw AppServiceError.unavailable(L10n.t("error.connect", error.localizedDescription))
        }
    }
}
