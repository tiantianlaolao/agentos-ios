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
            await L10n.shared.loadLocale()
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
                    Label(L10n.tr("tabs.chat"), systemImage: "bubble.left")
                }
                .tag(0)

            NavigationStack {
                MemoryView()
            }
            .tabItem {
                Label(L10n.tr("tabs.memory"), systemImage: "lightbulb")
            }
            .tag(1)

            NavigationStack {
                SettingsView(authViewModel: authViewModel)
            }
            .tabItem {
                Label(L10n.tr("tabs.settings"), systemImage: "gearshape")
            }
            .tag(2)
        }
        .tint(AppTheme.primary)
    }
}
