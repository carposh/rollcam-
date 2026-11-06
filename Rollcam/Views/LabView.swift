import SwiftUI

struct LabView: View {
    @EnvironmentObject private var store: RollStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: Roll?

    var body: some View {
        NavigationStack {
            List {
                if !store.labRolls.isEmpty {
                    Section("At the lab") {
                        ForEach(store.labRolls) { roll in
                            AtLabRow(roll: roll, progress: store.printing[roll.id])
                        }
                    }
                }
                if !store.developedRolls.isEmpty {
                    Section("Developed") {
                        ForEach(store.developedRolls) { roll in
                            NavigationLink(value: roll.id) { DevelopedRow(roll: roll) }
                                .swipeActions {
                                    Button(role: .destructive) { pendingDelete = roll } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .overlay {
                if store.labRolls.isEmpty && store.developedRolls.isEmpty {
                    ContentUnavailableView("No rolls yet", systemImage: "film",
                                           description: Text("Finish a roll and send it to the lab."))
                }
            }
            .navigationTitle("Lab")
            .navigationDestination(for: UUID.self) { RollGridView(rollID: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete this roll?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete roll", role: .destructive) {
                    if let roll = pendingDelete { store.delete(roll) }
                    pendingDelete = nil
                }
            } message: {
                Text("Photos you've already saved to Photos stay there.")
            }
            .refreshable { store.refresh(reschedule: true) }
        }
    }
}

private struct AtLabRow: View {
    let roll: Roll
    let progress: Double?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(roll.frames.count) exposures")
                    .font(.headline)
                if let progress {
                    ProgressView(value: progress) { Text("Printing…").font(.caption) }
                } else if let ticket = roll.lab {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let left = LabClock.estimatedRemaining(ticket)
                        Text(left > 0 ? "Ready in \(LabClock.format(left))" : "Coming out of the developer…")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if ticket.tamperCount > 0 {
                        Label("The lab noticed the clock going backwards. Only real time counts.", systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                if roll.discardedExposures > 0 {
                    Text("Developed early · \(roll.discardedExposures) unused shots discarded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DevelopedRow: View {
    @EnvironmentObject private var store: RollStore
    let roll: Roll

    var body: some View {
        HStack(spacing: 14) {
            let first = store.printURLs(for: roll).first
            ThumbnailImage(url: first.map { store.thumbnailURL(forPrint: $0) })
                .frame(width: 66, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(roll.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.headline)
                Text("\(roll.frames.count) photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
