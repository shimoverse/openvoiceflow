import Foundation

/// When the satisfaction card (CsatView) is allowed to appear.
///
/// The card is a question, and a question asked too early gets a shrug: it
/// waits until the person has actually used the app — a few days *and* a
/// real number of takes — so the answer is about the product, not first
/// impressions. Once shown, dismissing it snoozes for a month; sending a rating
/// snoozes for a season. It never appears while a dictation is in flight; the
/// caller checks that, since this is pure so the CI harness can pin the rules.
enum CsatPrompt {
    static let minimumDictations = 10
    static let minimumDaysOfUse = 3
    static let snoozeAfterDismiss: TimeInterval = 30 * 86_400
    static let snoozeAfterSubmit: TimeInterval = 120 * 86_400

    /// `nextPromptAt` is nil until the card has been shown once; after that it
    /// is the earliest moment it may return (Settings.csatNextPromptAt).
    static func shouldShow(
        now: Date,
        firstUseDate: Date?,
        dictationsCompleted: Int,
        nextPromptAt: Date?
    ) -> Bool {
        if let nextPromptAt, now < nextPromptAt { return false }
        guard dictationsCompleted >= minimumDictations else { return false }
        guard let firstUseDate,
              now.timeIntervalSince(firstUseDate) >= Double(minimumDaysOfUse) * 86_400
        else { return false }
        return true
    }

    static func nextPrompt(afterDismissAt now: Date) -> Date { now.addingTimeInterval(snoozeAfterDismiss) }
    static func nextPrompt(afterSubmitAt now: Date) -> Date { now.addingTimeInterval(snoozeAfterSubmit) }
}
