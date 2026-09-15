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
protocol AuthServicing {
    func sendVerificationCode(to phoneNumber: String) async throws
    func register(phoneNumber: String, username: String, code: String) async throws -> UserSession
}

@MainActor
protocol DeviceAPIServicing {
    func availability(of device: NearbyDevice, for session: UserSession) async throws -> DeviceAvailability
    func bind(_ device: NearbyDevice, for session: UserSession) async throws
    func modes(for device: NearbyDevice, session: UserSession) async throws -> [AnalysisMode]
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

@MainActor
final class MockAuthService: AuthServicing {
    func sendVerificationCode(to phoneNumber: String) async throws {
        guard phoneNumber.count == 11 else { throw AppServiceError.invalidPhone }
        try await Task.sleep(nanoseconds: 450_000_000)
    }

    func register(phoneNumber: String, username: String, code: String) async throws -> UserSession {
        guard phoneNumber.count == 11 else { throw AppServiceError.invalidPhone }
        guard code.count == 6 else { throw AppServiceError.invalidCode }
        try await Task.sleep(nanoseconds: 650_000_000)
        return UserSession(
            userID: UUID().uuidString,
            phoneNumber: phoneNumber,
            username: username,
            authToken: "mock-token",
            adminLevel: 2,
            canViewSpectrum: true
        )
    }
}

@MainActor
final class MockDeviceAPI: DeviceAPIServicing {
    private var shared: [String: [SharedUser]] = [
        "NIR-20260901": [SharedUser(phoneNumber: "138****8000")]
    ]

    func availability(of device: NearbyDevice, for session: UserSession) async throws -> DeviceAvailability {
        try await Task.sleep(nanoseconds: 500_000_000)
        if device.name.contains("LOCKED") {
            return .blocked("设备已停用，请联系管理员")
        }
        return device.name.contains("NEW") ? .unbound : .available
    }

    func bind(_ device: NearbyDevice, for session: UserSession) async throws {
        try await Task.sleep(nanoseconds: 450_000_000)
    }

    func modes(for device: NearbyDevice, session: UserSession) async throws -> [AnalysisMode] {
        try await Task.sleep(nanoseconds: 350_000_000)
        return [
            AnalysisMode(id: "JYS", name: "成分分析", monthlyUseCount: 18),
            AnalysisMode(id: "LINE", name: "谱线查看", monthlyUseCount: 6)
        ]
    }

    func managedDevices(for session: UserSession) async throws -> [ManagedDevice] {
        try await Task.sleep(nanoseconds: 420_000_000)
        return [
            ManagedDevice(
                id: "NIR-20260901",
                name: "NIR Mini",
                serialNumber: "NIR-20260901",
                monthlyUseCount: 27,
                usageHistory: ["2026-07": 22, "2026-08": 31, "2026-09": 27],
                isShareable: true
            ),
            ManagedDevice(
                id: "IR2210-0088",
                name: "IR2210",
                serialNumber: "IR2210-0088",
                monthlyUseCount: 12,
                usageHistory: ["2026-08": 8, "2026-09": 12],
                isShareable: true
            )
        ]
    }

    func sharedUsers(for device: ManagedDevice, session: UserSession) async throws -> [SharedUser] {
        shared[device.id, default: []]
    }

    func share(_ device: ManagedDevice, with phoneNumber: String, session: UserSession) async throws {
        guard phoneNumber.count == 11 else { throw AppServiceError.invalidPhone }
        var users = shared[device.id, default: []]
        guard !users.contains(where: { $0.phoneNumber == phoneNumber }) else { return }
        users.append(SharedUser(phoneNumber: phoneNumber))
        shared[device.id] = users
    }

    func revoke(_ device: ManagedDevice, from phoneNumber: String, session: UserSession) async throws {
        shared[device.id]?.removeAll { $0.phoneNumber == phoneNumber }
    }
}

@MainActor
final class MockMeasurementService: MeasurementServicing {
    func scan(device: NearbyDevice, calibration: CalibrationMode) async throws -> ScanCapture {
        try await Task.sleep(nanoseconds: 900_000_000)
        let phase = Double.random(in: 0 ... .pi)
        let previewCount = device.kind == .nir ? 228 : 256
        let preview = (0 ..< previewCount).map { index in
            let x = Double(index) / Double(previewCount)
            let signal = 0.54 + sin(x * 10 + phase) * 0.16 + cos(x * 31) * 0.035
            return SpectrumPoint(index: index, intensity: signal)
        }

        let data: ScanCaptureData
        switch device.kind {
        case .nir:
            data = .nir((0 ..< 3822).map { index in
                Int((sin(Double(index) / 80 + phase) + 1) * 110).clamped(to: 0 ... 255)
            })
        case .ir2210:
            data = .ir2210((0 ..< 256).map { index in
                1_200 + sin(Double(index) / 18 + phase) * 220
            })
        }

        return ScanCapture(
            id: UUID(),
            capturedAt: Date(),
            data: data,
            preview: preview
        )
    }

    func calibrate(device: NearbyDevice) async throws {
        try await Task.sleep(nanoseconds: 1_200_000_000)
    }
}

@MainActor
final class MockPredictionService: PredictionServicing {
    func predict(
        captures: [ScanCapture],
        device: NearbyDevice,
        mode: AnalysisMode,
        calibration: CalibrationMode,
        session: UserSession
    ) async throws -> MeasurementResult {
        guard let first = captures.first else {
            throw AppServiceError.unavailable("请先完成扫描")
        }
        try await Task.sleep(nanoseconds: 650_000_000)
        let pointCount = captures.map(\.preview.count).min() ?? 0
        let averaged = (0 ..< pointCount).map { index in
            let value = captures.reduce(0.0) { $0 + $1.preview[index].intensity }
                / Double(captures.count)
            return SpectrumPoint(index: index, intensity: value)
        }
        return MeasurementResult(
            id: UUID(),
            measuredAt: Date(),
            summary: "棉 68.4% · 聚酯纤维 31.6%",
            spectrum: averaged.isEmpty ? first.preview : averaged
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

struct LegacyAPIConfiguration {
    static let productionBaseURL = URL(string: "https://wx.nir.fabriceyes.com.cn:50002")!

    let baseURL: URL

    init(baseURL: URL = productionBaseURL) {
        self.baseURL = baseURL
    }
}
