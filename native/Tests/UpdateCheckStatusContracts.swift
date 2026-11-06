import Foundation

@main struct UpdateCheckStatusContracts {
    static func main() {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(3600)
        var state = UpdateCheckStatus()
        precondition(state.result == .unverified && state.lastSuccessfulCheckAt == nil)

        state.begin()
        precondition(state.isChecking && state.lastSuccessfulCheckAt == nil)
        state.aborted()
        state.finished()
        precondition(state.result == .failed && state.lastSuccessfulCheckAt == nil)

        state.begin()
        state.notFound(isCurrent: true, at: first)
        state.aborted(expectedNoUpdate: true) // Sparkle reports SUNoUpdateError after not-found.
        state.finished()
        precondition(state.result == .current && state.lastSuccessfulCheckAt == first)

        state.begin()
        precondition(state.isChecking && state.result == .unverified && state.lastSuccessfulCheckAt == first)
        state.finished() // An inconclusive cycle must not resurrect "Up to date".
        precondition(state.result == .failed && state.lastSuccessfulCheckAt == first)

        state.begin()
        state.notFound(isCurrent: false, at: first)
        state.aborted(expectedNoUpdate: true)
        state.finished()
        precondition(state.result == .noCompatibleUpdate && state.lastSuccessfulCheckAt == first)

        state.begin()
        state.found(version: "0.6.4", at: second)
        state.finished()
        precondition(state.result == .available("0.6.4") && state.lastSuccessfulCheckAt == second)

        state.begin()
        state.found(version: "0.6.5", at: second)
        state.aborted() // An actual download or verification error after discovery.
        state.finished(errorOccurred: true)
        precondition(state.result == .failed && state.lastSuccessfulCheckAt == second)

        let suite = "UpdateCheckStatusContracts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(state.lastSuccessfulCheckAt, forKey: "OVFLastSuccessfulUpdateCheck")
        var relaunched = UpdateCheckStatus(lastSuccessfulCheckAt: defaults.object(forKey: "OVFLastSuccessfulUpdateCheck") as? Date)
        precondition(relaunched.result == .unverified && relaunched.lastSuccessfulCheckAt == second)
        relaunched.invalidate() // Switching automatic checks off doesn't erase the date.
        precondition(relaunched.lastSuccessfulCheckAt == second && relaunched.result == .unverified)
        relaunched.begin() // Manual checks are independent of the automatic preference.
        relaunched.notFound(isCurrent: true, at: second)
        relaunched.finished()
        precondition(relaunched.result == .current)
        print("Update check lifecycle and isolated-defaults persistence passed")
    }
}
