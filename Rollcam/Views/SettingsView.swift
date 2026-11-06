import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.developSeconds) private var developSeconds = DevelopDuration.oneDay.rawValue
    @AppStorage(SettingsKey.dateStampDefault) private var dateStampDefault = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Developing time", selection: $developSeconds) {
                        ForEach(DevelopDuration.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("Lab")
                } footer: {
                    Text("Applies to the next roll you send. Rolls already at the lab keep their time.")
                }
                Section {
                    Toggle("Date stamp on new rolls", isOn: $dateStampDefault)
                }
                Section("How the lab works") {
                    Text("Photos are sealed and encrypted inside Rollcam until they're developed. They never appear in your Photos library unless you save them.")
                    Text("Developing time is measured with the phone's internal clock. Changing the date in Settings won't speed it up, and turning the clock back is detected.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
