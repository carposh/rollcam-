import Foundation
import Darwin

/// Light-weight anti-cheat for developing times.
///
/// Within one boot session the monotonic clock (which keeps counting while the phone sleeps
/// and cannot be changed by the user) is the source of truth, so moving the date in Settings
/// gains nothing. Across a reboot we fall back to the wall clock, measured from the latest
/// time we ever saw, so winding the clock backwards and forwards again cannot be re-credited.
enum LabClock {
    /// Clock drift we ignore (NTP corrections, time-zone travel does not affect Date).
    static let tolerance: TimeInterval = 120

    static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    static func bootSessionID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    static func newTicket(duration: TimeInterval, now: Date = Date()) -> LabTicket {
        LabTicket(
            sentAt: now,
            duration: duration,
            credited: 0,
            lastWall: now,
            lastMonotonic: monotonicNow(),
            bootSession: bootSessionID(),
            highWater: now
        )
    }

    /// Credits elapsed real time to the ticket. Returns true if the clock was seen going backwards.
    @discardableResult
    static func advance(
        _ ticket: inout LabTicket,
        now: Date = Date(),
        monotonic: TimeInterval = monotonicNow(),
        bootSession: String = bootSessionID()
    ) -> Bool {
        var tampered = false
        let wallDelta = now.timeIntervalSince(ticket.lastWall)
        let monoDelta = monotonic - ticket.lastMonotonic
        let sameBoot = monoDelta >= 0 && (bootSession.isEmpty || bootSession == ticket.bootSession)

        if sameBoot {
            ticket.credited += monoDelta
            if wallDelta < monoDelta - tolerance { tampered = true }
        } else {
            // Rebooted: only credit wall time beyond the furthest point we have already seen.
            let gained = now.timeIntervalSince(ticket.highWater)
            if gained > 0 { ticket.credited += gained }
        }

        // The device clock reads earlier than a time we have already observed (including "send to lab").
        if now < ticket.highWater.addingTimeInterval(-tolerance) || now < ticket.sentAt.addingTimeInterval(-tolerance) {
            tampered = true
        }

        if tampered {
            ticket.tamperCount += 1
            ticket.lastTamperAt = now
        }
        ticket.lastWall = now
        ticket.lastMonotonic = monotonic
        ticket.bootSession = bootSession
        if now > ticket.highWater { ticket.highWater = now }
        ticket.credited = min(ticket.credited, ticket.duration)
        return tampered
    }

    /// Remaining time for display between refreshes.
    static func estimatedRemaining(_ ticket: LabTicket) -> TimeInterval {
        let sinceLast = max(0, monotonicNow() - ticket.lastMonotonic)
        return max(0, ticket.duration - ticket.credited - sinceLast)
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval.rounded(.up)))
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60, sec = s % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}
