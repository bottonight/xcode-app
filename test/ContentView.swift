import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    private var hasMessage: Binding<Bool> {
        Binding(
            get: { app.errorMessage != nil || app.noticeMessage != nil },
            set: { value in
                guard !value else { return }
                app.errorMessage = nil
                app.noticeMessage = nil
            }
        )
    }

    var body: some View {
        Group {
            if app.session == nil {
                AuthenticationView()
            } else {
                MainShellView()
            }
        }
        .alert(app.t("common.alert"), isPresented: hasMessage) {
            Button(app.t("common.ok"), role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? app.noticeMessage ?? "")
        }
        .overlay {
            if app.isBusy {
                BusyOverlay(title: app.busyTitle)
            }
        }
        .environment(\.locale, app.language.locale)
    }
}

private struct MainShellView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            HomeFlowView()
                .tabItem {
                    Label(app.t("tab.home"), systemImage: "house")
                }

            DeviceManagementView()
                .tabItem {
                    Label(app.t("tab.devices"), systemImage: "sensor")
                }

            AccountView()
                .tabItem {
                    Label(app.t("tab.account"), systemImage: "person.crop.circle")
                }
        }
        .tint(FabricTheme.indigo)
    }
}
