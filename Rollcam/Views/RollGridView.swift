import SwiftUI

struct RollGridView: View {
    let rollID: UUID

    @EnvironmentObject private var store: RollStore
    @State private var viewer: ViewerSelection?
    @State private var saving = false
    @State private var message: String?

    struct ViewerSelection: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var body: some View {
        let roll = store.roll(rollID)
        let urls = roll.map { store.printURLs(for: $0) } ?? []
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    Button { viewer = ViewerSelection(index: index) } label: {
                        ThumbnailImage(url: store.thumbnailURL(forPrint: url))
                            .aspectRatio(3 / 2, contentMode: .fit)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .navigationTitle(roll.map { $0.createdAt.formatted(.dateTime.day().month(.abbreviated)) } ?? "Roll")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !urls.isEmpty {
                    ShareLink(items: urls) { Image(systemName: "square.and.arrow.up") }
                    Button {
                        Task { await saveAll(urls) }
                    } label: {
                        if saving { ProgressView() } else { Image(systemName: "square.and.arrow.down.on.square") }
                    }
                    .disabled(saving)
                    .accessibilityLabel("Save all to Photos")
                }
            }
        }
        .fullScreenCover(item: $viewer) { selection in
            PhotoViewer(urls: urls, startIndex: selection.index)
        }
        .alert("Rollcam", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func saveAll(_ urls: [URL]) async {
        saving = true
        defer { saving = false }
        do {
            try await PhotoExporter.saveToPhotos(urls)
            Haptics.success()
            message = "Saved \(urls.count) photos to Photos."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Loads a developed thumbnail off the main thread.
struct ThumbnailImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        }
    }
}
