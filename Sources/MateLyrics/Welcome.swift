import AppKit
import SwiftUI

/// Uygulama simgesine tıklayınca (ve ilk açılışta) çıkan pencere. Uygulama menü çubuğunda çalıştığı için
/// başka penceresi yok; bu pencere "açıldı mı?" sorusunu cevaplar ve temel ayarları gösterir.
struct WelcomeView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var spotify: SpotifyClient
    let firstRun: Bool
    let bringWidgetToFront: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mate Lyrics").font(.title2.bold())
                    Text(firstRun ? "Kurulum tamam, uygulama çalışıyor" : "Uygulama çalışıyor")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Widget masaüstünde duruyor; ayrı bir pencere açılmaz. Uygulama menü çubuğundaki ♫ simgesinde çalışır. Ayarlar için o simgeye ya da widget'a sağ tıkla.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    statusRows
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Hızlı ayarlar") {
                Form {
                    Picker("Görünüm", selection: $settings.style) {
                        ForEach(WidgetStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Arka plan", selection: $settings.background) {
                        ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Konum", selection: $settings.positionPreset) {
                        ForEach(PositionPreset.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Masaüstüne sabitle (pencerelerin arkasında)", isOn: $settings.pinToDesktop)
                    Toggle("Girişte otomatik başlat", isOn: Binding(get: { settings.launchAtLogin },
                                                                    set: { settings.launchAtLogin = $0 }))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                Button("Widget'ı öne getir", action: bringWidgetToFront)
                    .help("Widget'ı birkaç saniyeliğine pencerelerin önüne getirir")
                Spacer()
                Button("Tamam", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    @ViewBuilder private var statusRows: some View {
        if !spotify.isRunning {
            row("exclamationmark.triangle.fill", .orange, "Spotify kapalı") {
                Button("Spotify'ı aç") { spotify.launchSpotify() }
            }
            row("info.circle", .secondary,
                "Spotify açılınca macOS \"Mate Lyrics, Spotify'ı denetlemek istiyor\" diye soracak: İzin Ver de.")
        } else if spotify.permissionDenied {
            row("checkmark.circle.fill", .green, "Spotify açık")
            row("exclamationmark.triangle.fill", .orange, "Spotify'a erişim izni verilmemiş") {
                Button("Ayarları aç") { spotify.openPrivacySettings() }
            }
            row("info.circle", .secondary, "Gizlilik ve Güvenlik › Otomasyon › Mate Lyrics altında Spotify'ı aç.")
        } else if let track = spotify.track {
            row("checkmark.circle.fill", .green, "Spotify açık, izin tamam")
            row("music.note", .secondary, "Çalan: \(track.name) – \(track.artist)")
        } else {
            row("checkmark.circle.fill", .green, "Spotify açık")
            row("info.circle", .secondary, "Bir şarkı başlat; widget'ta görünecek. İzin sorusu çıkarsa İzin Ver de.")
        }
    }

    private func row(_ symbol: String, _ color: Color, _ text: String) -> some View {
        row(symbol, color, text) { EmptyView() }
    }

    private func row<Trailing: View>(_ symbol: String, _ color: Color, _ text: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

@MainActor
final class WelcomeWindowController {
    private(set) var window: NSWindow?

    func show(settings: Settings, spotify: SpotifyClient, firstRun: Bool, bringWidgetToFront: @escaping () -> Void) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Mate Lyrics"
            w.isReleasedWhenClosed = false
            window = w
        }
        guard let window else { return }
        window.contentView = NSHostingView(rootView: WelcomeView(
            settings: settings, spotify: spotify, firstRun: firstRun,
            bringWidgetToFront: bringWidgetToFront, close: { [weak window] in window?.close() }))
        window.setContentSize(window.contentView!.fittingSize)
        if !window.isVisible { window.center() }
        // Menü çubuğu uygulaması olduğu için pencereyi öne almak üzere uygulamayı etkinleştir
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
