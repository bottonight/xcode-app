//
//  testApp.swift
//  test
//
//  Created by JT Chen on 2026/9/4.
//

import SwiftUI

@main
struct FabricLabApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(\.locale, appModel.language.locale)
        }
    }
}
