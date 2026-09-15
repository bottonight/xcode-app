import Foundation

enum PredictionAPIError: LocalizedError {
    case invalidCapture(String)
    case invalidBuiltin
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .invalidCapture(message): message
        case .invalidBuiltin: "内置参考必须包含 228 个强度和 228 个波长"
        case .invalidResponse: "服务器返回了无法识别的数据"
        case let .server(message): message
        }
    }
}

struct DeviceIdentity {
    let name: String
    let serialNumber: String
    let macNIR: String?
    let uuid: String?
}

struct PredictionResponse: Decodable {
    let result: String?
    let preID: String?
    let status: Bool
    let error: String?
    let modelName: String?
    let useCountMonth: Int?
    let plotA: String?
    let plotR: String?

    enum CodingKeys: String, CodingKey {
        case result, status, error
        case preID = "pre_id"
        case modelName = "model_name"
        case useCountMonth = "use_count_month"
        case plotA = "plot_a"
        case plotR = "plot_r"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        result = try values.decodeIfPresent(String.self, forKey: .result)
        status = try values.decode(Bool.self, forKey: .status)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        modelName = try values.decodeIfPresent(String.self, forKey: .modelName)
        useCountMonth = try values.decodeIfPresent(Int.self, forKey: .useCountMonth)
        plotA = try values.decodeIfPresent(String.self, forKey: .plotA)
        plotR = try values.decodeIfPresent(String.self, forKey: .plotR)
        if let value = try? values.decode(String.self, forKey: .preID) {
            preID = value
        } else if let value = try? values.decode(Int.self, forKey: .preID) {
            preID = String(value)
        } else {
            preID = nil
        }
    }
}

struct SaveWaveResponse: Decodable {
    let status: APIStatus
    let error: String?
    let saved: Int?
    let savedError: Int?

    enum CodingKeys: String, CodingKey {
        case status, error, saved
        case savedError = "saved_error"
    }
}

enum APIStatus: Decodable {
    case success
    case failure

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let bool = try? value.decode(Bool.self) {
            self = bool ? .success : .failure
        } else if let text = try? value.decode(String.self) {
            self = ["succeed", "success", "true"].contains(text.lowercased()) ? .success : .failure
        } else {
            self = .failure
        }
    }
}

enum IRIntensityPayload: Encodable {
    case single([Double])
    case multiple([[Double]])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .single(values): try container.encode(values)
        case let .multiple(values): try container.encode(values)
        }
    }
}

enum NIRWavePayload: Encodable {
    case single([Int])
    case multiple([[Int]])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .single(values): try container.encode(values)
        case let .multiple(values): try container.encode(values)
        }
    }
}

enum IRWavePayload: Encodable {
    case single([Double])
    case multiple([[Double]])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .single(values): try container.encode(values)
        case let .multiple(values): try container.encode(values)
        }
    }
}

private struct NIRPredictionRequest: Encodable {
    let data: [Int]
    let macNIR: String?
    let modelName: String
    let isBuiltin: Bool
    let builtin: NIRBuiltinReference?
    let openid: String
    let phoneNumber: String
    let serialNumber: String
    let viewSpectrum: Bool
    let uuid: String?

    enum CodingKeys: String, CodingKey {
        case data, builtin, openid, uuid
        case macNIR = "mac_NIR"
        case modelName = "model_name"
        case isBuiltin = "is_builtin"
        case phoneNumber = "phone_number"
        case serialNumber = "serial_number"
        case viewSpectrum = "view_spectrum"
    }
}

private struct IRPredictionRequest: Encodable {
    let intensity: IRIntensityPayload
    let serialNumber: String
    let modelName: String
    let openid: String
    let phoneNumber: String
    let isDefaultReference: Bool
    let isAdapter: Bool

    enum CodingKeys: String, CodingKey {
        case intensity, openid
        case serialNumber = "serial_number"
        case modelName = "model_name"
        case phoneNumber = "phone_number"
        case isDefaultReference = "is_default_ref"
        case isAdapter = "is_adapter"
    }
}

private struct SaveNIRWaveRequest: Encodable {
    let serialNumber: String
    let deviceName: String
    let wave: NIRWavePayload
    let openid: String
    let phoneNumber: String
    let isDefaultReference: Bool
    let predictedComponents: String?
    let taggedComponents: String?
    let fabricID: String?
    let remark: String?
    let batteryPercent: Int?
    let integrationTime: Int?
    let image: String?

    enum CodingKeys: String, CodingKey {
        case wave, openid, remark, image
        case serialNumber = "serial_number"
        case deviceName = "device_name"
        case phoneNumber = "phone_number"
        case isDefaultReference = "is_default_ref"
        case predictedComponents = "components_pre"
        case taggedComponents = "components_tag"
        case fabricID = "fabric_id"
        case batteryPercent = "battery_percent"
        case integrationTime = "integration_time_us"
    }
}

private struct SaveIRWaveRequest: Encodable {
    let serialNumber: String
    let deviceName: String
    let wave: IRWavePayload
    let openid: String
    let phoneNumber: String
    let isDefaultReference: Bool
    let predictedComponents: String?
    let taggedComponents: String?
    let fabricID: String?
    let remark: String?
    let batteryPercent: Int?
    let integrationTime: Int?
    let image: String?

    enum CodingKeys: String, CodingKey {
        case wave, openid, remark, image
        case serialNumber = "serial_number"
        case deviceName = "device_name"
        case phoneNumber = "phone_number"
        case isDefaultReference = "is_default_ref"
        case predictedComponents = "components_pre"
        case taggedComponents = "components_tag"
        case fabricID = "fabric_id"
        case batteryPercent = "battery_percent"
        case integrationTime = "integration_time_us"
    }
}

@MainActor
final class LegacyPredictionAPI {
    private let configuration: LegacyAPIConfiguration
    private let session: URLSession

    init(
        configuration: LegacyAPIConfiguration = LegacyAPIConfiguration(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func predictNIR(
        captures: [ScanCapture],
        identity: DeviceIdentity,
        mode: AnalysisMode,
        builtin: NIRBuiltinReference?,
        account: String
    ) async throws -> PredictionResponse {
        if let builtin, !builtin.isValid { throw PredictionAPIError.invalidBuiltin }
        let scans = try Self.nirScans(from: captures)
        let request = NIRPredictionRequest(
            data: scans.flatMap { $0 },
            macNIR: identity.macNIR,
            modelName: mode.id,
            isBuiltin: builtin != nil,
            builtin: builtin,
            openid: "",
            phoneNumber: account,
            serialNumber: identity.serialNumber,
            viewSpectrum: mode.supportsSpectrum,
            uuid: identity.uuid
        )
        return try await post("/apps/PredictionPage/Prediction", body: request)
    }

    func predictIR2210(
        captures: [ScanCapture],
        identity: DeviceIdentity,
        mode: AnalysisMode,
        useDefaultReference: Bool,
        useAdapter: Bool,
        account: String
    ) async throws -> PredictionResponse {
        let scans = try Self.irScans(from: captures)
        let payload: IRIntensityPayload = scans.count == 1 ? .single(scans[0]) : .multiple(scans)
        let request = IRPredictionRequest(
            intensity: payload,
            serialNumber: identity.serialNumber,
            modelName: mode.id,
            openid: "",
            phoneNumber: account,
            isDefaultReference: useDefaultReference,
            isAdapter: useAdapter
        )
        return try await post("/apps/PredictionPage/IR2210Prediction", body: request)
    }

    func saveNIR(
        captures: [ScanCapture],
        identity: DeviceIdentity,
        account: String,
        useDefaultReference: Bool,
        result: String?,
        tag: String? = nil,
        fabricID: String? = nil,
        remark: String? = nil,
        battery: Int? = nil,
        integrationTime: Int? = nil,
        image: String? = nil
    ) async throws -> SaveWaveResponse {
        let scans = try Self.nirScans(from: captures)
        let wave: NIRWavePayload = scans.count == 1 ? .single(scans[0]) : .multiple(scans)
        let request = SaveNIRWaveRequest(
            serialNumber: identity.serialNumber,
            deviceName: identity.name,
            wave: wave,
            openid: "",
            phoneNumber: account,
            isDefaultReference: useDefaultReference,
            predictedComponents: result,
            taggedComponents: tag,
            fabricID: fabricID,
            remark: remark,
            batteryPercent: battery,
            integrationTime: integrationTime,
            image: image
        )
        return try await post("/apps/PredictionPage/SaveWaveTI", body: request)
    }

    func saveIR2210(
        captures: [ScanCapture],
        identity: DeviceIdentity,
        account: String,
        useDefaultReference: Bool,
        result: String?,
        tag: String? = nil,
        fabricID: String? = nil,
        remark: String? = nil,
        battery: Int? = nil,
        integrationTime: Int? = nil,
        image: String? = nil
    ) async throws -> SaveWaveResponse {
        let scans = try Self.irScans(from: captures)
        let wave: IRWavePayload = scans.count == 1 ? .single(scans[0]) : .multiple(scans)
        let request = SaveIRWaveRequest(
            serialNumber: identity.serialNumber,
            deviceName: identity.name,
            wave: wave,
            openid: "",
            phoneNumber: account,
            isDefaultReference: useDefaultReference,
            predictedComponents: result,
            taggedComponents: tag,
            fabricID: fabricID,
            remark: remark,
            batteryPercent: battery,
            integrationTime: integrationTime,
            image: image
        )
        return try await post("/apps/PredictionPage/SaveWaveOP", body: request)
    }

    private func post<Response: Decodable, Body: Encodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode
        else {
            throw PredictionAPIError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw PredictionAPIError.invalidResponse
        }
    }

    private static func nirScans(from captures: [ScanCapture]) throws -> [[Int]] {
        guard !captures.isEmpty else {
            throw PredictionAPIError.invalidCapture("请先采集 NIR 光谱")
        }
        return try captures.map { capture in
            guard case let .nir(values) = capture.data, values.count == 3822 else {
                throw PredictionAPIError.invalidCapture("每次 NIR 扫描必须包含 3822 个字节")
            }
            guard values.allSatisfy({ 0 ... 255 ~= $0 }) else {
                throw PredictionAPIError.invalidCapture("NIR 扫描数据必须是 0–255 的整数")
            }
            return values
        }
    }

    private static func irScans(from captures: [ScanCapture]) throws -> [[Double]] {
        guard !captures.isEmpty else {
            throw PredictionAPIError.invalidCapture("请先采集 IR2210 光谱")
        }
        return try captures.map { capture in
            guard case let .ir2210(values) = capture.data, values.count == 256 else {
                throw PredictionAPIError.invalidCapture("每次 IR2210 扫描必须包含 256 个强度值")
            }
            return values
        }
    }
}

@MainActor
final class LivePredictionService: PredictionServicing {
    private let api: LegacyPredictionAPI
    private let identityProvider: (NearbyDevice) -> DeviceIdentity?
    private let builtinProvider: (NearbyDevice) -> NIRBuiltinReference?

    init(
        api: LegacyPredictionAPI = LegacyPredictionAPI(),
        identityProvider: @escaping (NearbyDevice) -> DeviceIdentity?,
        builtinProvider: @escaping (NearbyDevice) -> NIRBuiltinReference? = { _ in nil }
    ) {
        self.api = api
        self.identityProvider = identityProvider
        self.builtinProvider = builtinProvider
    }

    func predict(
        captures: [ScanCapture],
        device: NearbyDevice,
        mode: AnalysisMode,
        calibration: CalibrationMode,
        session: UserSession
    ) async throws -> MeasurementResult {
        guard let identity = identityProvider(device) else {
            throw PredictionAPIError.invalidCapture("尚未读取到设备序列号")
        }

        let response: PredictionResponse
        switch device.kind {
        case .nir:
            let builtin = builtinProvider(device)
            if calibration == .builtIn, builtin == nil {
                throw PredictionAPIError.invalidBuiltin
            }
            response = try await api.predictNIR(
                captures: captures,
                identity: identity,
                mode: mode,
                builtin: calibration == .builtIn ? builtin : nil,
                account: session.phoneNumber
            )
        case .ir2210:
            response = try await api.predictIR2210(
                captures: captures,
                identity: identity,
                mode: mode,
                useDefaultReference: calibration == .builtIn,
                useAdapter: false,
                account: session.phoneNumber
            )
        }

        guard response.status, let result = response.result else {
            throw PredictionAPIError.server(response.error ?? "预测失败")
        }

        return MeasurementResult(
            id: UUID(),
            measuredAt: Date(),
            summary: result,
            spectrum: Self.averagePreview(captures)
        )
    }

    private static func averagePreview(_ captures: [ScanCapture]) -> [SpectrumPoint] {
        let pointCount = captures.map(\.preview.count).min() ?? 0
        guard pointCount > 0 else { return [] }
        return (0 ..< pointCount).map { index in
            let value = captures.reduce(0.0) { $0 + $1.preview[index].intensity }
                / Double(captures.count)
            return SpectrumPoint(index: index, intensity: value)
        }
    }
}
