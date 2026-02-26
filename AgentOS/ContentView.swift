import SwiftUI

struct ContentView: View {
    @State private var isAuthenticated = false
    @State private var hasCheckedAuth = false

    var body: some View {
        Group {
            if !hasCheckedAuth {
                // Loading
                ZStack {
                    AppTheme.background.ignoresSafeArea()
                    ProgressView()
                        .tint(AppTheme.primary)
                }
            } else if isAuthenticated {
                MainTabView()
            } else {
                LoginView(isAuthenticated: $isAuthenticated)
            }
        }
        .task {
            await checkAuth()
        }
    }

    private func checkAuth() async {
        // Check for stored auth token
        do {
            let token = try await DatabaseService.shared.getSetting(key: "auth_token")
            isAuthenticated = token != nil
        } catch {
            isAuthenticated = false
        }
        hasCheckedAuth = true
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label(String(localized: "Chat"), systemImage: "bubble.left")
                }
                .tag(0)

            MemoryView()
                .tabItem {
                    Label(String(localized: "Memory"), systemImage: "lightbulb")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
                .tag(2)
        }
        .tint(AppTheme.primary)
    }
}
