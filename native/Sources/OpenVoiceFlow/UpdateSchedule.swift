import Foundation

/// When the daily automatic update check runs: 3:00 PM Pacific, every day.
///
/// Sparkle's own scheduler counts 24 hours from the *last* check, so the check
/// drifts with whenever the Mac happened to be awake. A fixed wall-clock
/// deadline is easier to reason about and to explain in support: the app
/// checks at 3 PM Pacific, and a Mac that was asleep or off at 3 PM checks as
/// soon as it is back — a launch at 4 PM finds that today's deadline has
/// passed unmet and checks right then.
///
/// "Pacific" is the zone, not a fixed UTC offset, so the deadline stays at 3
/// PM local across daylight-saving changes. Everything here is pure so the
/// CI Swift harness can pin the boundary cases without a Sparkle session.
enum UpdateSchedule {
    static let hour = 15
    static let minute = 0
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The most recent deadline at or before `now`.
    static func lastDeadline(before now: Date) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
        if today <= now { return today }
        return calendar.date(byAdding: .day, value: -1, to: today)!
    }

    /// The first deadline strictly after `now`.
    static func nextDeadline(after now: Date) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// A check is due when no check has ever run on this schedule, or the last
    /// one ran before the most recent deadline — i.e. a deadline has passed
    /// since, whether the app was running at the time or not.
    static func isCheckDue(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        return lastCheck < lastDeadline(before: now)
    }
}
