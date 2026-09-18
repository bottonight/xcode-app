import Foundation
import Security

enum AppServiceError: LocalizedError {
    case invalidPhone
    case invalidEmail
    case invalidPassword
    case unauthorized
    case invalidCode
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidPhone: L10n.t("error.invalid_phone")
        case .invalidEmail: L10n.t("error.invalid_email")
        case .invalidPassword: L10n.t("error.invalid_password")
        case .unauthorized: L10n.t("error.unauthorized")
        case .invalidCode: L10n.t("error.invalid_code")
        case let .unavailable(message): message
        }
    }
}

@MainActor
protocol AuthServicing {
    func login(account: AccountIdentifier, password: String) async throws -> UserSession
    func sendVerificationCode(account: AccountIdentifier) async throws
    func register(
        username: String,
        account: AccountIdentifier,
        password: String,
        verificationCode: String,
        company: String,
        industry: String
    ) async throws -> UserSession
}

@MainActor
final class APIAuthStore {
    var token: String?
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
    func setReference(
        capture: ScanCapture,
        device: NearbyDevice,
        identity: DeviceIdentity
    ) async throws
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
    let authStore: APIAuthStore

    init(baseURL: URL, authStore: APIAuthStore) {
        self.baseURL = baseURL
        self.authStore = authStore
    }
}

extension URLRequest {
    mutating func applyAPIHeaders(token: String? = nil) {
        setValue(L10n.language.rawValue, forHTTPHeaderField: "Accept-Language")
        if let token, !token.isEmpty {
            setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
