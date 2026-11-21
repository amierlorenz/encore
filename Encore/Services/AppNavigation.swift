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
    /// Which part of the daily plan to start.
    var pendingDailyPlanPart: DailyPlanPart = .session
    /// An optional chunk index of the daily plan to start.
    var pendingChunkIndex: Int?
    /// A post-class plan another screen asked the Study screen to start.
    var pendingPostclassPlan: DailyPlan?

    func startSession(_ config: SessionConfig) {
        pendingDailyPlan = nil
        pendingPostclassPlan = nil
        pendingDailyPlanPart = .session
        pendingChunkIndex = nil
        pendingSession = config
        selection = .study
    }

    func startDailyPlan(_ plan: DailyPlan, part: DailyPlanPart = .session, chunkIndex: Int? = nil) {
        pendingSession = nil
        pendingPostclassPlan = nil
        pendingDailyPlan = plan
        pendingDailyPlanPart = part
        pendingChunkIndex = chunkIndex
        selection = .study
    }

    func startPostclassQuiz(_ plan: DailyPlan) {
        pendingSession = nil
        pendingDailyPlan = nil
        pendingDailyPlanPart = .session
        pendingChunkIndex = nil
        pendingPostclassPlan = plan
        selection = .study
    }
}
