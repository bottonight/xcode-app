//
//  ContentView.swift
//  test
//
//  Created by JT Chen on 2026/9/4.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.session == nil {
                AuthenticationView()
            } else {
                MainShellView()
            }
        }
    }
}

private struct MainShellView: View {
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
        TabView {
            HomeFlowView()
                .tabItem {
                    Label("首页", systemImage: "house")
                }

            DeviceManagementView()
                .tabItem {
                    Label("设备", systemImage: "sensor")
                }

            AccountView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
        .tint(FabricTheme.indigo)
        .alert("提示", isPresented: hasMessage) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? app.noticeMessage ?? "")
        }
        .overlay {
            if app.isBusy {
                BusyOverlay(title: "正在处理")
            }
        }
    }
}
