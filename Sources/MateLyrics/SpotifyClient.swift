import AppKit
import Combine

struct Track: Equatable {
    var id: String
    var name: String
    var artist: String
    var album: String
    var duration: Double
    var artworkURL: URL?
}

/// Spotify'dan çalan şarkıyı AppleScript ile okur, kontrol komutlarını gönderir.
@MainActor
final class SpotifyClient: ObservableObject {
    static let bundleID = "com.spotify.client"

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false

    /// Oynat/durdur'a basınca Spotify durumu hemen güncellemiyor; bu süre içinde gelen eski durumu yok say.
    private var expectedPlaying: (value: Bool, until: Date)?
    private var position: Double = 0
    private var positionDate = Date()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "mate.spotify.applescript")

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Son okumadan bu yana geçen süreyi ekleyerek tahmini anlık pozisyon.
    func currentPosition(at date: Date = Date()) -> Double {
        guard isPlaying else { return position }
        let p = position + date.timeIntervalSince(positionDate)
        return min(p, track?.duration ?? p)
    }

    // MARK: - Okuma

    nonisolated(unsafe) private static let readScript = NSAppleScript(source: """
    tell application "Spotify"
        set s to player state as string
        if s is "stopped" then return {"stopped"}
        set t to current track
        return {s, player position, id of t, name of t, artist of t, album of t, duration of t, artwork url of t}
    end tell
    """)!

    func refresh() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        guard running else {
            if isRunning { isRunning = false }
            if isPlaying { isPlaying = false }
            if track != nil { track = nil }
            return
        }
        queue.async { [weak self] in
            var error: NSDictionary?
            let start = Date()
            let result = Self.readScript.executeAndReturnError(&error)
            // Spotify konumu sorgunun ortasında okur (ölçüldü: ~50 ms sorgu, gerçek zamanla ~10 ms uyum)
            let sampleDate = start.addingTimeInterval(Date().timeIntervalSince(start) / 2)
            let errorCode = error?[NSAppleScript.errorNumber] as? Int
            let parsed = errorCode == nil ? Self.parse(result) : nil
            Task { @MainActor in
                guard let self else { return }
                // Değişmeyen değerleri tekrar yazma: her yazım tüm widget'ı yeniden çizdirir.
                if !self.isRunning { self.isRunning = true }
                let denied = errorCode == -1743 || errorCode == -1744
                if self.permissionDenied != denied { self.permissionDenied = denied }
                if denied { return }
                guard let parsed else {
                    if errorCode == nil { // durdurulmuş
                        if self.isPlaying { self.isPlaying = false }
                        if self.track != nil { self.track = nil }
                    }
                    return
                }
                self.apply(parsed, at: sampleDate)
            }
        }
    }

    private struct Snapshot {
        var playing: Bool
        var position: Double
        var track: Track
    }

    nonisolated private static func parse(_ d: NSAppleEventDescriptor) -> Snapshot? {
        guard d.numberOfItems >= 8 else { return nil }
        func str(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
        let durationMs = Double(d.atIndex(7)?.int32Value ?? 0)
        let track = Track(
            id: str(3), name: str(4), artist: str(5), album: str(6),
            duration: durationMs / 1000,
            artworkURL: URL(string: str(8))
        )
        return Snapshot(playing: str(1) == "playing", position: d.atIndex(2)?.doubleValue ?? 0, track: track)
    }

    private func apply(_ s: Snapshot, at date: Date) {
        if track != s.track { track = s.track }
        if let e = expectedPlaying {
            if s.playing == e.value || Date() > e.until {
                expectedPlaying = nil
            } else {
                return // Spotify henüz yeni durumu bildirmedi; iğne/plak ileri-geri zıplamasın
            }
        }
        if isPlaying != s.playing { isPlaying = s.playing }
        // Spotify'ın konumu doğru; doğrudan kullan (eski yumuşatma tahmini ileri kaydırıyordu).
        position = s.position
        positionDate = date
    }

    // MARK: - Kontroller

    func playPause() {
        freezePosition()
        isPlaying.toggle()
        expectedPlaying = (isPlaying, Date().addingTimeInterval(1.5))
        run("playpause")
    }
    func next() { run("next track") }
    func previous() { run("previous track") }

    func seek(to seconds: Double) {
        position = seconds
        positionDate = Date()
        run("set player position to \(seconds)")
    }

    func launchSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// Spotify'ı öne getirir; Dock simgesine tıklamak gibi, hiçbir sayfaya yönlendirmez
    /// (kapalıysa açar, pencere kapalıysa son kaldığı sayfayla yeniden gösterir).
    func bringToFront() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    private func freezePosition() {
        position = currentPosition()
        positionDate = Date()
    }

    private func run(_ command: String) {
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Spotify\" to \(command)")?.executeAndReturnError(&error)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.refresh()
            }
        }
    }
}
