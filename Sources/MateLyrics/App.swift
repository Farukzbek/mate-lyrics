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
        Divider()
        Toggle("Kilit ekranında göster", isOn: $settings.lockScreenEnabled)
        Picker("Kilit ekranı görünümü", selection: $settings.lockScreenLayout) {
            ForEach(LockScreenLayout.allCases) { Text($0.title).tag($0) }
        }
        Picker("Kilit ekranında taraf", selection: $settings.lockScreenSide) {
            ForEach(LockScreenSide.allCases) { Text($0.title).tag($0) }
        }
        .disabled(settings.lockScreenLayout != .side)
        Picker("Kilit ekranında yükseklik", selection: $settings.lockScreenHeight) {
            Text("Yukarıda").tag(0.62)
            Text("Ortada").tag(0.45)
            Text("Aşağıda").tag(0.3)
        }
        .disabled(settings.lockScreenLayout == .subtitle)
        Button("Kilit ekranı önizlemesi (5 sn)") { NotificationCenter.default.post(name: .lockScreenPreview, object: nil) }
        Toggle("Girişte otomatik başlat", isOn: Binding(get: { settings.launchAtLogin },
                                                        set: { settings.launchAtLogin = $0 }))
        Divider()
        Button("Konumu sıfırla") { NotificationCenter.default.post(name: .resetPosition, object: nil) }
        Button("Çıkış") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}


extension Notification.Name {
    static let resetPosition = Notification.Name("mate.resetPosition")
    static let lockScreenPreview = Notification.Name("mate.lockScreenPreview")
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
    var isLocked: () -> Bool = { false }

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
            if isLocked() {
                mode = .none // kilitli: taşıma/boyutlandırma yok, tıklamalar düğmelere gider
            } else if inResizeZone(event.locationInWindow) {
                mode = .resize
                startScale = getScale()
                setResizing(true)
                return
            } else {
                mode = .pending
            }
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
                // Taşıma başladı: basılı düğmeyi pencere dışında "bırakılmış" sayarak iptal et
                // (yoksa düğme basılı/soluk kalır; dışarıda bırakılan düğme tetiklenmez).
                if let cancel = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000),
                                                   modifierFlags: [], timestamp: event.timestamp,
                                                   windowNumber: windowNumber, context: nil,
                                                   eventNumber: 0, clickCount: 1, pressure: 0) {
                    super.sendEvent(cancel)
                }
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
    private var lockScreen: LockScreenController!
    private var bag = Set<AnyCancellable>()
    private var anchoringTop = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let root = WidgetView(spotify: spotify, lyrics: lyrics, artwork: artwork, settings: settings)
            .fixedSize()
            // Pencere içerikten büyükken (kapanma animasyonu sürerken) içerik sol üstte dursun, ortaya kaymasın
            // min 0: içerik pencereden büyük olduğu ilk anda (büyüme öncesi) çerçeve içerikle büyüyüp
            // ortalanmasın; içerik sol üstte kalsın, taşan kısım pencere büyüyene kadar kesilsin.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        let host = NSHostingView(rootView: root)
        // İçerik boyutu değişince (söz aç/kapa, görünüm, ölçek) pencere tam içerik kadar olsun;
        // sol üst köşe sabit kalsın. Böylece köşe tutamağı hep pencerenin sağ alt köşesinde.
        // onChange görünüm güncellemesi bittikten sonra çalışır; pencereyi hemen boyutlandırmak güvenli
        AppDelegate.contentSizeChanged = { [weak self] size in self?.resize(to: size) }
        host.sizingOptions = [] // pencereyi WidgetView'un bildirdiği boyuta göre biz boyutlandırıyoruz

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
        panel.isLocked = { [unowned self] in settings.lockPosition }
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        restorePosition()

        if CommandLine.arguments.contains("--debug-size") {
            NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: panel)
                .sink { [weak self] _ in
                    guard let self else { return }
                    print("  pencere boyutu değişti →", self.panel.frame.size, "applyFrame içinde mi:", self.anchoringTop)
                    if !self.anchoringTop { Thread.callStackSymbols.prefix(14).forEach { print("     ", $0) } }
                }.store(in: &bag)
        }
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in self?.savePosition() }.store(in: &bag)
        lockScreen = LockScreenController(spotify: spotify, lyrics: lyrics, artwork: artwork, settings: settings)
        NotificationCenter.default.publisher(for: .lockScreenPreview)
            .sink { [weak self] _ in self?.lockScreen.preview() }.store(in: &bag)
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
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--test-lockscreen"), i + 1 < CommandLine.arguments.count {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                print("SkyLight kilit ekranı katmanı:", lockScreen.isAvailable ? "bulundu" : "BULUNAMADI")
                settings.background = .transparent
                let steps: [(String, LockScreenLayout, Bool)] = [
                    ("lock-altyazi", .subtitle, false), ("lock-altyazi-kapali", .subtitle, true),
                    ("lock-yan", .side, false), ("lock-yan-kucuk", .side, true), ("lock-kart", .card, false),
                ]
                var rest = steps[...]
                @MainActor func next() {
                    guard let (name, layout, collapsed) = rest.popFirst() else { exit(0) }
                    settings.lockScreenLayout = layout
                    settings.lockScreenCollapsed = collapsed
                    if layout == .subtitle {
                        // Altyazı sadece senkron sözlerde görünür: örnek satırlar (her saniye bir satır)
                        lyrics.debugSet(.synced((0..<900).map {
                            LyricLine(id: $0, time: Double($0), text: "Örnek senkron söz satırı \($0) burada akıyor")
                        }))
                    }
                    lockScreen.preview(seconds: 30)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in MainActor.assumeIsolated {
                        lockScreen.snapshot(to: dir.appendingPathComponent(name + ".png"))
                        next()
                    } }
                }
                next()
            }
        }
        if CommandLine.arguments.contains("--test-sizes") {
            // Her görünüm × arka plan için widget boyutu: arka plan değişince boyut değişmemeli
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                let combos = WidgetStyle.allCases.flatMap { st in BackgroundStyle.allCases.map { (st, $0) } }
                var rest = combos[...]
                @MainActor func next() {
                    guard let (st, bg) = rest.popFirst() else { exit(0) }
                    settings.style = st
                    settings.background = bg
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in MainActor.assumeIsolated {
                        print(st.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0),
                              bg.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0), lastContentSize)
                        next()
                    } }
                }
                next()
            }
        }
        if CommandLine.arguments.contains("--test-jitter") {
            // Söz paneli açılıp kapanırken kartın sol üst köşesi ekranda kımıldıyor mu? Her 0.08 sn ölç.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                @MainActor func cardTopLeft() -> String {
                    guard let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return "-" }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    var minX = Int.max, minY = Int.max
                    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                        for x in stride(from: 0, to: rep.pixelsWide, by: 2) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                            minX = min(minX, x); minY = min(minY, y)
                        }
                    }
                    let scale = CGFloat(rep.pixelsWide) / v.bounds.width
                    // ekran koordinatı: pencere sol üst + kart ofseti
                    let sx = panel.frame.minX + CGFloat(minX) / scale
                    let sy = panel.frame.maxY - CGFloat(minY) / scale
                    return String(format: "pencere x=%.0f üst=%.0f %.0fx%.0f | kart sol-üst ekranda (%.0f, %.0f)",
                                  panel.frame.minX, panel.frame.maxY, panel.frame.width, panel.frame.height, sx, sy)
                }
                let synced = LyricsState.synced((0..<300).map { LyricLine(id: $0, time: Double($0), text: "Satır \($0)") })
                let plan: [(String, LyricsState)] = [("SÖZ YOK'A GEÇİŞ", .notFound), ("SÖZ VAR'A GEÇİŞ", synced)]
                var rest = plan[...]
                lyrics.debugSet(synced)
                @MainActor func next() {
                    guard let (name, state) = rest.popFirst() else { exit(0) }
                    print("==", name)
                    lyrics.debugSet(state)
                    var t = 0
                    let start = Date()
                    @MainActor func sample() {
                        print(String(format: "t=%.3f ", Date().timeIntervalSince(start)), cardTopLeft())
                        t += 1
                        if t <= 20 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { MainActor.assumeIsolated { sample() } }
                        } else { next() }
                    }
                    sample()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { next() } }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--test-autohide"), i + 1 < CommandLine.arguments.count {
            // Söz yok → panel kapanmalı; söz gelince → açılmalı. Pencere genişliği ve görüntüyle kontrol.
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                @MainActor func step(_ name: String, _ state: LyricsState, then: @escaping @MainActor () -> Void) {
                    lyrics.debugSet(state)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in MainActor.assumeIsolated {
                        print(name, "pencere:", panel.frame.size, "sözler açık tercihi:", settings.showLyrics)
                        if let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                            v.cacheDisplay(in: v.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?
                                .write(to: dir.appendingPathComponent("autohide-\(name).png"))
                        }
                        then()
                    } }
                }
                step("1-sozler-var", .synced([LyricLine(id: 0, time: 0, text: "Örnek satır")])) {
                    self.lyrics.debugSet(.notFound)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [self] in MainActor.assumeIsolated {
                        if let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                            v.cacheDisplay(in: v.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?
                                .write(to: dir.appendingPathComponent("autohide-1b-kapaniyor.png"))
                        }
                    } }
                    step("2-soz-yok", .notFound) {
                        step("3-yukleniyor", .loading) {
                            step("4-sozler-geri-geldi", .plain(["Düz söz"])) { exit(0) }
                        }
                    }
                }
            }
        }
        #endif
        if CommandLine.arguments.contains("--test-scale") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                @MainActor func r(_ l: String) { print(l, "scale:", settings.scale, "pencere:", panel.frame.size, "içerik:", lastContentSize) }
                r("başlangıç")
                settings.scale = 1.4
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in MainActor.assumeIsolated {
                    r("1.4 sonrası")
                    settings.scale = 0.7
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { r("0.7 sonrası"); exit(0) } }
                } }
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
            let fit = lastContentSize
            print(label, "scale:", String(format: "%.2f", settings.scale), "konum:", panel.frame.origin, "pencere:", panel.frame.size,
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
    static var contentSizeChanged: ((CGSize) -> Void)?
    private var pendingShrink: DispatchWorkItem?

    private var lastContentSize = CGSize.zero

    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastContentSize = size
        pendingShrink?.cancel()
        pendingShrink = nil
        guard panel.frame.size != size else { return }
        // Büyürken hemen; küçülürken (söz paneli kapanırken) animasyon bitince küçül, yoksa panel yarıda kesilir.
        // Köşeden elle boyutlandırırken gecikme olmasın.
        let shrinking = size.width < panel.frame.width || size.height < panel.frame.height
        if CommandLine.arguments.contains("--debug-size") { print("resize", size, "küçülme:", shrinking, "elle:", settings.isResizing) }
        if shrinking && !settings.isResizing {
            let work = DispatchWorkItem { [weak self] in self?.applyFrame(size) }
            pendingShrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            return
        }
        applyFrame(size)
    }

    private func applyFrame(_ size: CGSize) {
        guard panel.frame.size != size else { return }
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
