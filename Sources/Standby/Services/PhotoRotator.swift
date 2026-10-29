import AppKit
import ImageIO

/// Cycles through the images in a folder for the Photos view and widget.
@MainActor
final class PhotoRotator: ObservableObject {
    @Published private(set) var current: CGImage?
    @Published private(set) var generation = 0
    @Published private(set) var count = 0
    @Published private(set) var isScanning = false

    private var urls: [URL] = []
    private var index = 0
    private var timer: Timer?
    private var configuredKey = ""
    private var interval: TimeInterval = 15

    func configure(folder: String, shuffle: Bool) {
        let path = (folder as NSString).expandingTildeInPath
        let key = "\(path)|\(shuffle)"
        guard key != configuredKey else { return }
        configuredKey = key
        isScanning = true
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) { Self.scan(path) }.value
            guard let self, self.configuredKey == key else { return }
            urls = shuffle ? found.shuffled() : found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            count = urls.count
            index = 0
            isScanning = false
            loadCurrent()
        }
    }

    func start(interval: TimeInterval) {
        self.interval = max(interval, 3)
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func step(_ delta: Int) {
        guard !urls.isEmpty else { return }
        index = ((index + delta) % urls.count + urls.count) % urls.count
        loadCurrent()
        if timer != nil { scheduleTimer() }
    }

    func setPreview(_ image: CGImage?) {
        current = image
        generation += 1
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(1) }
        }
    }

    private func loadCurrent() {
        guard !urls.isEmpty else {
            current = nil
            return
        }
        let url = urls[index]
        let expected = index
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { Self.downsample(url, maxPixel: 3200) }.value
            guard let self, index == expected else { return }
            if let image {
                current = image
                generation += 1
            } else if urls.count > 1 {
                step(1)
            }
        }
    }

    nonisolated static func scan(_ path: String) -> [URL] {
        let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp"]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            out.append(url)
            if out.count >= 5000 { break }
        }
        return out
    }

    nonisolated static func downsample(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
