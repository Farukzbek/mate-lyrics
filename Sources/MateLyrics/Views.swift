import AppKit
import SwiftUI

// MARK: - Kök görünüm

struct WidgetView: View {
    @ObservedObject var spotify: SpotifyClient
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var artwork: ArtworkStore
    @ObservedObject var settings: Settings

    @State private var hovering = false

    private var s: CGFloat { CGFloat(settings.scale) }
    private var transparent: Bool { settings.background == .transparent }

    var body: some View {
        content
            .foregroundStyle(.white)
            .background(CardBackground(style: settings.background, color: artwork.color))
            .clipShape(RoundedRectangle(cornerRadius: 22 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .strokeBorder(.white.opacity(transparent ? 0 : 0.08), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if settings.lockPosition {
                        // Kilitliyken tutamak yerine küçük kilit; sadece üstüne gelince görünür
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .opacity(hovering ? 0.7 : 0)
                    } else {
                        ResizeHandle(settings: settings)
                            .opacity(hovering || settings.isResizing ? 1 : 0.35)
                    }
                }
                .padding(4)
                .allowsHitTesting(false)
            }
            .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
            .shadow(color: .black.opacity(transparent ? 0 : 0.35), radius: 18, y: 8)
            .padding(30)
            .contextMenu { ContextMenuItems(settings: settings, spotify: spotify) }
            .onChange(of: spotify.track) { _, t in
                artwork.load(t?.artworkURL)
                lyrics.load(for: t)
            }
            .onAppear {
                artwork.load(spotify.track?.artworkURL)
                lyrics.load(for: spotify.track)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: settings.showLyrics)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: settings.style)
    }

    @ViewBuilder private var content: some View {
        if !spotify.isRunning {
            MessageCard(icon: "music.note", title: "Spotify kapalı", button: "Spotify'ı aç", s: s) {
                spotify.launchSpotify()
            }
        } else if spotify.permissionDenied {
            MessageCard(icon: "lock.fill", title: "Spotify erişim izni gerekli",
                        subtitle: "Ayarlar › Gizlilik › Otomasyon'da Mate Lyrics için Spotify'ı aç",
                        button: "Ayarları aç", s: s) {
                spotify.openPrivacySettings()
            }
        } else if let track = spotify.track {
            player(track)
        } else {
            MessageCard(icon: "play.circle", title: "Şu an bir şey çalmıyor", s: s)
        }
    }

    @ViewBuilder private func player(_ track: Track) -> some View {
        let lyricsPanel = LyricsPanel(spotify: spotify, lyrics: lyrics, settings: settings, background: settings.background, s: s)
        switch settings.style {
        case .vinyl, .cover:
            HStack(alignment: .top, spacing: transparent ? 12 * s : 0) {
                VStack(spacing: transparent ? 12 * s : 14 * s) {
                    Group {
                        if settings.style == .vinyl {
                            VinylDisc(image: artwork.image, isPlaying: spotify.isPlaying, s: s)
                                .openSpotifyOnTap(spotify)
                        } else {
                            ArtworkImage(image: artwork.image, s: s)
                                .frame(width: 210 * s, height: 210 * s)
                                .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
                                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                                .openSpotifyOnTap(spotify)
                        }
                    }
                    .frame(width: 240 * s)
                    .sectionBox(transparent, s: s)

                    VStack(spacing: 14 * s) {
                        TrackInfo(track: track, s: s, alignment: .center)
                        ProgressRow(spotify: spotify, duration: track.duration, s: s)
                        Controls(spotify: spotify, showLyrics: $settings.showLyrics, s: s)
                    }
                    .frame(width: 240 * s)
                    .sectionBox(transparent, s: s)
                }
                .padding(transparent ? 0 : 20 * s)

                if settings.showLyrics {
                    lyricsPanel
                        .frame(width: 300 * s)
                        .padding(.vertical, transparent ? 0 : 20 * s)
                        .padding(.trailing, transparent ? 0 : 20 * s)
                        .frame(maxHeight: .infinity)
                        .sectionBox(transparent, s: s)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(height: (settings.style == .vinyl ? 400 : 390) * s + (transparent ? 40 * s : 0))

        case .compact:
            VStack(spacing: 0) {
              VStack(spacing: 0) {
                HStack(spacing: 12 * s) {
                    ArtworkImage(image: artwork.image, s: s)
                        .frame(width: 58 * s, height: 58 * s)
                        .clipShape(RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
                        .openSpotifyOnTap(spotify)
                    TrackInfo(track: track, s: s * 0.85, alignment: .leading)
                    Spacer(minLength: 0)
                    Controls(spotify: spotify, showLyrics: $settings.showLyrics, s: s * 0.8)
                }
                ProgressRow(spotify: spotify, duration: track.duration, s: s * 0.85, showTimes: false)
                    .padding(.top, 10 * s)
              }
              .sectionBox(transparent, s: s)
                if settings.showLyrics {
                    lyricsPanel
                        .frame(height: 170 * s)
                        .sectionBox(transparent, s: s)
                        .padding(.top, 12 * s)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(transparent ? 0 : 16 * s)
            .frame(width: 360 * s + (transparent ? 0 : 0))
        }
    }
}

// MARK: - Arka plan

struct CardBackground: View {
    let style: BackgroundStyle
    let color: Color

    var body: some View {
        switch style {
        case .artwork:
            ZStack {
                color
                LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            }
        case .glass:
            ZStack {
                VisualEffect()
                Color.black.opacity(0.15)
            }
        case .transparent:
            Color.black.opacity(0.001) // görünmez ama tıklanabilir/sürüklenebilir
        case .dark:
            Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.94)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Parçalar

struct ArtworkImage: View {
    let image: NSImage?
    let s: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note").font(.system(size: 30 * s)).opacity(0.6)
            }
        }
    }
}

struct TrackInfo: View {
    let track: Track
    let s: CGFloat
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 3 * s) {
            Text(track.name)
                .font(.system(size: 16 * s, weight: .bold))
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: 13 * s, weight: .medium))
                .opacity(0.7)
                .lineLimit(1)
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

struct ProgressRow: View {
    @ObservedObject var spotify: SpotifyClient
    let duration: Double
    let s: CGFloat
    var showTimes = true
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let pos = spotify.currentPosition(at: ctx.date)
            let progress = duration > 0 ? min(1, pos / duration) : 0
            VStack(spacing: 4 * s) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(.white).frame(width: max(0, geo.size.width * progress))
                    }
                    .frame(height: (hovering ? 6 : 4) * s)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                        let p = min(max(0, v.location.x / geo.size.width), 1)
                        spotify.seek(to: p * duration)
                    })
                }
                .frame(height: 10 * s)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)

                if showTimes {
                    HStack {
                        Text(format(pos))
                        Spacer()
                        Text(format(duration))
                    }
                    .font(.system(size: 10 * s, weight: .medium).monospacedDigit())
                    .opacity(0.6)
                }
            }
        }
    }

    private func format(_ t: Double) -> String {
        let t = Int(max(0, t))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct Controls: View {
    @ObservedObject var spotify: SpotifyClient
    @Binding var showLyrics: Bool
    let s: CGFloat

    var body: some View {
        HStack(spacing: 22 * s) {
            ControlButton(symbol: "backward.fill", size: 16 * s) { spotify.previous() }
            ControlButton(symbol: spotify.isPlaying ? "pause.circle.fill" : "play.circle.fill", size: 38 * s) {
                spotify.playPause()
            }
            ControlButton(symbol: "forward.fill", size: 16 * s) { spotify.next() }
            LyricsToggle(isOn: $showLyrics, s: s)
        }
    }
}

/// Sözleri tek tıkla aç/kapa. Açıkken yeşil (Spotify rengi) nokta ile işaretli.
struct LyricsToggle: View {
    @Binding var isOn: Bool
    let s: CGFloat

    var body: some View {
        ControlButton(symbol: "quote.bubble.fill", size: 15 * s) { isOn.toggle() }
            .opacity(isOn ? 1 : 0.45)
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(Color(red: 0.12, green: 0.84, blue: 0.38))
                    .frame(width: 4 * s, height: 4 * s)
                    .offset(y: 7 * s)
                    .opacity(isOn ? 1 : 0)
            }
            .help(isOn ? "Sözleri gizle" : "Sözleri göster")
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .opacity(hovering ? 1 : 0.85)
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct MessageCard: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var button: String? = nil
    let s: CGFloat
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 10 * s) {
            Image(systemName: icon).font(.system(size: 34 * s)).opacity(0.8)
            Text(title).font(.system(size: 15 * s, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11 * s)).opacity(0.6).multilineTextAlignment(.center)
            }
            if let button {
                Button(button, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12 * s, weight: .semibold))
                    .padding(.horizontal, 14 * s).padding(.vertical, 6 * s)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }
        }
        .padding(24 * s)
        .frame(width: 260 * s)
    }
}

struct ContextMenuItems: View {
    @ObservedObject var settings: Settings
    @ObservedObject var spotify: SpotifyClient

    var body: some View {
        Picker("Görünüm", selection: $settings.style) {
            ForEach(WidgetStyle.allCases) { Text($0.title).tag($0) }
        }
        Picker("Arka plan", selection: $settings.background) {
            ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
        }
        Menu("Boyut") {
            ForEach(WidgetSize.allCases) { size in
                Button(size.title) { settings.scale = Double(size.scale) }
            }
            Text("İpucu: sağ alt köşeden sürükleyerek de ayarlanır")
        }
        Toggle("Şarkı sözleri", isOn: $settings.showLyrics)
        Toggle("Konumu kilitle", isOn: $settings.lockPosition)
        Menu("Söz zamanlaması (bu şarkı)") {
            let id = spotify.track?.id
            let current = settings.offset(for: id)
            Text(current == 0 ? "Şu an: ayarsız" : String(format: "Şu an: %+.2f sn", current))
            Button("Sözler erken geliyor → 0,25 sn geciktir") { settings.adjustOffset(by: -0.25, for: id) }
            Button("Sözler geç geliyor → 0,25 sn öne al") { settings.adjustOffset(by: 0.25, for: id) }
            Button("Sıfırla") { settings.resetOffset(for: id) }.disabled(current == 0)
        }
    }
}

/// Sağ alt köşedeki tutamak (sadece görsel). Sürükleme WidgetPanel.sendEvent'te yönetiliyor.
struct ResizeHandle: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<3 {
                let o = CGFloat(i) * 4 + 6
                var p = Path()
                p.move(to: CGPoint(x: size.width - o, y: size.height - 5))
                p.addLine(to: CGPoint(x: size.width - 5, y: size.height - o))
                ctx.stroke(p, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .frame(width: 28, height: 28)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Kapağa / plağa tıklayınca Spotify öne gelir (sayfa değiştirmeden).
    func openSpotifyOnTap(_ spotify: SpotifyClient) -> some View {
        contentShape(Rectangle())
            .onTapGesture { spotify.bringToFront() }
            .help("Spotify'ı aç")
    }

    /// Şeffaf modda her bölümün arkasına yarı şeffaf, yuvarlak köşeli kutu koyar.
    @ViewBuilder func sectionBox(_ on: Bool, s: CGFloat) -> some View {
        if on {
            self
                .padding(14 * s)
                .background(
                    RoundedRectangle(cornerRadius: 18 * s, style: .continuous)
                        .fill(.black.opacity(0.42))
                        .overlay(RoundedRectangle(cornerRadius: 18 * s, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18 * s, style: .continuous))
        } else {
            self
        }
    }
}
