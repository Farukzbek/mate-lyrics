import AppKit
import Combine
import SwiftUI

@main
struct MateLyricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Mate Lyrics", systemImage: "music.note.list") {
            MenuContent(settings: delegate.settings, spotify: delegate.spotify)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var settings: Settings
    @ObservedObject var spotify: SpotifyClient

    var body: some View {
        Toggle("Widget'ı göster", isOn: $settings.widgetVisible)
        Divider()
        ContextMenuItems(settings: settings, spotify: spotify)
        Divider()
        Toggle("Masaüstüne sabitle (pencerelerin arkasında)", isOn: $settings.pinToDesktop)
        Toggle("Girişte otomatik başlat", isOn: Binding(get: { settings.launchAtLogin },
                                                        set: { settings.launchAtLogin = $0 }))
        Divider()
        Button("Konumu sıfırla") { NotificationCenter.default.post(name: .resetPosition, object: nil) }
        Button("Çıkış") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// İçeriğin doğal boyutu değişince haber veren hosting view.
final class FittingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((CGSize) -> Void)?
    private var scheduled = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scheduled = false
            onSizeChange?(fittingSize)
        }
    }
}

extension Notification.Name {
    static let resetPosition = Notification.Name("mate.resetPosition")
}

/// Kenarlıksız, şeffaf panel. Taşıma ve köşeden boyutlandırmayı kendisi yönetir:
/// sağ alt köşede başlayan sürükleme ölçeği değiştirir, başka yerde başlayan pencereyi taşır.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Kartın pencere kenarına olan boşluğu (WidgetView'daki dış padding).
    static let outerPadding: CGFloat = 30
    var getScale: () -> Double = { 1 }
    var setScale: (Double) -> Void = { _ in }
    var setResizing: (Bool) -> Void = { _ in }

    private enum Mode { case none, pending, move, resize }
    private var mode = Mode.none
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var startScale = 1.0

    private func inResizeZone(_ p: NSPoint) -> Bool {
        // AppKit pencere koordinatı: (0,0) sol alt. Kartın sağ alt köşesindeki 36pt'lik kare.
        let pad = Self.outerPadding
        let x = frame.width - pad
        return p.x > x - 36 && p.x < x + 6 && p.y > pad - 6 && p.y < pad + 36
    }

    override func sendEvent(_ event: NSEvent) {
        let mouse = convertPoint(toScreen: event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            startMouse = mouse
            startOrigin = frame.origin
            if inResizeZone(event.locationInWindow) {
                mode = .resize
                startScale = getScale()
                setResizing(true)
                return
            }
            mode = .pending
        case .leftMouseDragged:
            let now = mouse
            let dx = now.x - startMouse.x, dy = now.y - startMouse.y
            switch mode {
            case .resize:
                let delta = (dx - dy) / 2 // sağa / aşağı = büyüt
                let r = Settings.scaleRange
                setScale(min(max(startScale + delta / 350, r.lowerBound), r.upperBound))
                return
            case .pending where hypot(dx, dy) > 3:
                mode = .move
                fallthrough
            case .move:
                setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
                return
            default:
                break
            }
        case .scrollWheel:
            // İki parmakla kaydırma → sözleri kaydır (fare tekerinde satır başına ~12 pt)
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
            if dy != 0 { MainActor.assumeIsolated { LyricsScroll.shared.scroll(by: dy) } }
        case .leftMouseUp:
            let was = mode
            mode = .none
            if was == .resize { setResizing(false); return }
            if was == .move { return } // taşıma bitti; altta kalan butona tıklama sayılmasın
        default:
            break
        }
        super.sendEvent(event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    let spotify = SpotifyClient()
    let lyrics = LyricsService()
    let artwork = ArtworkStore()

    private var panel: WidgetPanel!
    private var bag = Set<AnyCancellable>()
    private var anchoringTop = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let root = WidgetView(spotify: spotify, lyrics: lyrics, artwork: artwork, settings: settings)
            .fixedSize()
        let host = FittingHostingView(rootView: root)
        // İçerik boyutu değişince (söz aç/kapa, görünüm, ölçek) pencere tam içerik kadar olsun;
        // sol üst köşe sabit kalsın. Böylece köşe tutamağı hep pencerenin sağ alt köşesinde.
        host.onSizeChange = { [weak self] size in self?.resize(to: size) }
        host.sizingOptions = [.intrinsicContentSize] // min/max kısıtı yok: pencereyi biz boyutlandırıyoruz

        panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        // Şeffaf pikseller (yuvarlak köşe, şeffaf moddaki kutu araları) tıklamayı masaüstüne kaçırmasın
        panel.ignoresMouseEvents = false
        panel.getScale = { [unowned self] in settings.scale }
        panel.setScale = { [unowned self] in settings.scale = $0 }
        panel.setResizing = { [unowned self] in settings.isResizing = $0 }
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        restorePosition()
        resize(to: host.fittingSize)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in self?.savePosition() }.store(in: &bag)
        NotificationCenter.default.publisher(for: .resetPosition)
            .sink { [weak self] _ in self?.resetPosition() }.store(in: &bag)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }.store(in: &bag)

        applySettings()

        if let i = CommandLine.arguments.firstIndex(of: "--test-control"), i + 1 < CommandLine.arguments.count {
            let cmd = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                @MainActor func state() -> String {
                    String(format: "%@ @ %.1f sn", spotify.track?.name ?? "-", spotify.currentPosition())
                }
                print("önce:", state())
                cmd == "next" ? spotify.next() : spotify.previous()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    MainActor.assumeIsolated { print("sonra:", state()) }
                    exit(0)
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--test-scroll"), i + 1 < CommandLine.arguments.count {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.runScrollTest(dir) }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--test-click"), i + 2 < CommandLine.arguments.count,
           let x = Double(CommandLine.arguments[i + 1]), let yTop = Double(CommandLine.arguments[i + 2]) {
            // (x, yTop): pencerenin sol üstüne göre nokta
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                let p = NSPoint(x: x, y: panel.frame.height - yTop)
                print(String(format: "önce: %@ @ %.1f sn", spotify.track?.name ?? "-", spotify.currentPosition()))
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    panel.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
                                                       windowNumber: panel.windowNumber, context: nil,
                                                       eventNumber: 0, clickCount: 1, pressure: 1)!)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MainActor.assumeIsolated {
                        print(String(format: "sonra: %@ @ %.1f sn", self.spotify.track?.name ?? "-", self.spotify.currentPosition()))
                    }
                    exit(0)
                }
            }
        }
        if CommandLine.arguments.contains("--test-drag") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.runDragTest() }
        }
        if CommandLine.arguments.contains("--bench") {
            DispatchQueue.main.async { runLyricsBench() }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.writeSnapshots(to: dir) }
        }
    }

    /// Geliştirme için: her görünümü PNG olarak kaydeder (ekran izni gerektirmez).
    /// NSHostingView ile çizilir, yani ekrandakiyle aynı sonuç (ImageRenderer kırpmayı düzgün yapmıyor).
    private func writeSnapshots(to dir: URL) {
        let combos = WidgetStyle.allCases.flatMap { st in
            [BackgroundStyle.artwork, .dark, .transparent].map { (st, $0) }
        }
        var remaining = combos[...]
        func next() {
            guard let (style, bg) = remaining.popFirst() else { NSApp.terminate(nil); return }
            settings.style = style
            settings.background = bg
            settings.showLyrics = true
            let view = WidgetView(spotify: spotify, lyrics: lyrics, artwork: artwork, settings: settings)
                .fixedSize().background(Color(white: 0.5))
            let host = NSHostingView(rootView: view)
            host.frame.size = host.fittingSize
            let win = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.contentView = host
            win.orderBack(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: dir.appendingPathComponent("\(style.rawValue)-\(bg.rawValue).png"))
                }
                win.orderOut(nil)
                next()
            }
        }
        next()
    }

    /// Geliştirme: iki parmak kaydırmayı sahte olaylarla dener, öncesi/sonrası görüntü kaydeder.
    private func runScrollTest(_ dir: URL) {
        let sc = LyricsScroll.shared
        func shot(_ name: String) {
            guard let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        func report(_ l: String) { print(l, "offset:", sc.offset, "sabit satır:", sc.frozenActive ?? -1, "aralık:", sc.range) }
        report("önce"); shot("scroll-0-once.png")
        for _ in 0..<8 {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -30, wheel2: 0, wheel3: 0)!
            cg.location = CGPoint(x: panel.frame.midX, y: NSScreen.main!.frame.height - panel.frame.midY)
            panel.sendEvent(NSEvent(cgEvent: cg)!)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        report("aşağı kaydırma sonrası"); shot("scroll-1-kaydirildi.png")
        for _ in 0..<200 {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 60, wheel2: 0, wheel3: 0)!
            panel.sendEvent(NSEvent(cgEvent: cg)!)
        }
        report("çok yukarı kaydırma (sınır testi)")
        RunLoop.current.run(until: Date().addingTimeInterval(LyricsScroll.idleReturn + 1.2))
        report("3 sn bekleme sonrası"); shot("scroll-2-geri-dondu.png")
        exit(0)
    }

    /// Geliştirme: köşeden boyutlandırma ve taşımayı sahte fare olaylarıyla dener.
    private func runDragTest() {
        func send(_ type: NSEvent.EventType, _ p: NSPoint) {
            let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
                                       windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 1)!
            panel.sendEvent(e)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        func report(_ label: String) {
            let fit = panel.contentView!.fittingSize
            print(label, "scale:", String(format: "%.2f", settings.scale), "pencere:", panel.frame.size,
                  "içerik:", fit, abs(panel.frame.width - fit.width) <= 1 && abs(panel.frame.height - fit.height) <= 1 ? "✓" : "✗ UYUMSUZ")
        }
        report("başlangıç")
        // Kartın sağ alt köşesi: (genişlik - 30, 30) pencere koordinatında; tutamak biraz içeride
        let w = panel.frame.width
        var p = NSPoint(x: w - WidgetPanel.outerPadding - 14, y: WidgetPanel.outerPadding + 14)
        send(.leftMouseDown, p)
        for _ in 0..<5 {
            // Pencere büyüdükçe pencere koordinatı değişir: ekran noktasından geri çevir
            let screen = panel.convertPoint(toScreen: p)
            let target = NSPoint(x: screen.x + 20, y: screen.y - 20)
            p = panel.convertPoint(fromScreen: target)
            send(.leftMouseDragged, p)
        }
        send(.leftMouseUp, p)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        report("köşeden sürükleme sonrası")

        let c = NSPoint(x: 120, y: panel.frame.height - 120)
        send(.leftMouseDown, c)
        let sc = panel.convertPoint(toScreen: c)
        send(.leftMouseDragged, panel.convertPoint(fromScreen: NSPoint(x: sc.x + 50, y: sc.y + 10)))
        send(.leftMouseUp, panel.convertPoint(fromScreen: NSPoint(x: sc.x + 50, y: sc.y + 10)))
        report("ortadan sürükleme sonrası")

        // Küçültme: köşeden sol-yukarı sürükle
        p = NSPoint(x: panel.frame.width - WidgetPanel.outerPadding - 14, y: WidgetPanel.outerPadding + 14)
        send(.leftMouseDown, p)
        for _ in 0..<6 {
            let screen = panel.convertPoint(toScreen: p)
            p = panel.convertPoint(fromScreen: NSPoint(x: screen.x - 25, y: screen.y + 25))
            send(.leftMouseDragged, p)
        }
        send(.leftMouseUp, p)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        report("küçültme sonrası")
        exit(0)
    }

    private func applySettings() {
        panel.level = settings.pinToDesktop
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            : .floating
        if settings.widgetVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    // MARK: - Konum

    private func savePosition() {
        guard !anchoringTop else { return }
        UserDefaults.standard.set(panel.frame.minX, forKey: "posX")
        UserDefaults.standard.set(panel.frame.maxY, forKey: "posTop")
    }

    /// İçerik boyutu değişince (söz aç/kapa, görünüm değişimi) pencereyi boyutlandır; sol üst köşe sabit kalsın.
    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0, panel.frame.size != size else { return }
        let top = panel.frame.maxY
        anchoringTop = true
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                       display: true)
        anchoringTop = false
    }

    private func restorePosition() {
        let d = UserDefaults.standard
        if let x = d.object(forKey: "posX") as? Double, let top = d.object(forKey: "posTop") as? Double,
           NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: x + 50, y: top - 50)) }) {
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        } else {
            resetPosition()
        }
    }

    private func resetPosition() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        panel.setFrameTopLeftPoint(NSPoint(x: screen.minX + 40, y: screen.maxY - 40))
        savePosition()
    }
}

// MARK: - Geliştirme: söz satırı değişiminin maliyetini ölçer

private final class BenchModel: ObservableObject { @Published var active = 0 }

private struct BenchView: View {
    @ObservedObject var m: BenchModel
    let lines: [LyricLine]
    var body: some View {
        SyncedLyrics(lines: lines, active: m.active, background: .artwork, s: 1) { _ in }
            .frame(width: 300, height: 360)
    }
}

@MainActor private func runLyricsBench() {
    let lines = (0..<70).map { LyricLine(id: $0, time: Double($0) * 3, text: "Satır \($0) biraz uzunca bir söz cümlesi burada duruyor") }
    let m = BenchModel()
    let host = NSHostingView(rootView: BenchView(m: m, lines: lines))
    host.frame = NSRect(x: 0, y: 0, width: 300, height: 360)
    let win = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    win.contentView = host
    win.orderBack(nil)
    host.layoutSubtreeIfNeeded(); host.display()
    var times: [Double] = []
    for i in 1..<50 {
        let t = CFAbsoluteTimeGetCurrent()
        m.active = i
        RunLoop.current.run(mode: .default, before: Date())
        host.layoutSubtreeIfNeeded()
        host.display()
        CATransaction.flush()
        times.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
    }
    times.sort()
    print(String(format: "satır değişimi: medyan %.1f ms, en kötü %.1f ms", times[times.count / 2], times.last!))
    exit(0)
}
