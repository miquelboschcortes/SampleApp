/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 The main content of the app.
*/

import SwiftUI
import Energy

@main
struct SampleApp: App {
    @StateObject private var homeEmulator: HomeEmulator = HomeEmulator()

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem {
                        Label("Status", systemImage: "gauge.medium")
                    }
                AccessoryListView()
                    .tabItem {
                        Label("Accessories", systemImage: "switch.2")
                    }
                SuperuserView()
                    .tabItem {
                        Label("Debug", systemImage: "gear")
                    }
            }
            .environment(\.managedObjectContext, homeEmulator.viewContext)
            .environmentObject(homeEmulator)
            .environmentObject(homeEmulator.generator)
            .environmentObject(homeEmulator.battery)
        }
    }
}
