import AppKit
import SwiftUI

// MARK: - Plak

struct VinylDisc: View {
    let image: NSImage?
    let isPlaying: Bool
    let s: CGFloat

    @State private var baseAngle: Double = 0
    @State private var spinStart: Date?
    private let degreesPerSecond = 60.0 // ~10 devir/dk (gerçek 33⅓ ekranda fazla hızlı duruyor)

    var body: some View {
        let d = 205 * s
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !isPlaying)) { ctx in
                record(diameter: d)
                    .rotationEffect(.degrees(angle(at: ctx.date)))
            }
            .overlay(sheen.frame(width: d, height: d).allowsHitTesting(false))
            .frame(width: d, height: d)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
            .offset(x: 4 * s, y: 6 * s)

            Tonearm(s: s)
                .rotationEffect(.degrees(isPlaying ? 19 : 3), anchor: UnitPoint(x: 0.5, y: 0.06))
                .offset(x: 200 * s, y: 0)
                .animation(.easeInOut(duration: 0.8), value: isPlaying)
        }
        .frame(width: 236 * s, height: 216 * s, alignment: .topLeading)
        .onAppear { if isPlaying { spinStart = Date() } }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                spinStart = Date()
            } else if let start = spinStart {
                baseAngle += Date().timeIntervalSince(start) * degreesPerSecond
                spinStart = nil
            }
        }
    }

    private func angle(at date: Date) -> Double {
        guard let start = spinStart else { return baseAngle }
        return (baseAngle + date.timeIntervalSince(start) * degreesPerSecond).truncatingRemainder(dividingBy: 360)
    }

    private func record(diameter d: CGFloat) -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.05)],
                                         center: .center, startRadius: 0, endRadius: d / 2))
            // Oluklar
            ForEach(0..<14, id: \.self) { i in
                Circle()
                    .stroke(.white.opacity(i % 3 == 0 ? 0.07 : 0.035), lineWidth: 0.6)
                    .frame(width: d * (0.96 - CGFloat(i) * 0.04), height: d * (0.96 - CGFloat(i) * 0.04))
            }
            // Etiket = albüm kapağı
            ArtworkImage(image: image, s: s)
                .frame(width: d * 0.38, height: d * 0.38)
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
            Circle().fill(Color(white: 0.85)).frame(width: d * 0.035, height: d * 0.035)
        }
        .frame(width: d, height: d)
    }

    /// Dönmeyen ışık yansıması — plak döndükçe gerçekçi görünür.
    private var sheen: some View {
        Circle()
            .fill(AngularGradient(colors: [
                .clear, .white.opacity(0.13), .clear, .clear,
                .clear, .white.opacity(0.13), .clear, .clear, .clear,
            ], center: .center, angle: .degrees(-20)))
            .mask(Circle().strokeBorder(lineWidth: 205 * s * 0.31).padding(205 * s * 0.01))
    }
}

struct Tonearm: View {
    let s: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.5)], startPoint: .top, endPoint: .bottom))
                .frame(width: 20 * s, height: 20 * s)
                .overlay(Circle().fill(Color(white: 0.3)).frame(width: 7 * s, height: 7 * s))
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.6)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 4 * s, height: 128 * s)
                .padding(.top, -4 * s)
            RoundedRectangle(cornerRadius: 2.5 * s)
                .fill(Color(white: 0.25))
                .frame(width: 10 * s, height: 22 * s)
        }
        .shadow(color: .black.opacity(0.45), radius: 4, x: 2, y: 3)
        .frame(width: 20 * s)
    }
}

// MARK: - Şarkı sözleri

/// İki parmakla kaydırma durumu. Kaydırınca otomatik takip durur, 3 sn sonra çalan satıra döner.
@MainActor
final class LyricsScroll: ObservableObject {
    static let shared = LyricsScroll()
    static let idleReturn: TimeInterval = 3

    @Published private(set) var offset: CGFloat = 0
    /// Kaydırma başladığında görünüm bu satıra sabitlenir (şarkı ilerlese de liste zıplamaz).
    @Published private(set) var frozenActive: Int?
    private(set) var lastScroll = Date.distantPast
    /// Panelin bildirdiği o anki aktif satır ve izin verilen kaydırma aralığı (yayınlanmaz).
    var currentActive = -1
    var range: ClosedRange<CGFloat> = 0...0

    func scroll(by dy: CGFloat) {
        if frozenActive == nil { frozenActive = currentActive }
        offset = min(max(offset + dy, range.lowerBound), range.upperBound)
        lastScroll = Date()
    }

    func reset(animated: Bool) {
        guard frozenActive != nil || offset != 0 else { return }
        let apply = { self.offset = 0; self.frozenActive = nil }
        if animated {
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.6), apply)
        } else {
            apply()
        }
    }

    func returnIfIdle() {
        if frozenActive != nil, Date().timeIntervalSince(lastScroll) > Self.idleReturn { reset(animated: true) }
    }
}

/// Satırı sesten çok az önce yak (Spotify da böyle yapıyor).
enum LyricsOffset { static let lead = 0.1 }

struct LyricsPanel: View {
    @ObservedObject var spotify: SpotifyClient
    @ObservedObject var lyrics: LyricsService
    let settings: Settings
    let background: BackgroundStyle
    let s: CGFloat

    var body: some View {
        Group {
            switch lyrics.state {
            case .idle, .loading:
                placeholder("Sözler yükleniyor…", icon: "text.quote")
            case .notFound:
                placeholder("Bu şarkının sözleri bulunamadı", icon: "text.badge.xmark")
            case .instrumental:
                placeholder("Enstrümantal ♪", icon: "pianokeys")
            case .plain(let lines):
                ScrollView {
                    VStack(alignment: .leading, spacing: 8 * s) {
                        Text("Senkron değil").font(.system(size: 10 * s, weight: .semibold)).opacity(0.5)
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 15 * s, weight: .bold))
                                .opacity(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16 * s)
                }
                .scrollIndicators(.hidden)
            case .synced(let lines):
                SyncedLyrics(lines: lines, active: active, background: background, s: s) {
                    scroll.reset(animated: true)
                    spotify.seek(to: $0)
                }
                .onReceive(tick) { _ in
                    updateActive(lines)
                    scroll.returnIfIdle()
                }
                .onAppear { updateActive(lines) }
                .onChange(of: spotify.track?.id) { _, _ in scroll.reset(animated: false) }
            }
        }
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
            .init(color: .black, location: 0.88), .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }

    @State private var active = -1
    private let scroll = LyricsScroll.shared
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    /// Sadece satır değişince state güncellenir, panel saniyede 20 kez baştan çizilmez.
    private func updateActive(_ lines: [LyricLine]) {
        // Ekrana biraz erken düşsün (Spotify'daki gibi)
        let t = spotify.currentPosition() + LyricsOffset.lead + settings.offset(for: spotify.track?.id)
        var i = activeIndex(lines, at: t)
        // Sınırda ölçüm titremesi yüzünden bir önceki satıra zıplama (gerçek geri sarmada geç)
        if i == active - 1, active < lines.count, lines[active].time - t < 0.4 { i = active }
        scroll.currentActive = i
        guard i != active else { return }
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.6)) { active = i }
    }

    private func activeIndex(_ lines: [LyricLine], at t: Double) -> Int {
        var lo = 0, hi = lines.count - 1, ans = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= t { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    private func placeholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 8 * s) {
            Image(systemName: icon).font(.system(size: 22 * s))
            Text(text).font(.system(size: 13 * s, weight: .semibold))
        }
        .opacity(0.55)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SyncedLyrics: View {
    @ObservedObject private var scroll = LyricsScroll.shared
    let lines: [LyricLine]
    let active: Int
    let background: BackgroundStyle
    let s: CGFloat
    let onSeek: (Double) -> Void

    var body: some View {
        // ScrollView ve satır başına ölçüm yok: satır yükseklikleri bir kez hesaplanır,
        // aktif satır hep üstten %35'te durur. Satır değişince sadece 2 satır yeniden çizilir.
        GeometryReader { geo in
            let layout = LyricsLayout.get(lines: lines, width: geo.size.width, s: s)
            // Kullanıcı kaydırıyorsa liste kaydırmanın başladığı satıra sabit kalır
            let i = min(max(scroll.frozenActive ?? active, 0), max(lines.count - 1, 0))
            // Baştaki satırlarda üstte boşluk bırakma: liste en üstten başlar,
            // aktif satır %35 hizasına gelince kaymaya başlar (Spotify gibi).
            let topInset = geo.size.height * 0.1
            let base = layout.mids.isEmpty ? topInset : min(topInset, geo.size.height * 0.35 - layout.mids[i])
            // Kaydırma sınırı: ilk satır üstten, son satır %35 hizasından öteye gitmesin
            let lowest = min(topInset, geo.size.height * 0.35 - layout.total)
            let _ = scroll.range = (lowest - base)...(topInset - base)
            let target = base + scroll.offset
            VStack(alignment: .leading, spacing: LyricsLayout.spacing * s) {
                ForEach(lines) { line in
                    LyricRow(text: line.text, state: state(line.id), background: background, s: s) {
                        onSeek(line.time)
                    }
                    .equatable()
                    // Sadece panelde görünen satırlar tıklanabilir
                    .allowsHitTesting(layout.mids.indices.contains(line.id)
                        && (0...geo.size.height).contains(layout.mids[line.id] + target))
                }
            }
            .offset(y: target)
        }
        .clipped()
        // clipped() sadece çizimi kırpar; dışarı taşan satırlar görünmez ama tıklanabilir kalıyordu
        // (boşluğa / düğmelere tıklayınca şarkı o satıra sarılıyordu). Tıklamayı da panelle sınırla.
        .contentShape(Rectangle())
    }

    private func state(_ id: Int) -> LyricRow.State {
        id == active ? .active : (id < active ? .past : .future)
    }
}

struct LyricRow: View, Equatable {
    enum State { case past, active, future }
    let text: String
    let state: State
    let background: BackgroundStyle
    let s: CGFloat
    let onTap: () -> Void

    static func == (a: LyricRow, b: LyricRow) -> Bool {
        a.text == b.text && a.state == b.state && a.background == b.background && a.s == b.s
    }

    var body: some View {
        Text(text)
            .font(.system(size: LyricsLayout.fontSize * s, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    /// Spotify tarzı: söylenen satır beyaz, geçmiş soluk beyaz, gelecek koyu.
    private var color: Color {
        switch (state, background == .artwork) {
        case (.active, _): .white
        case (.past, true): .white.opacity(0.55)
        case (.future, true): .black.opacity(0.55)
        case (.past, false): .white.opacity(0.4)
        case (.future, false): .white.opacity(0.3)
        }
    }
}

/// Satırların dikey orta noktalarını AppKit ile ölçer ve önbelleğe alır.
@MainActor
enum LyricsLayout {
    static let fontSize: CGFloat = 17
    static let spacing: CGFloat = 12
    struct Result { let mids: [CGFloat]; let total: CGFloat }
    private static var cache: [String: Result] = [:]

    static func get(lines: [LyricLine], width: CGFloat, s: CGFloat) -> Result {
        let key = "\(lines.count)|\(lines.first?.text ?? "")|\(lines.last?.text ?? "")|\(Int(width))|\(s)"
        if let r = cache[key] { return r }
        let font = NSFont.systemFont(ofSize: fontSize * s, weight: .bold)
        var y: CGFloat = 0
        var mids: [CGFloat] = []
        for line in lines {
            let h = ceil(NSAttributedString(string: line.text, attributes: [.font: font])
                .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            mids.append(y + h / 2)
            y += h + spacing * s
        }
        let r = Result(mids: mids, total: y)
        if cache.count > 50 { cache.removeAll() }
        cache[key] = r
        return r
    }
}

