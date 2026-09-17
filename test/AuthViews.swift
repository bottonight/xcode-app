import SwiftUI

struct AuthenticationView: View {
    @Environment(AppModel.self) private var app
    @State private var showsRegister = false
    @State private var account = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var verificationCode = ""
    @State private var company = ""
    @State private var industry = Industry.research
    @State private var codeCooldown = 0
    @FocusState private var focusedField: Field?

    private let allowsPhone = AppRegion.isMainlandChina

    private enum Field: Hashable {
        case account, username, password, confirm, code, company
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
        guard hasAccount, hasPassword, !app.isBusy else { return false }
        guard showsRegister else { return true }
        return password == confirmPassword
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FabricTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        form
                        switchModeButton
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
            Text(showsRegister ? "创建账号" : "用户登录")
                .font(.title2.bold())

            if showsRegister {
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
                .textContentType(showsRegister ? .newPassword : .password)
                .focused($focusedField, equals: .password)

            if showsRegister {
                Divider()
                SecureField("确认密码", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirm)
                Divider()
                HStack {
                    TextField("验证码", text: $verificationCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .code)
                    Button(codeCooldown > 0 ? "\(codeCooldown)s" : "获取验证码") {
                        Task { await sendCode() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(codeCooldown > 0 || app.isBusy || account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                TextField("公司（选填）", text: $company)
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .company)
                Divider()
                HStack {
                    Text("所在行业")
                    Spacer()
                    Picker("所在行业", selection: $industry) {
                        ForEach(Industry.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
            }

            Button {
                focusedField = nil
                Task { await submit() }
            } label: {
                Text(showsRegister ? "注册并登录" : "登录")
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

    private var switchModeButton: some View {
        Button {
            showsRegister.toggle()
        } label: {
            Text(showsRegister ? "已有账号？点击登录" : "没有账号？点击注册")
                .font(.footnote)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(app.isBusy)
    }

    private var privacyNote: some View {
        Label(
            "登录即表示同意用户协议和隐私政策。账号将保存在本机，下次打开自动登录。",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func sendCode() async {
        let sent = await app.sendVerificationCode(account: account)
        guard sent else { return }
        codeCooldown = 60
        while codeCooldown > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            codeCooldown -= 1
        }
    }

    private func submit() async {
        if showsRegister {
            await app.register(
                username: username,
                account: account,
                password: password,
                confirmPassword: confirmPassword,
                verificationCode: verificationCode,
                company: company,
                industry: industry.rawValue
            )
        } else {
            await app.login(account: account, password: password)
        }
    }
}
