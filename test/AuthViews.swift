import SwiftUI

struct AuthenticationView: View {
    @Environment(AppModel.self) private var app
    @State private var phoneNumber = ""
    @State private var username = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case phone
        case username
    }

    private var canSubmit: Bool {
        phoneNumber.count == 11 && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FabricTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        registrationForm
                        privacyNote
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(FabricTheme.indigo.gradient)
                    .frame(width: 60, height: 60)
                Image(systemName: "waveform.path.ecg")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            Text("FabricLab")
                .font(.largeTitle.bold())
            Text("连接近红外设备，快速获取可信的分析数据")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }

    private var registrationForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("功能验证")
                .font(.title2.bold())

            TextField("手机号", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focusedField, equals: .phone)

            Divider()

            TextField("用户名", text: $username)
                .textContentType(.name)
                .focused($focusedField, equals: .username)

            Divider()

            Button {
                app.startValidationSession(phoneNumber: phoneNumber, username: username)
                focusedField = nil
            } label: {
                Text("进入功能验证")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(FabricTheme.indigo)
            .disabled(!canSubmit || app.isBusy)
        }
        .textFieldStyle(.plain)
        .brandCard()
    }

    private var privacyNote: some View {
        Label(
            "当前版本暂不调用认证接口，手机号仅用于旧设备与预测接口联调。",
            systemImage: "hammer"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct ProjectSwitcherSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List(AppProject.allCases) { project in
                Button {
                    app.chooseProject(project)
                } label: {
                    HStack {
                        Image(systemName: project.isAvailable ? "waveform.path.ecg" : "plus")
                            .frame(width: 32)
                            .foregroundStyle(project.isAvailable ? FabricTheme.indigo : .secondary)
                        VStack(alignment: .leading) {
                            Text(project.rawValue)
                                .foregroundStyle(.primary)
                            Text(project.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if project == app.selectedProject {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(FabricTheme.indigo)
                        } else if !project.isAvailable {
                            Text("敬请期待")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!project.isAvailable)
            }
            .navigationTitle("切换项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { app.isProjectSwitcherPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
