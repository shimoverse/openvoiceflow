import Foundation

/// When the satisfaction card (CsatView) is allowed to appear.
///
/// The card is a question, and a question asked too early gets a shrug: it
/// waits until the person has actually used the app — a few days *and* a
/// real number of takes — so the answer is about the product, not first
/// impressions. An unanswered card can return after 24 hours, an explicit
/// dismissal snoozes 15 days, and a confirmed submission ends automatic
/// prompts. It never appears while a dictation is in flight; the
/// caller checks that, since this is pure so the CI harness can pin the rules.
enum CsatPrompt {
    static let minimumDictations = 10
    static let minimumDaysOfUse = 3
    static let intervalAfterShown: TimeInterval = 86_400
    static let snoozeAfterDismiss: TimeInterval = 15 * 86_400
    private static let legacySnoozeAfterSubmit: TimeInterval = 120 * 86_400

    /// `nextPromptAt` is nil until the card has been shown once; after that it
    /// is the earliest moment it may return (Settings.csatNextPromptAt).
    static func shouldShow(
        now: Date,
        firstUseDate: Date?,
        dictationsCompleted: Int,
        nextPromptAt: Date?,
        submittedAt: Date?
    ) -> Bool {
        guard submittedAt == nil else { return false }
        if let nextPromptAt, now < nextPromptAt { return false }
        guard dictationsCompleted >= minimumDictations else { return false }
        guard let firstUseDate,
              now.timeIntervalSince(firstUseDate) >= Double(minimumDaysOfUse) * 86_400
        else { return false }
        return true
    }

    static func nextPrompt(afterShownAt now: Date) -> Date { now.addingTimeInterval(intervalAfterShown) }
    static func nextPrompt(afterDismissAt now: Date) -> Date { now.addingTimeInterval(snoozeAfterDismiss) }

    /// Only an accepted API response may create the permanent stop marker.
    static func submissionDate(accepted: Bool, at now: Date) -> Date? { accepted ? now : nil }

    /// Prior builds recorded successful sends in a lifetime aggregate counter
    /// and set a 120-day date. A dismissal date alone never proves submission.
    static func confirmedSubmissionAt(
        submittedAt: Date?, legacySubmitCount: Int, legacyNextPromptAt: Date?
    ) -> Date? {
        if let submittedAt { return submittedAt }
        guard legacySubmitCount > 0 else { return nil }
        return legacyNextPromptAt?.addingTimeInterval(-legacySnoozeAfterSubmit) ?? .distantPast
    }
}
