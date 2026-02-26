import SwiftUI

struct ContentView: View {
    @State private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if !authViewModel.hasCheckedAuth {
                ZStack {
                    AppTheme.background.ignoresSafeArea()
                    ProgressView()
                        .tint(AppTheme.primary)
                }
            } else if authViewModel.isAuthenticated {
                MainTabView(authViewModel: authViewModel)
            } else {
                LoginView(authViewModel: authViewModel)
            }
        }
        .task {
            await authViewModel.loadAuth()
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var selectedTab = 0
    @State private var chatViewModel = ChatViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView(viewModel: chatViewModel)
                .tabItem {
                    Label(String(localized: "Chat"), systemImage: "bubble.left")
                }
                .tag(0)

            MemoryView()
                .tabItem {
                    Label(String(localized: "Memory"), systemImage: "lightbulb")
                }
                .tag(1)

            SettingsView(authViewModel: authViewModel)
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
                .tag(2)
        }
        .tint(AppTheme.primary)
    }
}
