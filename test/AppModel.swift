import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    var session: UserSession?
    var selectedProject: AppProject = .nearInfrared
    var isProjectSwitcherPresented = false
    var homeRoute: HomeRoute = .discovery
    var selectedDevice: NearbyDevice?
    var selectedMode: AnalysisMode?
    var availableModes: [AnalysisMode] = []
    var pendingBinding = false
    var scanMode: ScanMode = .single
    var calibrationMode: CalibrationMode = .builtIn
    var captures: [ScanCapture] = []
    var predictionResult: MeasurementResult?
    var managedDevices: [ManagedDevice] = []
    var isBusy = false
    var errorMessage: String?
    var noticeMessage: String?

    let bluetooth: BluetoothManager

    @ObservationIgnored private let authService: AuthServicing
    @ObservationIgnored private let deviceAPI: DeviceAPIServicing
    @ObservationIgnored private let measurementService: MeasurementServicing
    @ObservationIgnored private let predictionService: PredictionServicing
    @ObservationIgnored private let sessionStore: SessionStoring

    convenience init() {
        self.init(
            bluetooth: BluetoothManager(),
            authService: MockAuthService(),
            deviceAPI: MockDeviceAPI(),
            measurementService: MockMeasurementService(),
            predictionService: MockPredictionService(),
            sessionStore: KeychainSessionStore()
        )
    }

    init(
        bluetooth: BluetoothManager,
        authService: AuthServicing,
        deviceAPI: DeviceAPIServicing,
        measurementService: MeasurementServicing,
        predictionService: PredictionServicing,
        sessionStore: SessionStoring
    ) {
        self.bluetooth = bluetooth
        self.authService = authService
        self.deviceAPI = deviceAPI
        self.measurementService = measurementService
        self.predictionService = predictionService
        self.sessionStore = sessionStore
        session = sessionStore.load()
    }

    var permissions: DevicePermissions {
        DevicePermissions(
            adminLevel: session?.adminLevel ?? 0,
            canViewSpectrum: session?.canViewSpectrum ?? false
        )
    }

    func startValidationSession(phoneNumber: String, username: String) {
        let phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let validationPhone = phoneNumber.isEmpty ? "13800000000" : phoneNumber
        let validationName = username.isEmpty ? "测试用户" : username
        let session = UserSession(
            userID: "validation-\(validationPhone)",
            phoneNumber: validationPhone,
            username: validationName,
            authToken: "validation-only",
            adminLevel: 2,
            canViewSpectrum: true
        )
        self.session = session
        sessionStore.save(session)
    }

    func sendCode(to phoneNumber: String) async -> Bool {
        await perform {
            try await authService.sendVerificationCode(to: phoneNumber)
            noticeMessage = "验证码已发送；Mock 环境可输入任意 6 位数字"
        }
    }

    func register(phoneNumber: String, username: String, code: String) async -> Bool {
        await perform {
            let session = try await authService.register(
                phoneNumber: phoneNumber,
                username: username,
                code: code
            )
            self.session = session
            sessionStore.save(session)
        }
    }

    func signOut() {
        bluetooth.disconnect()
        sessionStore.clear()
        session = nil
        homeRoute = .discovery
        selectedDevice = nil
        selectedMode = nil
        captures = []
        predictionResult = nil
    }

    func chooseProject(_ project: AppProject) {
        guard project.isAvailable else { return }
        selectedProject = project
        isProjectSwitcherPresented = false
        resetHome()
    }

    func prepare(_ device: NearbyDevice) async {
        guard let session else { return }
        await perform {
            try await bluetooth.connect(to: device)
            selectedDevice = device
            let availability = try await deviceAPI.availability(of: device, for: session)
            switch availability {
            case .available:
                try await loadModes(for: device, session: session)
            case .unbound:
                pendingBinding = true
            case let .blocked(message):
                throw AppServiceError.unavailable(message)
            }
        }
    }

    func bindSelectedDevice() async {
        guard let session, let selectedDevice else { return }
        await perform {
            try await deviceAPI.bind(selectedDevice, for: session)
            pendingBinding = false
            try await loadModes(for: selectedDevice, session: session)
            noticeMessage = "设备绑定成功"
        }
    }

    func chooseMode(_ mode: AnalysisMode) {
        selectedMode = mode
        captures = []
        predictionResult = nil
        homeRoute = .workbench
    }

    func runScan() async {
        guard let session, let selectedDevice, let selectedMode else { return }
        guard scanMode == .single || captures.count < 9 else {
            errorMessage = "多次扫描最多保存 9 次"
            return
        }
        await perform {
            let capture = try await measurementService.scan(
                device: selectedDevice,
                calibration: calibrationMode
            )
            if scanMode == .single {
                captures = [capture]
                predictionResult = try await predictionService.predict(
                    captures: captures,
                    device: selectedDevice,
                    mode: selectedMode,
                    calibration: calibrationMode,
                    session: session
                )
            } else {
                captures.append(capture)
                predictionResult = nil
            }
        }
    }

    func predictMultiple() async {
        guard scanMode == .multiple,
              let session,
              let selectedDevice,
              let selectedMode,
              captures.count >= 2
        else {
            errorMessage = "多次预测至少需要完成 2 次扫描"
            return
        }
        await perform {
            predictionResult = try await predictionService.predict(
                captures: captures,
                device: selectedDevice,
                mode: selectedMode,
                calibration: calibrationMode,
                session: session
            )
        }
    }

    func runCalibration() async {
        guard let selectedDevice else { return }
        await perform {
            try await measurementService.calibrate(device: selectedDevice)
            clearMeasurements()
            noticeMessage = "手动校准完成"
        }
    }

    func clearMeasurements() {
        captures = []
        predictionResult = nil
    }

    func loadManagedDevices() async {
        guard let session else { return }
        await perform {
            managedDevices = try await deviceAPI.managedDevices(for: session)
        }
    }

    func sharedUsers(for device: ManagedDevice) async throws -> [SharedUser] {
        guard let session else { return [] }
        return try await deviceAPI.sharedUsers(for: device, session: session)
    }

    func share(_ device: ManagedDevice, phoneNumber: String) async -> Bool {
        guard let session else { return false }
        return await perform {
            try await deviceAPI.share(device, with: phoneNumber, session: session)
            noticeMessage = "设备已分享"
        }
    }

    func revoke(_ device: ManagedDevice, phoneNumber: String) async -> Bool {
        guard let session else { return false }
        return await perform {
            try await deviceAPI.revoke(device, from: phoneNumber, session: session)
        }
    }

    func resetHome() {
        bluetooth.disconnect()
        homeRoute = .discovery
        selectedDevice = nil
        selectedMode = nil
        availableModes = []
        pendingBinding = false
        captures = []
        predictionResult = nil
    }

    private func loadModes(for device: NearbyDevice, session: UserSession) async throws {
        availableModes = try await deviceAPI.modes(for: device, session: session)
        homeRoute = .modeSelection
    }

    @discardableResult
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
