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
    // Observe locale version to refresh tab labels and content on language change
    private var localeVersion: Int { L10n.shared.version }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView(viewModel: chatViewModel, authViewModel: authViewModel)
                .id("chat-\(localeVersion)")
                .tabItem {
                    Label(L10n.tr("tabs.chat"), systemImage: "bubble.left")
                }
                .tag(0)

            SkillStoreView()
                .id("skills-\(localeVersion)")
                .tabItem {
                    Label(L10n.tr("tabs.skills"), systemImage: "square.grid.2x2")
                }
                .tag(1)

            NavigationStack {
                MemoryView()
            }
            .id("memory-\(localeVersion)")
            .tabItem {
                Label(L10n.tr("tabs.memory"), systemImage: "lightbulb")
            }
            .tag(2)

            NavigationStack {
                SettingsView(authViewModel: authViewModel)
            }
            .id("settings-\(localeVersion)")
            .tabItem {
                Label(L10n.tr("tabs.settings"), systemImage: "gearshape")
            }
            .tag(3)
        }
        .tint(AppTheme.primary)
    }
}
