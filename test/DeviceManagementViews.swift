import Charts
import SwiftUI

struct DeviceManagementView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.managedDevices.isEmpty && !app.isBusy {
                    ContentUnavailableView {
                        Label("还没有绑定设备", systemImage: "sensor")
                    } description: {
                        Text("在首页连接设备后即可完成绑定")
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
                                    Text("本月 \(device.monthlyUseCount) 次")
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
            .navigationTitle("我的设备")
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
                    LabeledContent("本月使用次数", value: "\(device.monthlyUseCount)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .brandCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("使用趋势")
                        .font(.headline)
                    Chart(entries) { entry in
                        BarMark(
                            x: .value("月份", entry.month),
                            y: .value("次数", entry.count)
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
                        Label("管理设备分享", systemImage: "person.2.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FabricTheme.indigo)
                }
            }
            .padding()
        }
        .background(FabricTheme.background.ignoresSafeArea())
        .navigationTitle("设备详情")
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
                Section("添加共享用户") {
                    TextField("用户手机号", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    Button("分享设备") {
                        Task {
                            guard await app.share(device, phoneNumber: phoneNumber) else { return }
                            phoneNumber = ""
                            await reload()
                        }
                    }
                    .disabled(phoneNumber.count != 11)
                }

                Section("已共享") {
                    if users.isEmpty && !isLoading {
                        Text("尚未分享给其他用户")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(users) { user in
                        HStack {
                            Label(user.phoneNumber, systemImage: "person.crop.circle")
                            Spacer()
                            Button("取消", role: .destructive) {
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
            .navigationTitle("设备分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
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
                            Text(app.session?.username ?? "用户")
                                .font(.headline)
                            Text(app.session?.phoneNumber ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("权限") {
                    LabeledContent("管理员等级", value: "\(app.permissions.adminLevel)")
                }
                Section {
                    Button("退出登录", role: .destructive) {
                        app.signOut()
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}
