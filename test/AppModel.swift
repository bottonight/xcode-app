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
    var busyTitle = "正在处理"
    var errorMessage: String?
    var noticeMessage: String?

    let bluetooth: BluetoothManager

    @ObservationIgnored private let deviceAPI: DeviceAPIServicing
    @ObservationIgnored private let authAPI: AuthServicing
    @ObservationIgnored private let measurementService: MeasurementServicing
    @ObservationIgnored private let predictionService: PredictionServicing
    @ObservationIgnored private let sessionStore: SessionStoring
    @ObservationIgnored private let authStore: APIAuthStore
    @ObservationIgnored private var hardwareScanPending = false

    convenience init() {
        let authStore = APIAuthStore()
        let sessionStore = KeychainSessionStore()
        authStore.token = sessionStore.load()?.authToken
        let configuration = LegacyAPIConfiguration(
            baseURL: AppConfiguration.apiBaseURL,
            authStore: authStore
        )
        let bluetooth = BluetoothManager()
        self.init(
            bluetooth: bluetooth,
            authAPI: LegacyAuthAPI(configuration: configuration),
            deviceAPI: LegacyDeviceAPI(configuration: configuration),
            measurementService: bluetooth,
            predictionService: LivePredictionService(
                api: LegacyPredictionAPI(configuration: configuration, session: .shared),
                bluetooth: bluetooth
            ),
            sessionStore: sessionStore,
            authStore: authStore
        )
    }

    init(
        bluetooth: BluetoothManager,
        authAPI: AuthServicing,
        deviceAPI: DeviceAPIServicing,
        measurementService: MeasurementServicing,
        predictionService: PredictionServicing,
        sessionStore: SessionStoring,
        authStore: APIAuthStore
    ) {
        self.bluetooth = bluetooth
        self.authAPI = authAPI
        self.deviceAPI = deviceAPI
        self.measurementService = measurementService
        self.predictionService = predictionService
        self.sessionStore = sessionStore
        self.authStore = authStore
        session = sessionStore.load()
        authStore.token = session?.authToken
        bluetooth.onHardwareScanStarted = { [weak self] in
            self?.beginHardwareScan()
        }
        bluetooth.onHardwareScanProcessing = { [weak self] in
            self?.markHardwareScanProcessing()
        }
        bluetooth.onHardwareScan = { [weak self] capture in
            Task { @MainActor [weak self] in
                await self?.receiveHardwareScan(capture)
            }
        }
        bluetooth.onHardwareScanError = { [weak self] error in
            self?.receiveHardwareScanError(error)
        }
    }

    var permissions: DevicePermissions {
        DevicePermissions(
            adminLevel: session?.adminLevel ?? 0,
            canViewSpectrum: session?.canViewSpectrum ?? false
        )
    }

    func login(account: String, password: String) async {
        await perform(title: "正在登录") {
            let identifier = try AccountIdentifier.parse(account, allowsPhone: AppRegion.isMainlandChina)
            try applyAuthenticatedSession(
                await authAPI.login(account: identifier, password: password)
            )
        }
    }

    func register(
        username: String,
        account: String,
        password: String,
        confirmPassword: String,
        company: String,
        industry: String
    ) async {
        await perform(title: "正在注册") {
            let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw AppServiceError.unavailable("请输入用户名")
            }
            guard password.count >= 6 else { throw AppServiceError.invalidPassword }
            guard password == confirmPassword else {
                throw AppServiceError.unavailable("两次输入的密码不一致")
            }
            let identifier = try AccountIdentifier.parse(account, allowsPhone: AppRegion.isMainlandChina)
            try applyAuthenticatedSession(
                await authAPI.register(
                    username: name,
                    account: identifier,
                    password: password,
                    company: company.trimmingCharacters(in: .whitespacesAndNewlines),
                    industry: industry
                )
            )
        }
    }

    private func applyAuthenticatedSession(_ session: UserSession) {
        self.session = session
        authStore.token = session.authToken
        sessionStore.save(session)
    }

    func signOut() {
        bluetooth.disconnect()
        sessionStore.clear()
        authStore.token = nil
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
                enterModes(inspection.modes)
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
            let modes = try await deviceAPI.bind(
                selectedDevice,
                identity: selectedIdentity,
                session: session
            )
            pendingBinding = false
            noticeMessage = "设备绑定成功"
            enterModes(modes)
        }
    }

    func chooseMode(_ mode: AnalysisMode) {
        selectedMode = mode
        captures = []
        predictionResult = nil
        homeRoute = .workbench
    }

    func leaveWorkbench() {
        if availableModes.count <= 1 {
            returnToDiscovery()
            return
        }
        selectedMode = nil
        clearMeasurements()
        homeRoute = .modeSelection
    }

    func runScan() async {
        guard let session, let selectedDevice, let selectedIdentity, let selectedMode else { return }
        guard scanMode == .single || captures.count < 9 else {
            errorMessage = "多次扫描最多保存 9 次"
            return
        }
        await perform(title: "扫描中，请勿移动设备") {
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
        await perform(title: "正在预测") {
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
        await perform(title: "扫描中，请勿移动设备") {
            let capture = try await measurementService.scan(
                device: selectedDevice,
                calibration: .manual
            )
            busyTitle = "正在处理"
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

    private func enterModes(_ modes: [AnalysisMode]) {
        availableModes = modes
        if let onlyMode = modes.first, modes.count == 1 {
            chooseMode(onlyMode)
        } else {
            selectedMode = nil
            homeRoute = .modeSelection
        }
    }

    private func beginHardwareScan() {
        guard case .workbench = homeRoute else { return }
        guard !isBusy else {
            errorMessage = "当前任务尚未完成，请稍后再按设备扫描键"
            return
        }
        guard scanMode == .single || captures.count < 9 else {
            errorMessage = "多次扫描最多保存 9 次"
            return
        }
        hardwareScanPending = true
        isBusy = true
        busyTitle = "扫描中，请勿移动设备"
        errorMessage = nil
    }

    private func markHardwareScanProcessing() {
        guard isBusy else { return }
        busyTitle = "处理数据中"
    }

    private func receiveHardwareScan(_ capture: ScanCapture) async {
        guard hardwareScanPending else { return }
        defer {
            hardwareScanPending = false
            isBusy = false
        }
        guard case .workbench = homeRoute,
              let session,
              let selectedDevice,
              let selectedIdentity,
              let selectedMode
        else { return }
        do {
            try await acceptCapture(
                capture,
                session: session,
                device: selectedDevice,
                identity: selectedIdentity,
                mode: selectedMode
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func receiveHardwareScanError(_ error: Error) {
        if hardwareScanPending {
            hardwareScanPending = false
            isBusy = false
        }
        if case .workbench = homeRoute {
            errorMessage = error.localizedDescription
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
            busyTitle = "正在预测"
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
    private func perform(
        title: String = "正在处理",
        _ operation: () async throws -> Void
    ) async -> Bool {
        isBusy = true
        busyTitle = title
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch AppServiceError.unauthorized {
            signOut()
            errorMessage = AppServiceError.unauthorized.localizedDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
