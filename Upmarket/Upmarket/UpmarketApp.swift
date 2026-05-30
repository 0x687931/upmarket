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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pythonBridge)
                .environmentObject(conversionService)
                .environmentObject(storeManager)
                .environmentObject(modelManager)
        }
    }

    init() {
        Task { @MainActor in
            PythonBridge.shared.setup()
        }
    }
}
