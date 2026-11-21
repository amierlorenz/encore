import EncoreKit
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.dailyNewLimit) private var dailyNewLimit = NewConceptBudget.defaultLimit
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query private var reviews: [ReviewLog]
    @State private var isShowingSettings = false

    var body: some View {
        let overview = StudyOverview(courses: courses, exams: exams)
        let activePlan = DailyPlanStore.shared.activePlan()
        let dueCount = overview.courses.reduce(0) { $0 + $1.due }
        let isPlanDone = activePlan != nil && dueCount == 0 && reviewedToday > 0
        NavigationStack {
            Form {
                TodaySection(
                    due: dueCount,
                    newRemaining: newRemaining,
                    reviewedToday: reviewedToday,
                    plan: activePlan,
                    isPlanDone: isPlanDone,
                    onReview: { navigation.startSession(SessionConfig(mode: .review)) },
                    onLearn: { navigation.startSession(SessionConfig(mode: .learnNew)) },
                    onStartPlan: {
                        if let activePlan {
                            navigation.startDailyPlan(activePlan)
                        }
                    },
                    onKeepPracticing: {
                        navigation.startSession(SessionConfig(mode: .practice))
                    },
                    onStartPracticeTest: {
                        if let activePlan {
                            navigation.startDailyPlan(activePlan, part: .practiceTest)
                        }
                    },
                    onStartReviewQuiz: {
                        if let activePlan {
                            navigation.startDailyPlan(activePlan, part: .reviewQuiz)
                        }
                    }
                )
                if !overview.exams.isEmpty {
                    Section("Upcoming exams") {
                        ForEach(overview.exams) { exam in
                            ExamReadinessRow(exam: exam) { prepare(for: exam) }
                        }
                    }
                }
                CalibrationSection()
                Section("Classes") {
                    ForEach(overview.courses) { course in
                        CourseCountsRow(course: course) {
                            navigation.startSession(SessionConfig(scope: .init(courseIDs: [course.id]), mode: .review))
                        }
                    }
                    if overview.courses.isEmpty {
                        Text("Import or add a class to get started.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Home")
            .inlineTitleOnPhone()
            #if os(iOS)
            .toolbar {
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            #endif
        }
    }

    private var reviewedToday: Int {
        let start = Calendar.current.startOfDay(for: .now)
        return reviews.count { $0.reviewedAt >= start }
    }

    private var newRemaining: Int {
        (try? NewConceptBudget.remaining(limit: dailyNewLimit, in: modelContext)) ?? dailyNewLimit
    }

    private func prepare(for exam: StudyOverview.ExamReadiness) {
        navigation.startSession(SessionConfig(scope: exam.scope, mode: .practice, length: .minutes(25), order: .hardestFirst))
    }
}
