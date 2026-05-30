//
//  UpmarketApp.swift
//  Upmarket
//
//  Created by Andrew McArdle on 30/5/2026.
//

import SwiftUI

@main
struct UpmarketApp: App {

    @StateObject private var pythonBridge = PythonBridge.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pythonBridge)
        }
    }

    init() {
        Task { @MainActor in
            PythonBridge.shared.setup()
        }
    }
}
