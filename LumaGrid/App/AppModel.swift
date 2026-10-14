import Foundation
import Observation
import LumaGridEngine
import LumaGridServices

enum AppScreen: Equatable {
    case home
    case game
}

/// Dependency container and top-level navigation state. Services are created once here and
/// injected into views through the environment, so ads and purchases can be swapped for test doubles.
@MainActor
@Observable
final class AppModel {
    var screen: AppScreen = .home
    var isShopPresented = false
    var isSettingsPresented = false
    /// The game currently on screen. Created when the player starts or resumes a round.
    var game: GameViewModel?

    let progress: ProgressStore
    let store: StoreService
    let ads: AdsManager
    let feedback: FeedbackService

    init(progress: ProgressStore, store: StoreService, ads: AdsManager, feedback: FeedbackService) {
        self.progress = progress
        self.store = store
        self.ads = ads
        self.feedback = feedback
    }

    static func makeLive() -> AppModel {
        let progress = ProgressStore.makeDefault()
        let feedback = FeedbackService(settings: { progress.settings })
        let store = StoreService(catalog: AppConfiguration.productCatalog, progress: progress,
                                 isEnabled: !AppConfiguration.isUITesting)
        let ads = AdsManager(configuration: AppConfiguration.ads, progress: progress)
        return AppModel(progress: progress, store: store, ads: ads, feedback: feedback)
    }

    static func preview() -> AppModel {
        let progress = ProgressStore.preview()
        return AppModel(
            progress: progress,
            store: StoreService(catalog: AppConfiguration.productCatalog, progress: progress, isEnabled: false),
            ads: AdsManager(configuration: AppConfiguration.ads, progress: progress, forceDisabled: true),
            feedback: FeedbackService(settings: { progress.settings })
        )
    }

    @ObservationIgnored private var hasStarted = false

    /// Called once at launch. Never blocks the player from reaching the home screen.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        store.start()
        progress.update { $0.validateSelectedTheme(in: AppConfiguration.themes) }
        Task { await ads.start() }
    }

    // MARK: Navigation

    var savedGame: GameSession? { progress.progress.savedGame }

    func startNewGame(mode: GameMode = .classic) {
        let session: GameSession
        switch mode {
        case .classic:
            session = GameSession(configuration: AppConfiguration.game, seed: UInt64.random(in: 1...UInt64.max))
        case let .daily(dateKey):
            session = DailyChallenge.makeSession(dateKey: dateKey, configuration: AppConfiguration.game)
        }
        open(session)
    }

    func resumeSavedGame() {
        guard let saved = savedGame else { return startNewGame() }
        open(saved)
    }

    func goHome() {
        game = nil
        screen = .home
    }

    private func open(_ session: GameSession) {
        progress.update { $0.savedGame = session.isGameOver ? nil : session }
        game = GameViewModel(session: session, app: self)
        screen = .game
    }

    // MARK: Daily

    static func todayKey(calendar: Calendar = .current, now: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return DailyChallenge.dateKey(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}
