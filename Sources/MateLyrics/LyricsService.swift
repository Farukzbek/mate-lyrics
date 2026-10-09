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
    @Published private(set) var state: LyricsState = .idle
    private var cache: [String: LyricsState] = [:]
    private var currentID: String?
    private var task: Task<Void, Never>?

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
            state = cached
            return
        }
        state = .loading
        task = Task {
            let result = await Self.fetch(track)
            guard !Task.isCancelled, currentID == track.id else { return }
            cache[track.id] = result
            state = result
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
        c.httpAdditionalHeaders = ["User-Agent": "MateLyrics/1.1 (https://github.com/Farukzbek/mate-lyrics)"]
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    private static func fetch(_ track: Track) async -> LyricsState {
        // 1) Birebir eşleşme (süre dahil)
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            .init(name: "track_name", value: track.name),
            .init(name: "artist_name", value: track.artist),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        if let r: Record = await request(get.url!), let s = state(from: r) { return s }

        // 2) Arama: "- Remastered", "(feat. ...)" gibi ekleri temizleyip en yakın süreyi seç
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            .init(name: "track_name", value: cleaned(track.name)),
            .init(name: "artist_name", value: track.artist),
        ]
        if let list: [Record] = await request(search.url!) {
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
        return .notFound
    }

    private static func request<T: Decodable>(_ url: URL) async -> T? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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
