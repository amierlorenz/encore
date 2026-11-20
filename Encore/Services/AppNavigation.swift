import EncoreKit
import Observation

/// Shared navigation state, so one screen can open another, such as the
/// dashboard starting a study session.
@MainActor
@Observable
final class AppNavigation {
    var selection: SidebarSection? = .dashboard
    /// A session another screen asked the Study screen to start.
    var pendingSession: SessionConfig?
    /// A daily plan another screen asked the Study screen to start.
    var pendingDailyPlan: DailyPlan?
    /// An optional chunk index of the daily plan to start.
    var pendingChunkIndex: Int?

    func startSession(_ config: SessionConfig) {
        pendingDailyPlan = nil
        pendingChunkIndex = nil
        pendingSession = config
        selection = .study
    }

    func startDailyPlan(_ plan: DailyPlan, chunkIndex: Int? = nil) {
        pendingSession = nil
        pendingDailyPlan = plan
        pendingChunkIndex = chunkIndex
        selection = .study
    }
}
