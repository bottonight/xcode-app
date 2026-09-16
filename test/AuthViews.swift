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

    var body: some View {
        NavigationStack {
            ZStack {
                FabricTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        loginForm
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

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("用户登录")
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
                Text("登录")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(FabricTheme.indigo)
        }
        .textFieldStyle(.plain)
        .brandCard()
    }

    private var privacyNote: some View {
        Label(
            "登录即表示同意用户协议和隐私政策。",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

