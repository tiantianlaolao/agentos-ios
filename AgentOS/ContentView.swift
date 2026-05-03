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
    @State private var changelog = ChangelogService.shared
    // Pre / post versions captured at sheet-trigger time so the dialog's
    // `entry` doesn't disappear mid-render if refresh() clears it.
    @State private var showingPreVersion: ChangelogEntry?
    @State private var showingPostVersion: ChangelogEntry?
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
        .onChange(of: authViewModel.requestedTab) { _, newValue in
            if let newValue {
                selectedTab = newValue
                authViewModel.requestedTab = nil
            }
        }
        // Changelog dialog wiring — fetch on appear + foreground.
        .task {
            await changelog.refresh()
            triggerPendingDialog()
        }
        .onChange(of: changelog.response?.latest_version) { _, _ in
            triggerPendingDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await changelog.refresh()
                triggerPendingDialog()
            }
        }
        .sheet(item: $showingPreVersion) { entry in
            ChangelogDialog(entry: entry, mode: .pre, onDismiss: {
                showingPreVersion = nil
            })
        }
        .sheet(item: $showingPostVersion) { entry in
            ChangelogDialog(entry: entry, mode: .post, onDismiss: {
                showingPostVersion = nil
            })
        }
    }

    private func triggerPendingDialog() {
        // Pre takes priority over post. Don't double-show if already presenting.
        if showingPreVersion == nil, showingPostVersion == nil {
            if let pre = changelog.pendingPre {
                showingPreVersion = pre
            } else if let post = changelog.pendingPost {
                showingPostVersion = post
            }
        }
    }
}
