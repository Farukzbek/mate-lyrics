import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case notFound
}

/// Sözleri ücretsiz LRCLIB API'sinden (lrclib.net) çeker. Key gerekmez.
@MainActor
final class LyricsService: ObservableObject {
    @Published private(set) var state: LyricsState = .idle {
        didSet {
            // Yüklenirken önceki değer korunur: şarkı geçişlerinde panel kapanıp açılmasın
            let a: Bool? = switch state {
            case .synced, .plain: true
            case .notFound, .instrumental: false
            case .idle, .loading: nil
            }
            if let a, a != available { available = a }
        }
    }
    /// Bu şarkının gösterilecek sözü var mı (panelin otomatik açılıp kapanması için).
    @Published private(set) var available = true
    private var cache: [String: LyricsState] = [:]
    private var currentID: String?
    private var task: Task<Void, Never>?

    #if DEBUG
    /// Geliştirme: otomatik aç/kapa testini sözü olmayan bir şarkı bulmadan yapabilmek için.
    func debugSet(_ s: LyricsState) { state = s }
    #endif

    func load(for track: Track?) {
        guard let track else {
            currentID = nil
            state = .idle
            return
        }
        guard track.id != currentID else { return }
        currentID = track.id
        task?.cancel()
        if let cached = cache[track.id] {
            #if DEBUG
            if CommandLine.arguments.contains("--debug-size") {
                print(String(format: "[%.3f] sözler önbellekten", Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100)))
            }
            #endif
            state = cached
            return
        }
        state = .loading
        task = Task {
            // Sunucu/ağ hatasında "söz yok" deme: 3, 8, 20 sn sonra tekrar dene (panel bu sırada olduğu gibi kalır)
            for delay in [0, 3, 8, 20] as [UInt64] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
                guard !Task.isCancelled, currentID == track.id else { return }
                if let result = await Self.fetch(track) {
                    guard !Task.isCancelled, currentID == track.id else { return }
                    cache[track.id] = result
                    state = result
                    return
                }
            }
            // Hâlâ ulaşılamıyor: "bulunamadı" göster ama önbelleğe alma (şarkı tekrar gelince yeniden denenir)
            guard !Task.isCancelled, currentID == track.id else { return }
            state = .notFound
            currentID = nil
        }
    }

    // MARK: - Ağ

    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": "MateLyrics/1.5 (https://github.com/Farukzbek/mate-lyrics)"]
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    /// nil = LRCLIB'e ulaşılamadı (ağ hatası, 5xx); .notFound = gerçekten söz yok.
    private static func fetch(_ track: Track) async -> LyricsState? {
        // 1) Birebir eşleşme (süre dahil)
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            .init(name: "track_name", value: track.name),
            .init(name: "artist_name", value: track.artist),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        var reachable = true
        switch await request(get.url!) as Response<Record> {
        case .ok(let r): if let s = state(from: r) { return s }
        case .notFound: break
        case .failed: reachable = false
        }

        // 2) Arama: "- Remastered", "(feat. ...)" gibi ekleri temizleyip en yakın süreyi seç
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            .init(name: "track_name", value: cleaned(track.name)),
            .init(name: "artist_name", value: track.artist),
        ]
        let searchResult: Response<[Record]> = await request(search.url!)
        if case .failed = searchResult { return nil }
        if case .ok(let list) = searchResult {
            // Önce senkron olanlar, sonra süresi en yakın olan seçilir; böylece birebir kayıt varsa o kazanır.
            // Sınır geniş tutuldu: LRCLIB'de bazen tek kayıt var ve süresi birkaç sn farklı
            // (ör. Jefe - TEQUILA SUNRISE: Spotify 158,5 sn, LRCLIB 162 sn). Kayma olursa menüden ince ayar yapılır.
            let diff = { (r: Record) in abs((r.duration ?? 0) - track.duration) }
            let close = list.filter { diff($0) < 10 }
            let ranked = close.sorted {
                let a = $0.syncedLyrics != nil ? 0 : 1, b = $1.syncedLyrics != nil ? 0 : 1
                return a != b ? a < b : diff($0) < diff($1)
            }
            for r in ranked { if let s = state(from: r) { return s } }
        }
        // Arama çalıştı ama birebir istek başarısız olmuştu: sonucu kesin sayma, tekrar denensin
        return reachable ? .notFound : nil
    }

    private enum Response<T> { case ok(T), notFound, failed }

    private static func request<T: Decodable>(_ url: URL) async -> Response<T> {
        guard let (data, response) = try? await session.data(from: url),
              let code = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        if code == 404 { return .notFound }
        guard code == 200, let value = try? JSONDecoder().decode(T.self, from: data) else { return .failed }
        return .ok(value)
    }

    private static func state(from r: Record) -> LyricsState? {
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = r.plainLyrics, !plain.isEmpty {
            return .plain(plain.components(separatedBy: "\n"))
        }
        if r.instrumental == true { return .instrumental }
        return nil
    }

    private static func cleaned(_ name: String) -> String {
        var s = name
        if let r = s.range(of: " - ") { s = String(s[..<r.lowerBound]) }
        s = s.replacingOccurrences(of: #"\s*[\(\[](feat|ft|with)\.?[^\)\]]*[\)\]]"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)

    static func parseLRC(_ text: String) -> [LyricLine] {
        var items: [(Double, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = timeTag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let lyric = ns.substring(from: last.range.upperBound).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                items.append((min * 60 + sec, lyric.isEmpty ? "♪" : lyric))
            }
        }
        items.sort { $0.0 < $1.0 }
        // Art arda gelen boş "♪" satırlarını teke indir
        var lines: [LyricLine] = []
        for (t, s) in items where !(s == "♪" && lines.last?.text == "♪") {
            lines.append(LyricLine(id: lines.count, time: t, text: s))
        }
        return lines
    }
}
