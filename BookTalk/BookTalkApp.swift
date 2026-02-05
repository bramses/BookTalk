import SwiftUI
import CoreSpotlight

@main
struct BookTalkApp: App {
    @StateObject private var spotlightNavigation = SpotlightNavigationState()

    init() {
        // Initialize database on app launch (accessing shared triggers init)
        _ = DatabaseManager.shared

        // Reindex annotations in Spotlight (runs in background)
        SpotlightService.shared.reindexAllAnnotationsBackground()
        
        // Initialize PTT Manager for lock screen recording access
        Task { @MainActor in
            await PTTManager.shared.initialize()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(spotlightNavigation)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        spotlightNavigation.pendingAnnotationId = identifier
                    }
                }
        }
    }
}

class SpotlightNavigationState: ObservableObject {
    @Published var pendingAnnotationId: String?
}
