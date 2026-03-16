import SwiftUI

@main
struct AgentOSApp: App {
    init() {
        // Force dark mode
        setupAppearance()

        // Initialize database
        Task {
            do {
                try await DatabaseService.shared.initialize()
            } catch {
                print("[AgentOS] Database init failed: \(error)")
            }
        }

        // Auto-select fastest server node
        Task {
            let bestUrl = await ServerSelector.selectBest()
            await ServerConfig.shared.update(wsUrl: bestUrl)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }

    private func setupAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(AppTheme.background)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(AppTheme.surface)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
