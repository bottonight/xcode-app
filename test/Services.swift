import Foundation
import Security

enum AppServiceError: LocalizedError {
    case invalidPhone
    case invalidCode
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidPhone: "请输入正确的手机号"
        case .invalidCode: "请输入 6 位验证码"
        case let .unavailable(message): message
        }
    }
}

@MainActor
protocol DeviceAPIServicing {
    func inspect(
        _ device: NearbyDevice,
        identity: DeviceIdentity,
        session: UserSession
    ) async throws -> DeviceInspection
    func bind(
        _ device: NearbyDevice,
        identity: DeviceIdentity,
        session: UserSession
    ) async throws -> [AnalysisMode]
    func managedDevices(for session: UserSession) async throws -> [ManagedDevice]
    func sharedUsers(for device: ManagedDevice, session: UserSession) async throws -> [SharedUser]
    func share(_ device: ManagedDevice, with phoneNumber: String, session: UserSession) async throws
    func revoke(_ device: ManagedDevice, from phoneNumber: String, session: UserSession) async throws
}

@MainActor
protocol MeasurementServicing {
    func scan(device: NearbyDevice, calibration: CalibrationMode) async throws -> ScanCapture
    func calibrate(device: NearbyDevice) async throws
}

@MainActor
protocol PredictionServicing {
    func predict(
        captures: [ScanCapture],
        device: NearbyDevice,
        identity: DeviceIdentity,
        mode: AnalysisMode,
        calibration: CalibrationMode,
        session: UserSession
    ) async throws -> MeasurementResult
}

protocol SessionStoring {
    func load() -> UserSession?
    func save(_ session: UserSession)
    func clear()
}

struct KeychainSessionStore: SessionStoring {
    private let service = "com.fabriceyes.fabriclab"
    private let account = "user-session"

    func load() -> UserSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    func save(_ session: UserSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct LegacyAPIConfiguration {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }
}
