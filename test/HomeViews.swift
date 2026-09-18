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
                            Label(app.t("common.back"), systemImage: "chevron.left")
                        }
                    case .modeSelection:
                        Button {
                            app.returnToDiscovery()
                        } label: {
                            Label(app.t("common.back"), systemImage: "chevron.left")
                        }
                    case .workbench:
                        Button {
                            app.leaveWorkbench()
                        } label: {
                            Label(app.t("common.back"), systemImage: "chevron.left")
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
                                Text(app.t(project.titleKey))
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
        .navigationTitle(app.t("project.home"))
    }
}

struct DeviceDiscoveryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            FabricTheme.background.ignoresSafeArea()
            List {
                bluetoothBanner
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if app.bluetooth.nearbyDevices.isEmpty {
                    ContentUnavailableView {
                        Label(app.t("discovery.empty"), systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text(app.t("discovery.empty_hint"))
                    } actions: {
                        Button(app.t("discovery.rescan")) { app.bluetooth.startScanning() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(app.bluetooth.nearbyDevices) { device in
                        Button {
                            Task { await app.prepare(device) }
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                app.bluetooth.startScanning()
            }
        }
        .navigationTitle(app.t("discovery.title"))
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
            app.t("discovery.bind_title"),
            isPresented: Binding(
                get: { app.pendingBinding },
                set: { app.pendingBinding = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button(app.t("discovery.bind_continue")) {
                Task { await app.bindSelectedDevice() }
            }
            Button(app.t("common.cancel"), role: .cancel) {
                app.bluetooth.disconnect()
                app.selectedDevice = nil
            }
        } message: {
            Text(app.t("discovery.bind_message"))
        }
    }

    private var bluetoothBanner: some View {
        HStack {
            Image(systemName: app.bluetooth.status == .ready ? "bluetooth" : "exclamationmark.triangle")
            Text(bluetoothStatusText)
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

    private var bluetoothStatusText: String {
        if app.bluetooth.isScanning {
            return app.t("discovery.scanning")
        }
        switch app.bluetooth.status {
        case .unknown: return app.t("bt.checking")
        case .ready: return app.t("bt.ready")
        case .poweredOff: return app.t("bt.off")
        case .unauthorized: return app.t("bt.unauthorized")
        case .unsupported: return app.t("bt.unsupported")
        case let .unavailable(message): return message
        }
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
                                    Text(app.t("mode.monthly_use", mode.monthlyUseCount))
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
        .navigationTitle(app.t("mode.title"))
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
        .navigationTitle(app.selectedMode?.name ?? app.t("workbench.inspect"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsDeviceSettings) {
            DeviceSettingsView()
        }
    }

    private var deviceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(app.selectedDevice?.name ?? app.t("workbench.disconnected"))
                    .font(.headline)
                Label(app.t("workbench.connected"), systemImage: "checkmark.circle.fill")
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
            Text(app.t("workbench.settings"))
                .font(.headline)
            Picker(app.t("workbench.scan_mode"), selection: Binding(
                get: { app.scanMode },
                set: {
                    app.scanMode = $0
                    app.clearMeasurements()
                }
            )) {
                ForEach(ScanMode.allCases) { mode in
                    Text(app.t(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker(app.t("workbench.calibration"), selection: Binding(
                get: { app.calibrationMode },
                set: {
                    app.calibrationMode = $0
                    app.clearMeasurements()
                }
            )) {
                ForEach(CalibrationMode.allCases) { mode in
                    Text(app.t(mode.titleKey)).tag(mode)
                }
            }

            if app.calibrationMode == .manual {
                Button {
                    Task { await app.runCalibration() }
                } label: {
                    Label(app.t("workbench.start_manual_cal"), systemImage: "scope")
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
                Text(app.t("workbench.collected", app.captures.count))
                    .font(.headline.monospacedDigit())
            } else {
                Text(app.t("workbench.scan_and_predict"))
                    .foregroundStyle(.secondary)
            }

            Label(app.t("workbench.hardware_hint"), systemImage: "hand.tap")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await app.runScan() }
            } label: {
                Text(app.isBusy ? app.busyTitle : app.t("workbench.start_scan"))
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
                    Label(app.t("workbench.predict_n", app.captures.count), systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(app.captures.count < 2 || app.isBusy)

                Button(app.t("workbench.clear"), role: .destructive) {
                    app.clearMeasurements()
                }
            }
        }
        .brandCard()
    }

    private func resultCard(_ result: MeasurementResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(app.t("workbench.result"), systemImage: "checkmark.seal.fill")
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
                Text(app.t("workbench.result_based", app.captures.count))
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
                Text(app.t("workbench.more"))
                    .font(.headline)
                if app.permissions.canSaveSpectrum {
                    Button(app.t("workbench.save_spectrum"), systemImage: "square.and.arrow.down") {
                        app.noticeMessage = app.t("workbench.save_pending")
                    }
                }
                if app.selectedDevice?.kind == .ir2210,
                   app.permissions.canConfigureDevice {
                    Button(app.t("workbench.ir_config"), systemImage: "slider.horizontal.3") {
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
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var integrationTime = 10.0
    @State private var instantLight = true
    @State private var averageEnabled = false
    @State private var averageCount = 3

    var body: some View {
        NavigationStack {
            Form {
                Section(app.t("device.settings.params")) {
                    LabeledContent(app.t("device.settings.integration"), value: "\(Int(integrationTime)) ms")
                    Slider(value: $integrationTime, in: 1 ... 50, step: 1)
                    Toggle(app.t("device.settings.instant"), isOn: $instantLight)
                    Toggle(app.t("device.settings.average"), isOn: $averageEnabled)
                    Stepper(app.t("device.settings.average_count", averageCount), value: $averageCount, in: 2 ... 10)
                        .disabled(!averageEnabled)
                }
                Section(app.t("device.settings.cal")) {
                    Button(app.t("device.settings.ti")) {}
                    Button(app.t("device.settings.aopu")) {}
                    Button(app.t("device.settings.dark")) {}
                }
                Section {
                    Button(app.t("device.settings.save")) { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(app.t("device.settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.t("common.close")) { dismiss() }
                }
            }
        }
    }
}
