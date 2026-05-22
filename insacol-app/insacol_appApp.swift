//
//  insacol_appApp.swift
//  insacol-app
//
//  Created by Guillermo Matos on 16/5/26.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct insacol_appApp: App {
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}
