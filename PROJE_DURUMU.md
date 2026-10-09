# Mate Lyrics — Proje Durumu

Spotify'da çalan şarkıyı masaüstünde gösteren SwiftUI widget (macOS 14+). Kişisel kullanım + arkadaşlara zip.

## Mimari
- `SpotifyClient.swift` — AppleScript ile Spotify okuma/kontrol (1 sn poll + PlaybackStateChanged bildirimi, pozisyon interpolasyonu)
- `LyricsService.swift` — lrclib.net (önce /api/get, olmazsa /api/search + süre eşleşmesi), LRC parse
- `Settings.swift` — AppStorage ayarları + kapak indirme/baskın renk
- `Views.swift` / `VinylAndLyrics.swift` — Plak, Kapak, Kompakt görünüm; söz paneli (ScrollView yok, offset ile kaydırma)
- `App.swift` — MenuBarExtra + kenarlıksız NSPanel (masaüstü seviyesi / üstte), konum kaydı

## Build
`./build-app.sh` → `dist/Mate Lyrics.app` + `dist/Mate-Lyrics.zip` (universal, ad-hoc imzalı)
Görsel test: `.build/debug/MateLyrics --snapshot <klasör>` → her görünümü PNG kaydeder.

## Notlar
- NSHostingController.sizingOptions=.preferredContentSize sonsuz layout döngüsüyle çöktü → pencere boyutu PreferenceKey ile elle ayarlanıyor.
- ImageRenderer ScrollView çizmiyor ve offset'li içeriği kırpmıyor → snapshot artık NSHostingView.cacheDisplay ile.
- Pencere boyutu: FittingHostingView.invalidateIntrinsicContentSize → fittingSize'a göre (sizingOptions sadece
  intrinsicContentSize). Eski SizeKey preference yolu hiç tetiklenmiyordu, pencere küçülmüyordu → köşe kayıyordu.
  Test: `.build/debug/MateLyrics --test-drag` (sahte fare olaylarıyla büyüt/taşı/küçült, pencere=içerik kontrolü)
- Oynat/durdur sonrası 1.5 sn Spotify'ın eski durumu yok sayılır (iğne zıplıyordu).
- Taşıma/boyutlandırma WidgetPanel.sendEvent'te elle (isMovableByWindowBackground köşe sürüklemeyi yutuyordu).
- Söz paneli: aktif satır 0.05 sn Timer ile, sadece değişince state güncellenir (TimelineView kasıyordu).
- Söz satırı değişimi 36 ms → ~1 ms: satır başına GeometryReader kaldırıldı, yükseklikler LyricsLayout'ta
  NSAttributedString ile bir kez ölçülüp önbelleğe alınıyor; LyricRow Equatable (sadece 2 satır yeniden çizilir).
  Ölçüm: `.build/release/MateLyrics --bench`
- SpotifyClient @Published alanlara sadece değer değişince yazar (her yazım tüm widget'ı yeniden çizdiriyordu).
- Senkron: Spotify AppleScript konumu gerçek zamanla ~10 ms uyumlu (ölçüldü). Konum ham kullanılıyor
  (sorgu ortası zaman damgası), lead 0.1 sn, LRCLIB arama eşleşmesi süre farkı < 10 sn (senkron + en yakın süre önce; 3 sn Jefe - TEQUILA SUNRISE gibi tek kayıtlı şarkıları kaçırıyordu).
  Şarkı bazında elle kaydırma: menü › "Söz zamanlaması (bu şarkı)" (UserDefaults "lyricOffsets").
- Şarkı başında üst boşluk yok: offset üstten %10'a sınırlı, aktif satır %35'e gelince kaymaya başlar.
- Spotify'ın kendi söz API'si yok/kapalı; sözler LRCLIB'den.

## Durum (2026-10-09)
v1 + kullanıcı istekleri: widget üstünde söz aç/kapa butonu, yumuşak söz geçişi, plak 60°/sn,
köşeden boyutlandırma (scale 0.6–1.8), "Şeffaf (ayrı kutular)" arka planı. /Applications'a kuruldu, kullanıcı testi bekleniyor.
