<p align="center">
  <img src="docs/icon.png" width="96" alt="Mate Lyrics icon">
</p>

<h1 align="center">Mate Lyrics</h1>

<p align="center">
  Spotify'da çalan şarkıyı macOS masaüstünde gösteren, senkron şarkı sözlü widget.<br>
  <i>A macOS desktop widget for the song playing in Spotify, with synced lyrics.</i>
</p>

<p align="center">
  <a href="https://github.com/Farukzbek/mate-lyrics/releases/latest/download/Mate-Lyrics.dmg"><b>⬇️ macOS için indir (Mate-Lyrics.dmg)</b></a><br>
  <sub>macOS 14 veya üstü · Spotify masaüstü uygulaması gerekir · <a href="#kurulum">kurulum adımları</a></sub>
</p>

<p align="center">
  <img src="docs/screenshots/vinyl-dark.png" width="640" alt="Plak görünümü">
</p>

## Özellikler

- **3 görünüm:** Plak (dönen plak + iğne), Kapak, Kompakt
- **Senkron şarkı sözleri:** Spotify tarzı, söylenen satır vurgulanır; satıra tıklayınca oraya atlar
- **4 arka plan:** kapak rengi, cam, koyu, şeffaf (ayrı kutular)
- **Tek tuşla sözleri aç/kapa**, oynat/durdur, ileri/geri, ilerleme çubuğundan atlama
- Sözü olmayan şarkılarda söz paneli **otomatik kapanır**, sözler gelince açılır (elle kapattıysan açılmaz)
- **Köşeden sürükleyerek boyutlandırma**, istediğin yere taşıma (konum hatırlanır), **konum kilidi**
- **Hazır konumlar:** sol/orta/sağ × üst/orta/alt; ekranın boyutuna göre hesaplanır (her ekranda aynı yere düşer), widget yeni konuma kayarak geçer
- Sözleri **iki parmakla kaydırma** (3 sn sonra çalan satıra döner)
- Kapağa / plağa tıklayınca **Spotify öne gelir** (sayfa değiştirmeden)
- Masaüstüne sabitleme (pencerelerin arkasında) veya her zaman üstte
- Spotify kapalıyken widget'ı göster ("Spotify'ı aç") ya da tamamen gizle
- Şarkı bazında söz zamanlaması ince ayarı
- **Kilit ekranında senkron sözler:** macOS'un kilit ekranı oynatıcısının altında altyazı gibi (kutulu yan düzen ve tam kart da seçilebilir); kilit ekranında tek dokunuşla gizle/göster
- Şarkı değişince sözler bulanık geçişle değişir
- Menü çubuğu uygulaması, Dock'ta yer kaplamaz; girişte otomatik başlatma

| Kapak | Şeffaf | Kompakt |
|---|---|---|
| <img src="docs/screenshots/cover-artwork.png" width="300"> | <img src="docs/screenshots/vinyl-transparent.png" width="300"> | <img src="docs/screenshots/compact-dark.png" width="220"> |

## Kurulum

> ⚠️ Yeşil **Code › Download ZIP** düğmesi uygulamayı değil, programın **kaynak kodunu** indirir. Uygulama için yukarıdaki indirme bağlantısını ya da [Releases](../../releases) sayfasındaki `Mate-Lyrics.dmg` dosyasını kullan.

1. [`Mate-Lyrics.dmg`](https://github.com/Farukzbek/mate-lyrics/releases/latest/download/Mate-Lyrics.dmg) dosyasını indir ve çift tıkla. Açılan pencerede **Mate Lyrics**'i **Applications** klasörünün üzerine sürükle.
2. Uygulamalar klasöründen Mate Lyrics'i aç. Uygulama Apple onayından geçmediği için ilk açılışta macOS uyarı verir:
   **Sistem Ayarları › Gizlilik ve Güvenlik › en altta "Yine de Aç"**. Ya da Terminal'de:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Mate Lyrics.app"
   ```
3. "Mate Lyrics, Spotify'ı denetlemek istiyor" sorusuna **İzin Ver** de.

İlk açılışta bir karşılama penceresi çıkar. Uygulama menü çubuğunda (♫) çalışır ve widget masaüstünde durur; uygulama simgesine tekrar tıklarsan bu pencere yeniden açılır.

**Gereksinimler:** macOS 14 (Sonoma) veya üstü, Spotify masaüstü uygulaması. Apple Silicon ve Intel.

## Kullanım

- Ayarlar: menü çubuğundaki ♫ ikonu ya da widget'a sağ tık.
- Boyutlandırma: widget'ın sağ alt köşesinden sürükle.
- Sözler kayıksa: sağ tık › **Söz zamanlaması (bu şarkı)** ile 0,25 sn adımlarla düzelt.

## Kaynaktan derleme

```bash
git clone https://github.com/Farukzbek/mate-lyrics.git
cd mate-lyrics
./build-app.sh        # dist/Mate Lyrics.app + dist/Mate-Lyrics.dmg
```

Xcode komut satırı araçları yeterli (Swift 5.9+). Geliştirme için:

| Komut | Ne yapar |
|---|---|
| `.build/debug/MateLyrics --snapshot <klasör>` | Her görünümü PNG olarak kaydeder |
| `.build/release/MateLyrics --bench` | Söz satırı değişiminin maliyetini ölçer |
| `.build/debug/MateLyrics --test-drag` | Taşıma/boyutlandırmayı sahte fare olaylarıyla dener |

## Nasıl çalışıyor?

- Çalan şarkı Spotify'dan **AppleScript** ile okunur (API anahtarı ya da giriş gerekmez).
- Şarkı sözleri topluluk tarafından oluşturulan ücretsiz [LRCLIB](https://lrclib.net) veritabanından gelir; her şarkıda bulunmayabilir.
- Tamamen SwiftUI + AppKit, harici bağımlılık yok.
- Kilit ekranı desteği macOS'un **resmi olmayan** SkyLight arayüzünü kullanır ([LockWidget](https://github.com/TechSynth/LockWidget) ve [Boring Notch](https://github.com/TheBoredTeam/boring.notch) ile aynı yöntem). Bir macOS güncellemesiyle çalışmayı bırakabilir; o durumda uygulama çökmez, sadece kilit ekranında görünmez. Menüden kapatılabilir.

---

## English

Mate Lyrics shows the track currently playing in Spotify as a desktop widget on macOS, with Spotify-style synced lyrics.

- Three styles (vinyl, cover, compact), four backgrounds, resize from the corner, pin to desktop
- Synced lyrics from [LRCLIB](https://lrclib.net); click a line to seek; per-song timing offset
- Lyrics on the lock screen as a subtitle under macOS's own Now Playing (uses the private SkyLight API; may break with macOS updates, can be turned off)
- Download `Mate-Lyrics.dmg` from [Releases](../../releases), drag the app to Applications, then allow it in **System Settings › Privacy & Security** (the app is not notarized) and allow Spotify automation when asked
- Requires macOS 14+ and the Spotify desktop app. Build with `./build-app.sh`

## Yasal not / Disclaimer

Bu proje Spotify ile bağlantılı değildir ve Spotify tarafından onaylanmamıştır. Spotify, Spotify AB'nin ticari markasıdır.
Şarkı sözlerinin ve albüm kapaklarının hakları sahiplerine aittir; uygulama bunları yalnızca kişisel kullanım için gösterir.

*Not affiliated with or endorsed by Spotify. Lyrics and artwork belong to their respective owners.*

## Lisans

[MIT](LICENSE)
