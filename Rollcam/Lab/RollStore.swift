import Combine
import Foundation

@MainActor
final class RollStore: ObservableObject {
    @Published private(set) var rolls: [Roll] = []
    /// Rolls currently being printed, with progress 0...1.
    @Published private(set) var printing: [UUID: Double] = [:]
    @Published var lastError: String?

    private let vault = Vault.shared
    private let fm = FileManager.default
    private var ticker: AnyCancellable?

    init() {
        load()
        refresh(reschedule: true)
        ticker = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    // MARK: - Queries

    var activeRoll: Roll? { rolls.first { $0.status == .loaded } }

    var labRolls: [Roll] {
        rolls.filter { $0.status == .atLab }
            .sorted { ($0.lab?.sentAt ?? .distantPast) > ($1.lab?.sentAt ?? .distantPast) }
    }

    var developedRolls: [Roll] {
        rolls.filter { $0.status == .developed }
            .sorted { ($0.developedAt ?? .distantPast) > ($1.developedAt ?? .distantPast) }
    }

    func roll(_ id: UUID) -> Roll? { rolls.first { $0.id == id } }

    func printURLs(for roll: Roll) -> [URL] {
        roll.frames.indices.map { printURL(roll.id, index: $0) }.filter { fm.fileExists(atPath: $0.path) }
    }

    func thumbnailURL(forPrint url: URL) -> URL {
        url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
    }

    // MARK: - Shooting

    func loadFilm(capacity: Int, dateStamp: Bool) {
        guard activeRoll == nil else { return }
        rolls.append(Roll(id: UUID(), capacity: capacity, createdAt: Date(), dateStamp: dateStamp))
        save()
    }

    func markWound() {
        guard var roll = activeRoll, !roll.isWound, !roll.isFull else { return }
        roll.isWound = true
        replace(roll)
        save()
    }

    /// Seals a frame straight into the vault. It is never decoded or shown until developed.
    func expose(_ data: Data) {
        guard var roll = activeRoll, roll.isWound, !roll.isFull else { return }
        let frame = Frame(id: UUID(), capturedAt: Date())
        do {
            let url = latentURL(roll.id, frame.id)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try vault.seal(data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            roll.frames.append(frame)
            roll.isWound = false
            replace(roll)
            save()
        } catch {
            lastError = "That frame didn't make it onto the film. Try again."
        }
    }

    /// Sends the active roll to the lab. Unused exposures are thrown away.
    func sendToLab() {
        guard var roll = activeRoll else { return }
        guard !roll.frames.isEmpty else {
            delete(roll)
            return
        }
        let stored = UserDefaults.standard.integer(forKey: SettingsKey.developSeconds)
        let duration = DevelopDuration(rawValue: stored)?.seconds ?? DevelopDuration.oneDay.seconds
        roll.discardedExposures = roll.remaining
        roll.isWound = false
        roll.status = .atLab
        roll.lab = LabClock.newTicket(duration: duration)
        replace(roll)
        save()

        let id = roll.id, count = roll.frames.count
        Notifier.requestAuthorization {
            Notifier.scheduleDeveloped(rollID: id, frames: count, after: duration)
        }
    }

    func delete(_ roll: Roll) {
        Notifier.cancel(rollID: roll.id)
        try? fm.removeItem(at: directory(roll.id))
        rolls.removeAll { $0.id == roll.id }
        save()
    }

    // MARK: - The lab

    /// Credits elapsed time to every roll at the lab and prints the ones that are ready.
    func refresh(reschedule: Bool = false) {
        var changed = false
        for index in rolls.indices where rolls[index].status == .atLab {
            guard var ticket = rolls[index].lab else { continue }
            let tampered = LabClock.advance(&ticket)
            rolls[index].lab = ticket
            changed = true
            let roll = rolls[index]
            if ticket.isReady {
                startPrinting(roll)
            } else if reschedule || tampered {
                Notifier.scheduleDeveloped(rollID: roll.id, frames: roll.frames.count, after: ticket.remaining)
            }
        }
        if changed { save() }
    }

    private func startPrinting(_ roll: Roll) {
        guard printing[roll.id] == nil else { return }
        printing[roll.id] = 0

        struct Job {
            let latent: URL
            let output: URL
            let thumb: URL
            let options: FilmLab.Options
        }
        let jobs: [Job] = roll.frames.enumerated().map { index, frame in
            let output = printURL(roll.id, index: index)
            return Job(
                latent: latentURL(roll.id, frame.id),
                output: output,
                thumb: thumbnailURL(forPrint: output),
                options: FilmLab.Options(dateStamp: roll.dateStamp, capturedAt: frame.capturedAt, seed: Self.seed(frame.id))
            )
        }
        let vault = self.vault
        let rollID = roll.id

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            for (index, job) in jobs.enumerated() {
                autoreleasepool {
                    guard let sealed = try? Data(contentsOf: job.latent),
                          let original = try? vault.open(sealed),
                          let developed = FilmLab.develop(original, options: job.options) else { return }
                    try? fm.createDirectory(at: job.output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? fm.createDirectory(at: job.thumb.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? developed.write(to: job.output, options: .atomic)
                    FilmLab.writeThumbnail(from: job.output, to: job.thumb)
                }
                let progress = Double(index + 1) / Double(max(1, jobs.count))
                await MainActor.run { self.printing[rollID] = progress }
            }
            await MainActor.run { self.finishPrinting(rollID) }
        }
    }

    private func finishPrinting(_ id: UUID) {
        printing[id] = nil
        guard var roll = roll(id) else { return }
        roll.status = .developed
        roll.developedAt = Date()
        replace(roll)
        save()
        try? fm.removeItem(at: directory(id).appendingPathComponent("latent", isDirectory: true))
    }

    // MARK: - Files

    private var indexURL: URL { vault.root.appendingPathComponent("rolls.json") }

    private func directory(_ id: UUID) -> URL {
        vault.root.appendingPathComponent("rolls", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func latentURL(_ rollID: UUID, _ frameID: UUID) -> URL {
        directory(rollID).appendingPathComponent("latent", isDirectory: true).appendingPathComponent("\(frameID.uuidString).latent")
    }

    private func printURL(_ rollID: UUID, index: Int) -> URL {
        directory(rollID).appendingPathComponent("prints", isDirectory: true)
            .appendingPathComponent(String(format: "Rollcam-%02d.jpg", index + 1))
    }

    private func replace(_ roll: Roll) {
        if let index = rolls.firstIndex(where: { $0.id == roll.id }) { rolls[index] = roll }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        rolls = (try? decoder.decode([Roll].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(rolls) else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func seed(_ id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.loadUnaligned(as: UInt64.self) }
    }
}
