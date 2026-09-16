import SwiftUI

struct HomeFlowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                switch app.homeRoute {
                case .projects:
                    ProjectGridView()
                case .discovery:
                    DeviceDiscoveryView()
                case .modeSelection:
                    ModeSelectionView()
                case .workbench:
                    MeasurementWorkbenchView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    switch app.homeRoute {
                    case .projects:
                        EmptyView()
                    case .discovery:
                        Button {
                            app.resetHome()
                        } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                    case .modeSelection:
                        Button {
                            app.returnToDiscovery()
                        } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                    case .workbench:
                        Button {
                            app.homeRoute = .modeSelection
                        } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                    }
                }
            }
        }
    }
}

struct ProjectGridView: View {
    @Environment(AppModel.self) private var app
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            FabricTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppProject.allCases) { project in
                        Button {
                            app.chooseProject(project)
                        } label: {
                            VStack(spacing: 14) {
                                Image(systemName: project.systemImage)
                                    .font(.system(size: 34, weight: .medium))
                                    .foregroundStyle(project.isAvailable ? FabricTheme.indigo : .secondary)
                                Text(project.name)
                                    .font(.headline)
                                    .foregroundStyle(project.isAvailable ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 142)
                            .brandCard()
                        }
                        .buttonStyle(.plain)
                        .disabled(!project.isAvailable)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("首页")
    }
}

struct DeviceDiscoveryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            FabricTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                bluetoothBanner
                if app.bluetooth.nearbyDevices.isEmpty {
                    ContentUnavailableView {
                        Label("附近没有设备", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("请打开 NIR 或 IR2210 设备并保持在附近")
                    } actions: {
                        Button("重新扫描") { app.bluetooth.startScanning() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(app.bluetooth.nearbyDevices) { device in
                        Button {
                            Task { await app.prepare(device) }
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        app.bluetooth.startScanning()
                    }
                }
            }
        }
        .navigationTitle("发现设备")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.bluetooth.isScanning
                        ? app.bluetooth.stopScanning()
                        : app.bluetooth.startScanning()
                } label: {
                    Image(systemName: app.bluetooth.isScanning ? "stop.circle" : "arrow.clockwise")
                }
                .disabled(app.bluetooth.status != .ready)
            }
        }
        .onAppear {
            if app.bluetooth.status == .ready && app.bluetooth.nearbyDevices.isEmpty {
                app.bluetooth.startScanning()
            }
        }
        .confirmationDialog(
            "绑定这台设备？",
            isPresented: Binding(
                get: { app.pendingBinding },
                set: { app.pendingBinding = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("绑定并继续") {
                Task { await app.bindSelectedDevice() }
            }
            Button("取消", role: .cancel) {
                app.bluetooth.disconnect()
                app.selectedDevice = nil
            }
        } message: {
            Text("设备尚未激活，将绑定到当前手机号。")
        }
    }

    private var bluetoothBanner: some View {
        HStack {
            Image(systemName: app.bluetooth.status == .ready ? "bluetooth" : "exclamationmark.triangle")
            Text(app.bluetooth.isScanning ? "正在扫描附近设备…" : app.bluetooth.status.message)
            Spacer()
            if app.bluetooth.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.subheadline)
        .foregroundStyle(app.bluetooth.status == .ready ? FabricTheme.indigo : .orange)
        .padding()
    }
}

private struct DeviceRow: View {
    let device: NearbyDevice

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(FabricTheme.indigo.opacity(0.1))
                    .frame(width: 52, height: 52)
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .foregroundStyle(FabricTheme.indigo)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text(device.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SignalIndicator(level: device.signalLevel)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}

struct ModeSelectionView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            FabricTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let device = app.selectedDevice {
                        Label(device.name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(FabricTheme.cyan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .brandCard()
                    }

                    ForEach(app.availableModes) { mode in
                        Button {
                            app.chooseMode(mode)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: icon(for: mode))
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(FabricTheme.indigo.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(mode.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("本月已使用 \(mode.monthlyUseCount) 次")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .brandCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("选择分析模式")
    }

    private func icon(for mode: AnalysisMode) -> String {
        return "sparkles"
    }
}

struct MeasurementWorkbenchView: View {
    @Environment(AppModel.self) private var app
    @State private var showsDeviceSettings = false

    private var latestResult: MeasurementResult? { app.predictionResult }

    var body: some View {
        ZStack {
            FabricTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 16) {
                    deviceHeader
                    controls
                    scanPanel
                    if let latestResult {
                        resultCard(latestResult)
                    }
                    permissionActions
                }
                .padding()
            }
        }
        .navigationTitle(app.selectedMode?.name ?? "检测")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsDeviceSettings) {
            DeviceSettingsView()
        }
    }

    private var deviceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(app.selectedDevice?.name ?? "未连接设备")
                    .font(.headline)
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            Text(app.selectedDevice?.kind.rawValue ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .brandCard()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("检测设置")
                .font(.headline)
            Picker("扫描方式", selection: Binding(
                get: { app.scanMode },
                set: {
                    app.scanMode = $0
                    app.clearMeasurements()
                }
            )) {
                ForEach(ScanMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("校准方式", selection: Binding(
                get: { app.calibrationMode },
                set: {
                    app.calibrationMode = $0
                    app.clearMeasurements()
                }
            )) {
                ForEach(CalibrationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if app.calibrationMode == .manual {
                Button {
                    Task { await app.runCalibration() }
                } label: {
                    Label("开始手动校准", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .brandCard()
    }

    private var scanPanel: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(FabricTheme.indigo.opacity(0.12), lineWidth: 14)
                    .frame(width: 138, height: 138)
                Circle()
                    .fill(FabricTheme.indigo.gradient)
                    .frame(width: 108, height: 108)
                Image(systemName: app.isBusy ? "waveform" : "viewfinder")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            if app.scanMode == .multiple {
                Text("已采集 \(app.captures.count) / 9 次")
                    .font(.headline.monospacedDigit())
            } else {
                Text("将完成扫描并立即预测")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await app.runScan() }
            } label: {
                Text(app.isBusy ? "正在采集…" : "开始扫描")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(FabricTheme.indigo)
            .disabled(app.isBusy || (app.scanMode == .multiple && app.captures.count >= 9))

            if app.scanMode == .multiple && !app.captures.isEmpty {
                Button {
                    Task { await app.predictMultiple() }
                } label: {
                    Label("对 \(app.captures.count) 次采集进行预测", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(app.captures.count < 2 || app.isBusy)

                Button("清空已采集数据", role: .destructive) {
                    app.clearMeasurements()
                }
            }
        }
        .brandCard()
    }

    private func resultCard(_ result: MeasurementResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("分析结果", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(FabricTheme.cyan)
                Spacer()
                Text(result.measuredAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(result.summary)
                .font(.title3.bold())
            if app.scanMode == .multiple {
                Text("结果基于 \(app.captures.count) 次采集")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard()
    }

    @ViewBuilder
    private var permissionActions: some View {
        if app.permissions.canSaveSpectrum
            || app.permissions.canConfigureDevice {
            VStack(alignment: .leading, spacing: 12) {
                Text("更多操作")
                    .font(.headline)
                if app.permissions.canSaveSpectrum {
                    Button("保存谱线与多点数据", systemImage: "square.and.arrow.down") {
                        app.noticeMessage = "保存功能将在真实预测接口接入后启用"
                    }
                }
                if app.selectedDevice?.kind == .ir2210,
                   app.permissions.canConfigureDevice {
                    Button("IR2210 设备配置", systemImage: "slider.horizontal.3") {
                        showsDeviceSettings = true
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandCard()
        }
    }
}

private struct DeviceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var integrationTime = 10.0
    @State private var instantLight = true
    @State private var averageEnabled = false
    @State private var averageCount = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("采集参数") {
                    LabeledContent("积分时间", value: "\(Int(integrationTime)) ms")
                    Slider(value: $integrationTime, in: 1 ... 50, step: 1)
                    Toggle("即测即亮", isOn: $instantLight)
                    Toggle("多次均值", isOn: $averageEnabled)
                    Stepper("均值次数：\(averageCount)", value: $averageCount, in: 2 ... 10)
                        .disabled(!averageEnabled)
                }
                Section("校准") {
                    Button("TI 默认参考") {}
                    Button("奥普默认参考") {}
                    Button("暗电流校准") {}
                }
                Section {
                    Button("保存配置") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("设备配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
