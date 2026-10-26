import AppKit
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
    /// Pencere sabit boyutta; kart içinde ortalanır (sözler yokken daralır, pencere değişmez).
    static let windowSize = NSSize(width: 920, height: 480)

    private let spotify: SpotifyClient
    private let settings: Settings
    private let panel: NSPanel
    private var isLocked = false
    private var previewWork: DispatchWorkItem?

    init(spotify: SpotifyClient, lyrics: LyricsService, artwork: ArtworkStore, settings: Settings) {
        self.spotify = spotify
        self.settings = settings

        panel = LockPanel(contentRect: NSRect(origin: .zero, size: Self.windowSize),
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
        panel.contentView = NSHostingView(rootView: LockScreenView(
            spotify: spotify, lyrics: lyrics, artwork: artwork, settings: settings))

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

    /// Ana ekranın ortasının biraz altı: üstteki saatle alttaki şifre alanının arasına.
    private func place() {
        guard let screen = NSScreen.screens.first else { return }
        let f = screen.frame
        let size = Self.windowSize
        let y = f.minY + f.height * CGFloat(settings.lockScreenHeight) - size.height / 2
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
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

    var body: some View {
        Group {
            if let track = spotify.track {
                card(track)
            }
        }
        .foregroundStyle(.white)
        .frame(width: LockScreenController.windowSize.width, height: LockScreenController.windowSize.height)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: lyrics.available)
    }

    private func card(_ track: Track) -> some View {
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

            if lyrics.available {
                LyricsPanel(spotify: spotify, lyrics: lyrics, settings: settings, background: .artwork, s: 1.15)
                    .frame(width: 400)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(26)
        .fixedSize()
        .background(
            ZStack {
                artwork.color.opacity(0.82)
                LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}
