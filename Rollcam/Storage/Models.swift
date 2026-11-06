import Foundation

enum DevelopDuration: Int, CaseIterable, Identifiable {
    case oneHour = 3_600
    case twelveHours = 43_200
    case oneDay = 86_400
    case threeDays = 259_200

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .oneHour: return "1 hour"
        case .twelveHours: return "12 hours"
        case .oneDay: return "24 hours"
        case .threeDays: return "3 days"
        }
    }
}

enum SettingsKey {
    static let developSeconds = "developSeconds"
    static let dateStampDefault = "dateStampDefault"
}

struct Frame: Codable, Identifiable, Hashable {
    let id: UUID
    let capturedAt: Date
}

enum RollStatus: String, Codable {
    case loaded
    case atLab
    case developed
}

struct Roll: Codable, Identifiable, Hashable {
    let id: UUID
    let capacity: Int
    let createdAt: Date
    var dateStamp: Bool
    var frames: [Frame] = []
    var status: RollStatus = .loaded
    var isWound: Bool = false
    var discardedExposures: Int = 0
    var lab: LabTicket?
    var developedAt: Date?

    var remaining: Int { max(0, capacity - frames.count) }
    var isFull: Bool { frames.count >= capacity }
}

/// Everything the lab needs to decide whether a roll is ready, without trusting the wall clock.
struct LabTicket: Codable, Hashable {
    let sentAt: Date
    let duration: TimeInterval
    /// Seconds of real time the roll has spent at the lab.
    var credited: TimeInterval
    var lastWall: Date
    var lastMonotonic: TimeInterval
    var bootSession: String
    /// The latest wall-clock time ever observed for this roll.
    var highWater: Date
    var tamperCount: Int = 0
    var lastTamperAt: Date?

    var isReady: Bool { credited >= duration }
    var remaining: TimeInterval { max(0, duration - credited) }
}
