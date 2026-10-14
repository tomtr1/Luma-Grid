import Foundation
import Observation
import LumaGridEngine
import LumaGridServices

/// Observable owner of the player's saved progress. All mutations go through `update`, which
/// applies the change and saves immediately, so a change is never half-persisted.
@MainActor
@Observable
final class ProgressStore {
    private(set) var progress: PlayerProgress
    private(set) var loadIssue: ProgressLoadIssue
    private(set) var lastSaveFailed = false

    @ObservationIgnored private let repository: ProgressRepository

    init(repository: ProgressRepository) {
        self.repository = repository
        let (progress, issue) = repository.load()
        self.progress = progress
        self.loadIssue = issue
    }

    /// Production store in Application Support, or an in-memory store for UI tests and previews.
    static func makeDefault() -> ProgressStore {
        if AppConfiguration.isUITesting {
            return ProgressStore(repository: ProgressRepository(storage: InMemoryProgressStorage()))
        }
        do {
            return ProgressStore(repository: ProgressRepository(storage: try FileProgressStorage.defaultLocation()))
        } catch {
            // Application Support unavailable (extremely rare): keep the game playable in memory.
            return ProgressStore(repository: ProgressRepository(storage: InMemoryProgressStorage()))
        }
    }

    static func preview() -> ProgressStore {
        ProgressStore(repository: ProgressRepository(storage: InMemoryProgressStorage()))
    }

    /// Applies a change and saves it. Returns the closure's result for convenience.
    @discardableResult
    func update<T>(_ change: (inout PlayerProgress) -> T) -> T {
        var copy = progress
        let result = change(&copy)
        progress = copy
        save()
        return result
    }

    func save() {
        do {
            try repository.save(progress)
            lastSaveFailed = false
        } catch {
            lastSaveFailed = true
        }
    }

    // MARK: Convenience

    var settings: GameSettings { progress.settings }

    var selectedTheme: ThemeDefinition {
        AppConfiguration.themes.first { $0.id == progress.selectedThemeID } ?? AppConfiguration.themes[0]
    }

    var hasRemoveForcedAds: Bool {
        PurchaseProcessor.hasRemoveForcedAds(progress, catalog: AppConfiguration.productCatalog)
    }
}
