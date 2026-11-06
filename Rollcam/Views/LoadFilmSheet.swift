import SwiftUI

struct LoadFilmSheet: View {
    @EnvironmentObject private var store: RollStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.dateStampDefault) private var dateStampDefault = true
    @State private var capacity = 24
    @State private var dateStamp = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Exposures", selection: $capacity) {
                        Text("24 exposures").tag(24)
                        Text("36 exposures").tag(36)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("You won't see a single photo until the whole roll is developed.")
                }
                Section {
                    Toggle("Orange date stamp", isOn: $dateStamp)
                }
            }
            .navigationTitle("Load film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Load") {
                        store.loadFilm(capacity: capacity, dateStamp: dateStamp)
                        Haptics.clunk()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { dateStamp = dateStampDefault }
        }
    }
}
