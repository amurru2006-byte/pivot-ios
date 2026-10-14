import Foundation

/// Numeric edits can be temporarily incomplete while the user replaces a
/// value on an already completed set. Keep the last valid saved snapshot,
/// rather than raising a modal validation error on every keystroke.
enum TrainingDraftValidation {
    static func canAutosave(_ session: TrainingSession) -> Bool {
        do { try TrainingLibrary(sessions: [session]).validate(); return true }
        catch { return false }
    }
}
