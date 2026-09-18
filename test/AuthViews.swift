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
        case research
        case inspection
        case manufacturer
        case personal
        case trade

        var id: String { rawValue }

        var apiValue: String {
            switch self {
            case .research: "科研人员"
            case .inspection: "检测人员"
            case .manufacturer: "生产商"
            case .personal: "个人自用"
            case .trade: "贸易行业"
            }
        }

        var titleKey: String { "industry.\(rawValue)" }
    }

    private var accountPlaceholder: String {
        allowsPhone ? app.t("auth.account_cn") : app.t("auth.account_intl")
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
            Text(app.t("auth.tagline"))
                .foregroundStyle(.secondary)
            Text(allowsPhone ? app.t("auth.region_cn") : app.t("auth.region_intl"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(showsRegister ? app.t("auth.register_title") : app.t("auth.login_title"))
                .font(.title2.bold())

            if showsRegister {
                TextField(app.t("auth.username"), text: $username)
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

            SecureField(app.t("auth.password"), text: $password)
                .textContentType(showsRegister ? .newPassword : .password)
                .focused($focusedField, equals: .password)

            if showsRegister {
                Divider()
                SecureField(app.t("auth.confirm_password"), text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirm)
                Divider()
                HStack {
                    TextField(app.t("auth.code"), text: $verificationCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .code)
                    Button(codeCooldown > 0 ? "\(codeCooldown)s" : app.t("auth.get_code")) {
                        Task { await sendCode() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(codeCooldown > 0 || app.isBusy || account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                TextField(app.t("auth.company"), text: $company)
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .company)
                Divider()
                HStack {
                    Text(app.t("auth.industry"))
                    Spacer()
                    Picker(app.t("auth.industry"), selection: $industry) {
                        ForEach(Industry.allCases) { item in
                            Text(app.t(item.titleKey)).tag(item)
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
                Text(showsRegister ? app.t("auth.register") : app.t("auth.login"))
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
            Text(showsRegister ? app.t("auth.to_login") : app.t("auth.to_register"))
                .font(.footnote)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(app.isBusy)
    }

    private var privacyNote: some View {
        Label(
            app.t("auth.privacy"),
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
                industry: industry.apiValue
            )
        } else {
            await app.login(account: account, password: password)
        }
    }
}
