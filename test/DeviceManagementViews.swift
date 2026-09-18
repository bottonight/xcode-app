import Charts
import SwiftUI

struct DeviceManagementView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.managedDevices.isEmpty && !app.isBusy {
                    ContentUnavailableView {
                        Label(app.t("devices.empty"), systemImage: "sensor")
                    } description: {
                        Text(app.t("devices.empty_hint"))
                    }
                } else {
                    List(app.managedDevices) { device in
                        NavigationLink {
                            ManagedDeviceDetailView(device: device)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(device.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(app.t("mode.monthly_use", device.monthlyUseCount))
                                        .font(.subheadline)
                                        .foregroundStyle(FabricTheme.indigo)
                                }
                                Text(device.serialNumber)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await app.loadManagedDevices()
                    }
                }
            }
            .navigationTitle(app.t("devices.title"))
            .task {
                if app.managedDevices.isEmpty {
                    await app.loadManagedDevices()
                }
            }
        }
    }
}

private struct UsageEntry: Identifiable {
    let month: String
    let count: Int
    var id: String { month }
}

struct ManagedDeviceDetailView: View {
    @Environment(AppModel.self) private var app
    let device: ManagedDevice
    @State private var showsSharing = false

    private var entries: [UsageEntry] {
        device.usageHistory
            .map { UsageEntry(month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(device.name)
                        .font(.title2.bold())
                    Text(device.serialNumber)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                    Divider()
                    LabeledContent(app.t("devices.monthly_count"), value: "\(device.monthlyUseCount)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .brandCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text(app.t("devices.trend"))
                        .font(.headline)
                    Chart(entries) { entry in
                        BarMark(
                            x: .value(app.t("devices.month"), entry.month),
                            y: .value(app.t("devices.count"), entry.count)
                        )
                        .foregroundStyle(FabricTheme.indigo.gradient)
                        .cornerRadius(4)
                    }
                    .frame(height: 190)
                }
                .brandCard()

                if device.isShareable {
                    Button {
                        showsSharing = true
                    } label: {
                        Label(app.t("devices.manage_share"), systemImage: "person.2.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FabricTheme.indigo)
                }
            }
            .padding()
        }
        .background(FabricTheme.background.ignoresSafeArea())
        .navigationTitle(app.t("devices.detail"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSharing) {
            DeviceSharingView(device: device)
        }
    }
}

struct DeviceSharingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let device: ManagedDevice

    @State private var phoneNumber = ""
    @State private var users: [SharedUser] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section(app.t("share.add")) {
                    TextField(app.t("share.phone"), text: $phoneNumber)
                        .keyboardType(.phonePad)
                    Button(app.t("share.action")) {
                        Task {
                            guard await app.share(device, phoneNumber: phoneNumber) else { return }
                            phoneNumber = ""
                            await reload()
                        }
                    }
                    .disabled(phoneNumber.count != 11)
                }

                Section(app.t("share.existing")) {
                    if users.isEmpty && !isLoading {
                        Text(app.t("share.empty"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(users) { user in
                        HStack {
                            Label(user.phoneNumber, systemImage: "person.crop.circle")
                            Spacer()
                            Button(app.t("share.revoke"), role: .destructive) {
                                Task {
                                    if await app.revoke(device, phoneNumber: user.phoneNumber) {
                                        await reload()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .navigationTitle(app.t("share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(app.t("common.done")) { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await app.sharedUsers(for: device)
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(FabricTheme.indigo)
                        VStack(alignment: .leading) {
                            Text(app.session?.username ?? app.t("common.user"))
                                .font(.headline)
                            Text(app.session?.displayAccount ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Picker(app.t("account.language"), selection: Binding(
                        get: { app.language },
                        set: { app.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language)
                        }
                    }
                }
                if app.permissions.adminLevel >= 1 {
                    Section(app.t("account.permissions")) {
                        LabeledContent(app.t("account.admin_level"), value: "\(app.permissions.adminLevel)")
                    }
                }
                Section {
                    Button(app.t("account.sign_out"), role: .destructive) {
                        app.signOut()
                    }
                }
            }
            .navigationTitle(app.t("account.title"))
        }
    }
}
