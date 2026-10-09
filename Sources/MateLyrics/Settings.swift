import AppKit
import SwiftUI
import ServiceManagement

enum WidgetStyle: String, CaseIterable, Identifiable {
    case vinyl, cover, compact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vinyl: "Plak"
        case .cover: "Kapak"
        case .compact: "Kompakt"
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case artwork, glass, dark, transparent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .artwork: "Kapak rengi (Spotify gibi)"
        case .glass: "Cam (şeffaf)"
        case .dark: "Koyu"
        case .transparent: "Şeffaf (ayrı kutular)"
        }
    }
}

enum WidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var scale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1.0
        case .large: 1.25
        }
    }
    var title: String {
        switch self {
        case .small: "Küçük"
        case .medium: "Orta"
        case .large: "Büyük"
        }
    }
}

/// Kullanıcı ayarları (UserDefaults'a kaydedilir).
@MainActor
final class Settings: ObservableObject {
    @AppStorage("style") var style: WidgetStyle = .vinyl
    @AppStorage("background") var background: BackgroundStyle = .artwork
    /// Serbest ölçek (köşeden sürükleyerek veya menüden). 0.6 – 1.8
    @AppStorage("scale") var scale: Double = 1.0
    static let scaleRange: ClosedRange<Double> = 0.6...1.8
    @AppStorage("showLyrics") var showLyrics = true
    @AppStorage("pinToDesktop") var pinToDesktop = true
    @AppStorage("widgetVisible") var widgetVisible = true
    /// Kilitliyken widget taşınamaz ve köşeden boyutlandırılamaz.
    @AppStorage("lockPosition") var lockPosition = false
    @Published var isResizing = false

    // MARK: Şarkı bazında söz kaydırma (LRCLIB zamanlaması tutmazsa elle düzeltmek için)

    private var offsets: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: "lyricOffsets") as? [String: Double] ?? [:] }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "lyricOffsets") }
    }

    func offset(for trackID: String?) -> Double {
        guard let trackID else { return 0 }
        return offsets[trackID] ?? 0
    }

    func adjustOffset(by delta: Double, for trackID: String?) {
        guard let trackID else { return }
        let v = ((offset(for: trackID) + delta) * 100).rounded() / 100
        offsets[trackID] = abs(v) < 0.001 ? nil : v
    }

    func resetOffset(for trackID: String?) {
        guard let trackID else { return }
        offsets[trackID] = nil
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}

/// Kapak görselini indirir ve baskın rengini çıkarır.
@MainActor
final class ArtworkStore: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var color: Color = Color(red: 0.25, green: 0.25, blue: 0.28)
    private var url: URL?
    private var cache: [URL: (NSImage, Color)] = [:]

    func load(_ newURL: URL?) {
        guard newURL != url else { return }
        url = newURL
        guard let newURL else { image = nil; return }
        if let (img, c) = cache[newURL] { image = img; color = c; return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: newURL),
                  let img = NSImage(data: data) else { return }
            let c = Self.dominantColor(img)
            cache[newURL] = (img, c)
            guard url == newURL else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                image = img
                color = c
            }
        }
    }

    /// Ortalama rengi alıp, beyaz yazı okunacak şekilde biraz koyulaştırır ve doygunlaştırır.
    private static func dominantColor(_ image: NSImage) -> Color {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .gray }
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let ns = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, s * 1.4 + 0.1), brightness: min(max(b, 0.35), 0.55))
    }
}
