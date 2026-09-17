import Foundation

enum AppProject: String, CaseIterable, Identifiable {
    case compositionAnalysis
    case reservedTwo
    case reservedThree
    case reservedFour

    var id: String { rawValue }
    var isAvailable: Bool { self == .compositionAnalysis }

    var name: String {
        isAvailable ? "成分分析" : "敬请期待"
    }

    var systemImage: String {
        switch self {
        case .compositionAnalysis: "waveform.path.ecg"
        case .reservedTwo: "camera.macro"
        case .reservedThree: "chart.xyaxis.line"
        case .reservedFour: "square.grid.3x3"
        }
    }
}

enum DeviceKind: String, Codable, CaseIterable {
    case nir = "NIR"
    case ir2210 = "IR2210"

    static func identify(name: String) -> DeviceKind? {
        allCases.first { name.uppercased().hasPrefix($0.rawValue) }
    }
}

struct NearbyDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let kind: DeviceKind
    var rssi: Int

    var signalLevel: Int {
        if rssi >= -55 { return 3 }
        if rssi >= -70 { return 2 }
        return 1
    }
}

struct DeviceIdentity: Equatable {
    let name: String
    let serialNumber: String
    let macNIR: String?
    let uuid: String?
}

enum DeviceAvailability: Equatable {
    case available
    case unbound
    case blocked(String)
}

struct DeviceInspection {
    let availability: DeviceAvailability
    let modes: [AnalysisMode]
    let shouldInitialize: Bool
}

struct UserSession: Codable, Equatable {
    let userID: String
    let phoneNumber: String
    let email: String
    let username: String
    let authToken: String
    let adminLevel: Int
    let canViewSpectrum: Bool

    var displayAccount: String {
        phoneNumber.isEmpty ? email : phoneNumber
    }

    var requestPhoneNumber: String? {
        phoneNumber.isEmpty ? nil : phoneNumber
    }

    var requestEmail: String? {
        requestPhoneNumber == nil && !email.isEmpty ? email : nil
    }

    var accountQueryItem: URLQueryItem {
        if let phone = requestPhoneNumber {
            return URLQueryItem(name: "phone_number", value: phone)
        }
        return URLQueryItem(name: "email", value: email)
    }

    enum CodingKeys: String, CodingKey {
        case userID, phoneNumber, email, username, authToken, adminLevel, canViewSpectrum
    }

    init(
        userID: String,
        phoneNumber: String,
        email: String,
        username: String,
        authToken: String,
        adminLevel: Int,
        canViewSpectrum: Bool
    ) {
        self.userID = userID
        self.phoneNumber = phoneNumber
        self.email = email
        self.username = username
        self.authToken = authToken
        self.adminLevel = adminLevel
        self.canViewSpectrum = canViewSpectrum
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userID = try values.decode(String.self, forKey: .userID)
        phoneNumber = try values.decode(String.self, forKey: .phoneNumber)
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        username = try values.decode(String.self, forKey: .username)
        authToken = try values.decode(String.self, forKey: .authToken)
        adminLevel = try values.decode(Int.self, forKey: .adminLevel)
        canViewSpectrum = try values.decode(Bool.self, forKey: .canViewSpectrum)
    }
}

enum AccountIdentifier: Equatable {
    case phone(String)
    case email(String)

    var phoneNumber: String? {
        if case let .phone(value) = self { return value }
        return nil
    }

    var email: String? {
        if case let .email(value) = self { return value }
        return nil
    }

    var value: String {
        switch self {
        case let .phone(value), let .email(value): value
        }
    }

    static func parse(_ raw: String, allowsPhone: Bool) throws -> AccountIdentifier {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("@") {
            guard value.contains("."), value.count >= 5 else {
                throw AppServiceError.invalidEmail
            }
            return .email(value.lowercased())
        }
        guard allowsPhone else { throw AppServiceError.invalidEmail }
        let digits = value.filter(\.isNumber)
        guard digits.count == 11, digits.hasPrefix("1") else {
            throw AppServiceError.invalidPhone
        }
        return .phone(digits)
    }
}

enum AppRegion {
    static var isMainlandChina: Bool {
        Locale.current.region?.identifier.uppercased() == "CN"
    }
}

struct AnalysisMode: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let monthlyUseCount: Int
}

enum ScanMode: String, CaseIterable, Identifiable {
    case single = "单次扫描"
    case multiple = "多次扫描"

    var id: String { rawValue }
}

enum CalibrationMode: String, CaseIterable, Identifiable {
    case builtIn = "默认校准"
    case manual = "手动校准"

    var id: String { rawValue }
}

struct SpectrumPoint: Identifiable, Hashable {
    let index: Int
    let intensity: Double
    var id: Int { index }
}

enum ScanCaptureData {
    case nir([Int])
    case ir2210([Double])
}

struct ScanCapture: Identifiable {
    let id: UUID
    let capturedAt: Date
    let data: ScanCaptureData
    let preview: [SpectrumPoint]
}

struct MeasurementResult: Identifiable {
    let id: UUID
    let measuredAt: Date
    let summary: String
    let spectrum: [SpectrumPoint]
}

struct DevicePermissions: Equatable {
    let adminLevel: Int
    let canViewSpectrum: Bool

    var canSaveSpectrum: Bool { adminLevel >= 1 }
    var canConfigureDevice: Bool { adminLevel >= 2 }
}

struct ManagedDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let serialNumber: String
    let monthlyUseCount: Int
    let usageHistory: [String: Int]
    let isShareable: Bool
}

struct SharedUser: Identifiable, Hashable {
    let phoneNumber: String
    var id: String { phoneNumber }
}

enum HomeRoute {
    case projects
    case discovery
    case modeSelection
    case workbench
}
