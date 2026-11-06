import SwiftUI

struct PhotoViewer: View {
    let urls: [URL]
    @State var startIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $startIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    FullImage(url: url).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).padding(12)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                Spacer()
                Text("\(startIndex + 1) / \(urls.count)")
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                Spacer()
                if urls.indices.contains(startIndex) {
                    ShareLink(item: urls[startIndex]) {
                        Image(systemName: "square.and.arrow.up").font(.headline).padding(12)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal)
        }
        .statusBarHidden()
    }
}

private struct FullImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
        }
        .onDisappear { image = nil }
    }
}
