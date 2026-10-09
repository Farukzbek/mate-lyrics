#!/bin/zsh
# Mate Lyrics.app oluşturur (Apple Silicon + Intel) ve arkadaşlara atmak için zip'ler.
set -e
cd "$(dirname "$0")"
APP="dist/Mate Lyrics.app"

swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/MateLyrics"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MateLyrics"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Mate Lyrics</string>
  <key>CFBundleDisplayName</key><string>Mate Lyrics</string>
  <key>CFBundleIdentifier</key><string>online.matestudios.matelyrics</string>
  <key>CFBundleExecutable</key><string>MateLyrics</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Spotify'da çalan şarkıyı göstermek ve kontrol etmek için.</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
cp NASIL_KURULUR.txt dist/ 2>/dev/null || true
(cd dist && zip -qry "Mate-Lyrics.zip" "Mate Lyrics.app" NASIL_KURULUR.txt)
echo "Hazır: $APP  +  dist/Mate-Lyrics.zip"
