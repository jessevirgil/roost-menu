import SwiftUI

@main
struct RoostMenuApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(state)
        } label: {
            MenuBarLabel().environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Window("Roost Menu Settings", id: "settings") {
            SettingsView().environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
            if let t = state.primaryThermostat, let c = t.ambientC {
                Text(Temp.text(c, fahrenheit: t.usesFahrenheit))
            }
        }
    }
}
