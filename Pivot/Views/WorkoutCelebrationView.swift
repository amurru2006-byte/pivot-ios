import SwiftUI

struct WorkoutCelebrationOverlay: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.scenePhase) private var scene
    var enabled: Bool
    let sessionID: UUID
    @State private var presenting: TrainingAchievement?
    private var canPresent: Bool { enabled && scene == .active && !store.isLoading && !store.isRestoring && !store.locked }
    var body: some View {
        ZStack {
            if canPresent, let achievement = presenting {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        Button { dismissAchievement() } label: {
                            Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                        }.accessibilityLabel("Chiudi traguardo").accessibilityIdentifier("close-workout-achievement")
                    }
                    if achievement.kind == .rank, let level = achievement.rankLevel {
                        StrengthRankEmblem(level: level, size: 126)
                        Text("Nuovo rank!").font(.title2.bold())
                        Text(StrengthRankPresentation.name(level)).font(.title3.bold()).multilineTextAlignment(.center)
                        Text(achievement.benchmark?.title ?? achievement.exercise).font(.subheadline).foregroundStyle(PivotTheme.muted)
                    } else {
                        Image(systemName: "medal.fill").font(.system(size: 76)).foregroundStyle(PivotTheme.amber).accessibilityHidden(true)
                        Text("Nuovo massimale stimato!").font(.title2.bold()).multilineTextAlignment(.center)
                        Text(achievement.exercise).font(.headline).multilineTextAlignment(.center)
                        Text(StrengthRankPresentation.kg(achievement.value)).font(.system(size: 32, weight: .bold, design: .rounded))
                        if let previous = achievement.previousValue {
                            Text("Prima: \(StrengthRankPresentation.kg(previous))").font(.subheadline).foregroundStyle(PivotTheme.muted)
                        }
                    }
                    Text("Un nuovo traguardo, serie dopo serie.").font(.caption).foregroundStyle(PivotTheme.muted)
                }.padding(.horizontal, 22).padding(.bottom, 28)
                    .frame(maxWidth: 320).background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    .padding(24).accessibilityIdentifier("workout-achievement")
            }
        }
        .onChange(of: store.data.updatedAt) { _, _ in refresh() }
        .onChange(of: canPresent) { _, _ in refresh() }
        .onAppear { refresh() }
        .task(id: canPresent ? presenting?.id : nil) {
            guard canPresent, let id = presenting?.id else { return }
            do { try await Task.sleep(nanoseconds: 4_500_000_000) }
            catch { return }
            if presenting?.id == id && canPresent { dismissAchievement() }
        }
    }
    private func refresh() {
        guard canPresent else { return }
        let library = store.data.training ?? .init()
        if let presenting, TrainingRecords.isCurrent(presenting, library: library) { return }
        presenting = (library.achievements ?? []).first { $0.sessionID == sessionID && $0.presentedAt == nil && TrainingRecords.isCurrent($0, library: library) }
    }
    private func dismissAchievement() {
        guard let id = presenting?.id, canPresent else { return }
        let saved = store.change { data in
            guard let i = data.training?.achievements?.firstIndex(where: { $0.id == id }) else { return }
            data.training?.achievements?[i].presentedAt = Date()
        }
        if saved { presenting = nil; refresh() }
    }
}
