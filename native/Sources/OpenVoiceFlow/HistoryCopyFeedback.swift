import Combine
import Foundation

/// Short-lived acknowledgement for History copy actions.
///
/// One task owns the reset. Copying another row cancels that task so an older
/// timer can never clear a newer row's feedback.
@MainActor
final class HistoryCopyFeedback: ObservableObject {
    @Published private(set) var copiedEntryID: UUID?
    private var resetTask: Task<Void, Never>?

    func markCopied(_ entryID: UUID, dismissAfterNanoseconds: UInt64 = 1_500_000_000) {
        resetTask?.cancel()
        copiedEntryID = entryID
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: dismissAfterNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.copiedEntryID == entryID else { return }
            self.copiedEntryID = nil
        }
    }

    func isCopied(_ entryID: UUID) -> Bool {
        copiedEntryID == entryID
    }
}
