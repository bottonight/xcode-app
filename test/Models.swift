import Foundation

enum AppProject: String, CaseIterable, Identifiable {
    case nearInfrared = "近红外检测"
    case reserved = "更多项目"

    var id: String { rawValue }
    var isAvailable: Bool { self == .nearInfrared }
    var subtitle: String {
        switch self {
        case .nearInfrared: "NIR 与 IR2210 光谱分析"
        case .reserved: "已预留项目接入能力"
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

enum DeviceAvailability: Equatable {
    case available
    case unbound
    case blocked(String)
}

struct UserSession: Codable, Equatable {
    let userID: String
    let phoneNumber: String
    let username: String
    let authToken: String
    let adminLevel: Int
    let canViewSpectrum: Bool
}

struct AnalysisMode: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let monthlyUseCount: Int

    var supportsSpectrum: Bool { id == "LINE" }
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

struct NIRBuiltinReference: Codable, Equatable {
    let i: [Double]
    let w: [Double]

    var isValid: Bool {
        i.count == 228 && w.count == 228
            && i.allSatisfy(\.isFinite)
            && w.allSatisfy(\.isFinite)
    }
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
    case discovery
    case modeSelection
    case workbench
}
