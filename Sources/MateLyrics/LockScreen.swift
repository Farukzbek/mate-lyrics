import AppKit
import Combine
import SwiftUI

// MARK: - Kilit ekranı katmanı (SkyLight)

/// Pencereyi macOS kilit ekranı katmanına iliştirir.
/// Apple'ın resmi API'si değil (özel SkyLight framework'ü); bir macOS güncellemesiyle bozulabilir.
/// Sembol bulunamazsa sessizce devre dışı kalır, uygulama çökmez.
/// Yöntem: github.com/TechSynth/LockWidget ve boring.notch ile aynı.
@MainActor
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// Kilit ekranındaki bildirim merkezinin katmanı: kilit ekranının üstünde, şifre isteminin altında.
    private static let lockScreenLevel: Int32 = 400

    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var addWindows: AddWindows?

    var isAvailable: Bool { addWindows != nil }

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let pMain = dlsym(handle, "SLSMainConnectionID"),
              let pCreate = dlsym(handle, "SLSSpaceCreate"),
              let pLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let pShow = dlsym(handle, "SLSShowSpaces"),
              let pAdd = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return }

        let main = unsafeBitCast(pMain, to: MainConnection.self)
        let create = unsafeBitCast(pCreate, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(pLevel, to: SpaceSetAbsoluteLevel.self)
        let show = unsafeBitCast(pShow, to: ShowSpaces.self)

        connection = main()
        space = create(connection, 1, 0)
        _ = setLevel(connection, space, Self.lockScreenLevel)
        _ = show(connection, [space] as CFArray)
        addWindows = unsafeBitCast(pAdd, to: AddWindows.self)
    }

    func attach(_ window: NSWindow) {
        _ = addWindows?(connection, space, [Int32(window.windowNumber)] as CFArray, 7)
    }
}

// MARK: - Kilit ekranı penceresi

@MainActor
final class LockScreenController {
    /// Tam kart düzeninde pencere boyutu (kart içinde ortalanır).
    static let cardWindowSize = NSSize(width: 920, height: 480)
    /// Sistem oynatıcısının yarı genişliği + boşluk (yan düzende sözler bunun dışında durur).
    static let systemPlayerClearance: CGFloat = 175

    private let spotify: SpotifyClient
    private let settings: Settings
    private let panel: NSPanel
    private var isLocked = false
    private var previewWork: DispatchWorkItem?
    private var settingsObserver: Any?

    init(spotify: SpotifyClient, lyrics: LyricsService, artwork: ArtworkStore, settings: Settings) {
        self.spotify = spotify
        self.settings = settings

        panel = LockPanel(contentRect: NSRect(origin: .zero, size: Self.cardWindowSize),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.alphaValue = 0
        let host = NSHostingView(rootView: LockScreenView(
            spotify: spotify, lyrics: lyrics, artwork: artwork, settings: settings))
        host.sizingOptions = [] // pencere boyutunu place() belirler, görünüm pencereyi doldurur
        panel.contentView = host

        // Düzen / taraf / yükseklik değişince görünürse yeniden yerleş
        settingsObserver = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { if let self, self.panel.isVisible { self.place() } }
        }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenUnlocked() }
        }
        // Ekran uykudan uyanınca kilit hâlâ açık değilse yeniden göster
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isLocked == true { self?.screenLocked() } }
        }
    }

    var isAvailable: Bool { LockScreenSpace.shared.isAvailable }

    private func screenLocked() {
        isLocked = true
        previewWork?.cancel()
        spotify.refresh()
        guard settings.lockScreenEnabled, spotify.isRunning, spotify.track != nil else { return }
        place()
        LockScreenSpace.shared.attach(panel)
        show()
    }

    private func screenUnlocked() {
        isLocked = false
        hide()
    }

    /// Kilitlemeden görmek için: kartı birkaç saniye masaüstünde gösterir.
    func preview(seconds: TimeInterval = 5) {
        previewWork?.cancel()
        place()
        show()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isLocked else { return }
            self.hide()
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Tam kart: ortada. Yan düzen: macOS'un kilit ekranı oynatıcısının (ekranın ortasında) sağında/solunda.
    private func place() {
        guard let screen = NSScreen.screens.first else { return }
        let f = screen.frame
        let centerY = f.minY + f.height * CGFloat(settings.lockScreenHeight)
        let rect: NSRect
        switch settings.lockScreenLayout {
        case .card:
            let size = Self.cardWindowSize
            rect = NSRect(x: f.midX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
        case .side:
            let width = min(400, max(240, f.width / 2 - Self.systemPlayerClearance - 24))
            let height: CGFloat = 400
            let x = settings.lockScreenSide == .right
                ? f.midX + Self.systemPlayerClearance
                : f.midX - Self.systemPlayerClearance - width
            rect = NSRect(x: x, y: centerY - height / 2, width: width, height: height)
        }
        panel.setFrame(rect, display: true)
    }

    private func show() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.panel.alphaValue == 0 { self?.panel.orderOut(nil) }
            }
        })
    }

    #if DEBUG
    /// Geliştirme: kartı önizleme olarak açıp görüntüsünü kaydeder.
    func snapshot(to url: URL) {
        guard let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif
}

/// Kilit ekranında key olamaz (klavye odağını şifre alanından çalmasın) ama tıklamaları alır.
private final class LockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Kilit ekranı görünümü

struct LockScreenView: View {
    @ObservedObject var spotify: SpotifyClient
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var artwork: ArtworkStore
    @ObservedObject var settings: Settings

    private let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)

    /// Kilit ekranı da widget'ın arka plan ayarını izler. Cam efekti kilit ekranında çalışmadığı için koyu gibi.
    private var bg: BackgroundStyle { settings.background }
    private var lyricsScheme: BackgroundStyle { bg == .artwork ? .artwork : .dark }

    @ViewBuilder private func cardFill(_ radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch bg {
        case .artwork:
            ZStack {
                artwork.color.opacity(0.82)
                LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
        case .dark:
            shape.fill(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.88))
        case .glass, .transparent:
            shape.fill(.black.opacity(0.38))
        }
    }

    var body: some View {
        Group {
            if let track = spotify.track {
                switch settings.lockScreenLayout {
                case .side: side(track)
                case .card: card(track)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(spring, value: lyrics.available)
        .animation(spring, value: settings.lockScreenCollapsed)
    }

    /// Küçültülmüş "Sözler" düğmesi sistem oynatıcısına yakın tarafta dursun.
    private var alignment: Alignment {
        switch settings.lockScreenLayout {
        case .card: .center
        case .side: settings.lockScreenSide == .right ? .topLeading : .topTrailing
        }
    }

    // MARK: Yan düzen: sadece sözler

    @ViewBuilder private func side(_ track: Track) -> some View {
        if settings.lockScreenCollapsed {
            expandButton.transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else if lyrics.available {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 12, weight: .medium)).opacity(0.6).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    collapseButton
                }
                LyricsPanel(spotify: spotify, lyrics: lyrics, settings: settings, background: lyricsScheme, s: 1.05)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardFill(24))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    // MARK: Tam kart

    @ViewBuilder private func card(_ track: Track) -> some View {
        if settings.lockScreenCollapsed {
            expandButton.transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            HStack(spacing: 28) {
                VStack(spacing: 14) {
                    ArtworkImage(image: artwork.image, s: 1.1)
                        .frame(width: 170, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    TrackInfo(track: track, s: 1.05, alignment: .center)
                    ProgressRow(spotify: spotify, duration: track.duration, s: 1)
                    Controls(spotify: spotify, showLyrics: .constant(true), s: 1, showsLyricsToggle: false)
                }
                .frame(width: 250)
                .sectionBox(bg == .transparent, s: 1)

                if lyrics.available {
                    LyricsPanel(spotify: spotify, lyrics: lyrics, settings: settings, background: lyricsScheme, s: 1.15)
                        // Sabit yükseklik: düz (senkron olmayan) sözler ScrollView'u fixedSize içinde sonsuz uzatmasın
                        .frame(width: 400, height: bg == .transparent ? 320 : 360)
                        .sectionBox(bg == .transparent, s: 1)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
            // Şeffafta dış kart yok: bölümler ayrı yarı saydam kutularda (masaüstü widget'ı gibi)
            .padding(bg == .transparent ? 0 : 26)
            .fixedSize()
            .background { if bg != .transparent { cardFill(28) } }
            .overlay {
                if bg != .transparent {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
            }
            .overlay(alignment: .topTrailing) { collapseButton.padding(bg == .transparent ? 10 : 14) }
            .shadow(color: .black.opacity(bg == .transparent ? 0 : 0.35), radius: 24, y: 10)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    // MARK: Küçült / aç

    private var collapseButton: some View {
        Button { withAnimation(spring) { settings.lockScreenCollapsed = true } } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(PressFadeStyle())
        .help("Sözleri küçült")
    }

    private var expandButton: some View {
        Button { withAnimation(spring) { settings.lockScreenCollapsed = false } } label: {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble.fill").font(.system(size: 12))
                Text("Sözler").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.38)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressFadeStyle())
        .padding(4)
        .help("Sözleri göster")
    }
}
