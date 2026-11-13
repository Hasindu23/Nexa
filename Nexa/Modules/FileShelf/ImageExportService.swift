import AppKit
import ImageIO
import UniformTypeIdentifiers
import Combine

@MainActor final class ImageExportService: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var result: URL?
    @Published var error: String?
    var activity: ((LiveActivity.State, String) -> Void)?
    private var worker: Task<URL, Error>?
    func chooseOutput(for source: URL, type: UTType) {
        guard !busy else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "-export." + (type == .jpeg ? "jpg" : "png")
        panel.message = "Export a new image. Your original stays unchanged. Choose a new filename."
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            self?.export(source: source, destination: destination, type: type)
        }
    }
    func export(source: URL, destination: URL, type: UTType) {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        activity?(.active, "Exporting \(source.lastPathComponent) to \(type == .jpeg ? "JPEG" : "PNG")")
        let work = Task.detached(priority: .userInitiated) { try ImageExport.write(source: source, destination: destination, type: type); return destination }
        worker = work
        Task { [weak self] in
            do { let url = try await work.value; self?.result = url; self?.activity?(.completed, "Saved \(url.lastPathComponent). Original unchanged.") }
            catch is CancellationError { self?.activity?(.dismissed, "Export canceled before saving") }
            catch { self?.error = error.localizedDescription; self?.activity?(.failed, error.localizedDescription) }
            self?.busy = false; self?.worker = nil
        }
    }
    func wait() async { _ = try? await worker?.value }
    func cancel() { worker?.cancel() }
}

enum ImageExport {
    static func write(source: URL, destination: URL, type: UTType) throws {
        guard type == .png || type == .jpeg, source.isFileURL, destination.isFileURL,
              source.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else { throw NexaError.message("Choose a different filename for the exported image.") }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NexaError.message("A file already uses that name. Choose a new name to preserve both files.") }
        try Task.checkCancellation()
        guard let input = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 40_000_000 else {
            throw NexaError.message("Choose a supported image up to 40 megapixels. Nexa does not resize the original.")
        }
        guard let image = CGImageSourceCreateImageAtIndex(input, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw NexaError.message("This image could not be decoded.") }
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw NexaError.message("This image format is unavailable.") }
        var exported = image
        if type == .jpeg, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            if let flattened = context.makeImage() { exported = flattened }
        }
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        if let orientation = properties[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(output, exported, options as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw NexaError.message("The image export could not be completed.") }
        try Task.checkCancellation()
        // The exclusive write fails if another process creates the name meanwhile.
        try (data as Data).write(to: destination, options: .withoutOverwriting)
    }
}
