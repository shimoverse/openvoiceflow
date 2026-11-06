import Foundation

/// One Sparkle check cycle's observed result, separate from the last successful
/// check: a failed attempt must never turn a cached timestamp into "Up to date".
struct UpdateCheckStatus {
    enum Result: Equatable {
        case unverified
        case current
        case noCompatibleUpdate
        case available(String)
        case failed
    }

    private(set) var result: Result = .unverified
    private(set) var isChecking = false
    private(set) var lastSuccessfulCheckAt: Date?
    private var receivedResult = false

    init(lastSuccessfulCheckAt: Date? = nil) {
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
    }

    mutating func begin() {
        isChecking = true
        receivedResult = false
        result = .unverified
    }

    mutating func found(version: String, at date: Date) {
        result = .available(version)
        successfulCheck(at: date)
    }

    mutating func notFound(isCurrent: Bool, at date: Date) {
        result = isCurrent ? .current : .noCompatibleUpdate
        successfulCheck(at: date)
    }

    private mutating func successfulCheck(at date: Date) {
        receivedResult = true
        // Appcast verification is complete even if Sparkle's download/install
        // cycle remains open (including while an idle-gated install waits).
        isChecking = false
        lastSuccessfulCheckAt = date
    }

    /// Sparkle also aborts the normal no-update cycle. Preserve a result if
    /// one arrived; otherwise this attempt has not verified the running build.
    mutating func aborted(expectedNoUpdate: Bool = false, userCanceled: Bool = false) {
        guard !receivedResult || !(expectedNoUpdate || userCanceled) else { return }
        isChecking = false
        result = .failed
    }

    mutating func finished(errorOccurred: Bool = false) {
        if !receivedResult || errorOccurred { result = .failed }
        isChecking = false
        receivedResult = false
    }

    mutating func invalidate() {
        result = .unverified
        isChecking = false
        receivedResult = false
    }
}
