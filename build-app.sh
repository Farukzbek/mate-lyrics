#!/bin/zsh
# Mate Lyrics.app oluşturur (Apple Silicon + Intel), imzalar ve dağıtım için DMG + zip üretir.
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
  <key>CFBundleShortVersionString</key><string>1.8</string>
  <key>CFBundleVersion</key><string>9</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Spotify'da çalan şarkıyı göstermek ve kontrol etmek için.</string>
</dict></plist>
PLIST

# --- İmza -------------------------------------------------------------------------------------
# "Developer ID Application" sertifikası varsa onunla (hardened runtime; Apple onayı için şart),
# yoksa ad-hoc. Ad-hoc'ta indiren kişi ilk açılışta "Yine de Aç" demek zorunda.
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/MateLyrics.entitlements --sign "$SIGN_ID" "$APP"
  echo "İmza: $SIGN_ID"
else
  codesign --force --deep --sign - "$APP"
  echo "İmza: ad-hoc (Developer ID sertifikası yok)"
fi

cp NASIL_KURULUR.txt dist/ 2>/dev/null || true
(cd dist && zip -qry "Mate-Lyrics.zip" "Mate Lyrics.app" NASIL_KURULUR.txt)

# --- DMG --------------------------------------------------------------------------------------
# Apple onayı (notarization) için: xcrun notarytool store-credentials mate-lyrics-notary ...
NOTARY_PROFILE="mate-lyrics-notary"
NOTARIZE=""
if [ -n "$SIGN_ID" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then NOTARIZE=1; fi

VENV=".build/dmgvenv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild
fi
BG_DIR=".build/dmg-bg"
# Onaysız sürümde pencerede "Yine de Aç" ipucu gösterilir
if [ -n "$NOTARIZE" ]; then BG_FLAG=""; else BG_FLAG="--gatekeeper-ipucu"; fi
swift tools/make-dmg-background.swift "$BG_DIR" $BG_FLAG
tiffutil -cathidpicheck "$BG_DIR/dmg-bg.png" "$BG_DIR/dmg-bg@2x.png" -out "$BG_DIR/dmg-bg.tiff" 2>/dev/null
"$VENV/bin/dmgbuild" -s tools/dmg-settings.py -D app="$APP" -D bg="$BG_DIR/dmg-bg.tiff" "Mate Lyrics" "dist/Mate-Lyrics.dmg" >/dev/null

if [ -n "$SIGN_ID" ]; then codesign --force --timestamp --sign "$SIGN_ID" "dist/Mate-Lyrics.dmg"; fi
if [ -n "$NOTARIZE" ]; then
  echo "Apple onayına gönderiliyor (birkaç dakika sürebilir)…"
  xcrun notarytool submit "dist/Mate-Lyrics.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/Mate-Lyrics.dmg"
  echo "Apple onayı: tamam"
else
  echo "Apple onayı: yok (indiren kişi ilk açılışta \"Yine de Aç\" demeli)"
fi
echo "Hazır: $APP  +  dist/Mate-Lyrics.dmg  +  dist/Mate-Lyrics.zip"
