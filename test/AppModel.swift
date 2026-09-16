import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    var session: UserSession?
    var selectedProject: AppProject = .compositionAnalysis
    var homeRoute: HomeRoute = .projects
    var selectedDevice: NearbyDevice?
    var selectedIdentity: DeviceIdentity?
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

    @ObservationIgnored private let deviceAPI: DeviceAPIServicing
    @ObservationIgnored private let measurementService: MeasurementServicing
    @ObservationIgnored private let predictionService: PredictionServicing
    @ObservationIgnored private let sessionStore: SessionStoring

    convenience init() {
        let configuration = LegacyAPIConfiguration(baseURL: AppConfiguration.apiBaseURL)
        let bluetooth = BluetoothManager()
        self.init(
            bluetooth: bluetooth,
            deviceAPI: LegacyDeviceAPI(configuration: configuration),
            measurementService: bluetooth,
            predictionService: LivePredictionService(
                api: LegacyPredictionAPI(configuration: configuration, session: .shared),
                bluetooth: bluetooth
            ),
            sessionStore: KeychainSessionStore()
        )
    }

    init(
        bluetooth: BluetoothManager,
        deviceAPI: DeviceAPIServicing,
        measurementService: MeasurementServicing,
        predictionService: PredictionServicing,
        sessionStore: SessionStoring
    ) {
        self.bluetooth = bluetooth
        self.deviceAPI = deviceAPI
        self.measurementService = measurementService
        self.predictionService = predictionService
        self.sessionStore = sessionStore
        session = sessionStore.load()
        bluetooth.onHardwareScan = { [weak self] capture in
            Task { @MainActor [weak self] in
                await self?.receiveHardwareScan(capture)
            }
        }
        bluetooth.onHardwareScanError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, case .workbench = self.homeRoute else { return }
                self.errorMessage = error.localizedDescription
            }
        }
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
            adminLevel: 0,
            canViewSpectrum: false
        )
        self.session = session
        sessionStore.save(session)
    }

    func signOut() {
        bluetooth.disconnect()
        sessionStore.clear()
        session = nil
        homeRoute = .projects
        selectedDevice = nil
        selectedIdentity = nil
        selectedMode = nil
        captures = []
        predictionResult = nil
    }

    func chooseProject(_ project: AppProject) {
        guard project.isAvailable else { return }
        selectedProject = project
        homeRoute = .discovery
    }

    func prepare(_ device: NearbyDevice) async {
        guard let session else { return }
        await perform {
            try await bluetooth.connect(to: device)
            selectedDevice = device
            let identity = try await bluetooth.readIdentity(for: device)
            selectedIdentity = identity
            let inspection = try await deviceAPI.inspect(device, identity: identity, session: session)
            switch inspection.availability {
            case .available:
                availableModes = inspection.modes
                homeRoute = .modeSelection
            case .unbound:
                pendingBinding = true
            case let .blocked(message):
                throw AppServiceError.unavailable(message)
            }
        }
    }

    func bindSelectedDevice() async {
        guard let session, let selectedDevice, let selectedIdentity else { return }
        await perform {
            availableModes = try await deviceAPI.bind(
                selectedDevice,
                identity: selectedIdentity,
                session: session
            )
            pendingBinding = false
            homeRoute = .modeSelection
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
        guard let session, let selectedDevice, let selectedIdentity, let selectedMode else { return }
        guard scanMode == .single || captures.count < 9 else {
            errorMessage = "多次扫描最多保存 9 次"
            return
        }
        await perform {
            let capture = try await measurementService.scan(
                device: selectedDevice,
                calibration: calibrationMode
            )
            try await acceptCapture(
                capture,
                session: session,
                device: selectedDevice,
                identity: selectedIdentity,
                mode: selectedMode
            )
        }
    }

    func predictMultiple() async {
        guard scanMode == .multiple,
              let session,
              let selectedDevice,
              let selectedIdentity,
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
                identity: selectedIdentity,
                mode: selectedMode,
                calibration: calibrationMode,
                session: session
            )
        }
    }

    func runCalibration() async {
        guard let selectedDevice, let selectedIdentity else { return }
        await perform {
            let capture = try await measurementService.scan(
                device: selectedDevice,
                calibration: .manual
            )
            try await predictionService.setReference(
                capture: capture,
                device: selectedDevice,
                identity: selectedIdentity
            )
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
        homeRoute = .projects
        selectedDevice = nil
        selectedIdentity = nil
        selectedMode = nil
        availableModes = []
        pendingBinding = false
        captures = []
        predictionResult = nil
    }

    func returnToDiscovery() {
        bluetooth.disconnect()
        homeRoute = .discovery
        selectedDevice = nil
        selectedIdentity = nil
        selectedMode = nil
        availableModes = []
        pendingBinding = false
        clearMeasurements()
    }

    private func receiveHardwareScan(_ capture: ScanCapture) async {
        guard case .workbench = homeRoute,
              let session,
              let selectedDevice,
              let selectedIdentity,
              let selectedMode
        else { return }
        guard !isBusy else {
            errorMessage = "当前任务尚未完成，请稍后再按设备扫描键"
            return
        }
        guard scanMode == .single || captures.count < 9 else {
            errorMessage = "多次扫描最多保存 9 次"
            return
        }
        await perform {
            try await acceptCapture(
                capture,
                session: session,
                device: selectedDevice,
                identity: selectedIdentity,
                mode: selectedMode
            )
        }
    }

    private func acceptCapture(
        _ capture: ScanCapture,
        session: UserSession,
        device: NearbyDevice,
        identity: DeviceIdentity,
        mode: AnalysisMode
    ) async throws {
        if scanMode == .single {
            captures = [capture]
            predictionResult = try await predictionService.predict(
                captures: captures,
                device: device,
                identity: identity,
                mode: mode,
                calibration: calibrationMode,
                session: session
            )
        } else {
            captures.append(capture)
            predictionResult = nil
        }
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
