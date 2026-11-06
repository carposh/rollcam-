import Photos

enum PhotoExporter {
    enum ExportError: LocalizedError {
        case denied
        var errorDescription: String? { "Rollcam isn't allowed to add photos. Turn it on in Settings › Rollcam › Photos." }
    }

    static func saveToPhotos(_ urls: [URL]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            for url in urls {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        }
    }
}
