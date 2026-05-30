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
    @StateObject private var conversionService = ConversionService.shared
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var featureFlags = FeatureFlags.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pythonBridge)
                .environmentObject(conversionService)
                .environmentObject(storeManager)
                .environmentObject(modelManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Convert Document…") {
                    NotificationCenter.default.post(name: .openFilePicker, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(conversionService)
                .environmentObject(storeManager)
                .environmentObject(modelManager)
        } label: {
            Text("#")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        Task { @MainActor in
            PythonBridge.shared.setup()
        }
        FeatureFlags.shared.fetchFlags()
    }
}
