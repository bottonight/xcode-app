import SwiftUI

struct AuthenticationView: View {
    @Environment(AppModel.self) private var app
    @State private var mode: Mode = .login
    @State private var account = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var company = ""
    @State private var industry = Industry.research
    @FocusState private var focusedField: Field?

    private let allowsPhone = AppRegion.isMainlandChina

    private enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"
        var id: String { rawValue }
    }

    private enum Field: Hashable {
        case account, username, password, confirm, company
    }

    private enum Industry: String, CaseIterable, Identifiable {
        case research = "科研人员"
        case inspection = "检测人员"
        case manufacturer = "生产商"
        case personal = "个人自用"
        case trade = "贸易行业"

        var id: String { rawValue }
    }

    private var accountPlaceholder: String {
        allowsPhone ? "手机号或邮箱" : "邮箱"
    }

    private var canSubmit: Bool {
        let hasAccount = !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPassword = password.count >= 6
        if mode == .login {
            return hasAccount && hasPassword && !app.isBusy
        }
        return hasAccount
            && hasPassword
            && password == confirmPassword
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !app.isBusy
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FabricTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        form
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
            Text(allowsPhone ? "当前地区：中国大陆" : "Current region: International")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(mode == .login ? "用户登录" : "创建账号")
                .font(.title2.bold())

            if mode == .register {
                TextField("用户名", text: $username)
                    .textContentType(.username)
                    .focused($focusedField, equals: .username)
                Divider()
            }

            TextField(accountPlaceholder, text: $account)
                .keyboardType(allowsPhone ? .default : .emailAddress)
                .textContentType(allowsPhone ? .username : .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .account)

            Divider()

            SecureField("密码（至少 6 位）", text: $password)
                .textContentType(mode == .register ? .newPassword : .password)
                .focused($focusedField, equals: .password)

            if mode == .register {
                Divider()
                SecureField("确认密码", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirm)
                Divider()
                TextField("公司（选填）", text: $company)
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .company)
                Picker("行业", selection: $industry) {
                    ForEach(Industry.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
            }

            Button {
                focusedField = nil
                Task { await submit() }
            } label: {
                Text(mode == .login ? "登录" : "注册并登录")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(FabricTheme.indigo)
            .disabled(!canSubmit)
        }
        .textFieldStyle(.plain)
        .brandCard()
    }

    private var privacyNote: some View {
        Label(
            "登录即表示同意用户协议和隐私政策。账号将保存在本机，下次打开自动登录。",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func submit() async {
        if mode == .login {
            await app.login(account: account, password: password)
        } else {
            await app.register(
                username: username,
                account: account,
                password: password,
                confirmPassword: confirmPassword,
                company: company,
                industry: industry.rawValue
            )
        }
    }
}
