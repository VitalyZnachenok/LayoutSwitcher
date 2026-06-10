#!/usr/bin/env bash
#
# Сборка Release-версии LayoutSwitcher и упаковка в КРАСИВЫЙ .dmg
# (с фоновой картинкой, иконкой приложения и ярлыком /Applications).
#
# В отличие от scripts/package.sh, этот скрипт НЕ требует сертификата
# "Developer ID Application" и НЕ выполняет нотаризацию. Он использует
# обычную автоматическую подпись "Apple Development". Полученный DMG
# вызовет предупреждение Gatekeeper на других Mac — открывать через
# правый клик -> «Открыть».
#
# Для будущего «релизного» (нотаризованного) DMG используйте package.sh.
#
# Запуск:
#   ./scripts/make-dmg.sh
#
# Оформление окна DMG делается через Finder/osascript и может не сработать
# в headless-окружении. В этом случае скрипт ВСЁ РАВНО выдаст обычный
# (неоформленный) сжатый DMG — оформление best-effort.
#
set -euo pipefail

# --- Конфигурация ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"            # .../layoutswitcher/LayoutSwitcher
REPO_ROOT="$(dirname "$PROJECT_DIR")"             # .../layoutswitcher
PROJECT="$PROJECT_DIR/LayoutSwitcher.xcodeproj"
SCHEME="LayoutSwitcher"
APP_NAME="LayoutSwitcher"
VERSION="2.1"
VOLNAME="$APP_NAME $VERSION"

BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

SRC_BG="$SCRIPT_DIR/assets/dmg-background.png"
BG_WORK="$BUILD_DIR/dmg-bg"                       # рабочая папка с подготовленным фоном
RW_DMG="$BUILD_DIR/$APP_NAME-rw.dmg"
FINAL_DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Геометрия окна DMG
WIN_W=660
WIN_H=440
ICON_SIZE=110
APP_ICON_X=165
APP_ICON_Y=255
APPS_ICON_X=495
APPS_ICON_Y=255

echo "==> Очистка прошлых артефактов"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$BG_WORK" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 1. Сборка Release (archive + export) с обычной "Apple Development" подписью
# ---------------------------------------------------------------------------
echo "==> Архивирование Release (Apple Development, автоматическая подпись)"
xcodebuild archive \
	-project "$PROJECT" \
	-scheme "$SCHEME" \
	-configuration Release \
	-archivePath "$ARCHIVE_PATH" \
	-destination "generic/platform=macOS" \
	CODE_SIGN_STYLE=Automatic \
	"CODE_SIGN_IDENTITY=Apple Development"

echo "==> Экспорт .app из архива (метод development)"
EXPORT_PLIST="$BUILD_DIR/ExportOptions-dev.plist"
cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>development</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST

if ! xcodebuild -exportArchive \
	-archivePath "$ARCHIVE_PATH" \
	-exportOptionsPlist "$EXPORT_PLIST" \
	-exportPath "$EXPORT_DIR"; then
	echo "!! exportArchive не удался — берём .app напрямую из архива"
	mkdir -p "$EXPORT_DIR"
	cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"
fi

if [[ ! -d "$APP_PATH" ]]; then
	echo "Ошибка: не найден $APP_PATH" >&2
	exit 1
fi

echo "==> Проверка подписи .app (best-effort)"
codesign --verify --verbose "$APP_PATH" || echo "!! codesign verify сообщил о проблеме (ожидаемо для development-подписи)"

# ---------------------------------------------------------------------------
# 2. Подготовка фона (resize до 660x440 + @2x ретина -> multi-res TIFF)
# ---------------------------------------------------------------------------
echo "==> Подготовка фоновой картинки"
mkdir -p "$BG_WORK"
BG_IMAGE=""
if [[ -f "$SRC_BG" ]]; then
	# sips -z height width
	sips -z "$WIN_H" "$WIN_W" "$SRC_BG" --out "$BG_WORK/background.png" >/dev/null 2>&1 || true
	sips -z $((WIN_H * 2)) $((WIN_W * 2)) "$SRC_BG" --out "$BG_WORK/background@2x.png" >/dev/null 2>&1 || true
	if [[ -f "$BG_WORK/background.png" && -f "$BG_WORK/background@2x.png" ]]; then
		if tiffutil -cathidpicheck "$BG_WORK/background.png" "$BG_WORK/background@2x.png" \
			-out "$BG_WORK/background.tiff" >/dev/null 2>&1; then
			BG_IMAGE="$BG_WORK/background.tiff"
		fi
	fi
	[[ -z "$BG_IMAGE" && -f "$BG_WORK/background.png" ]] && BG_IMAGE="$BG_WORK/background.png"
else
	echo "!! Фон не найден ($SRC_BG) — DMG будет без картинки"
fi

# ---------------------------------------------------------------------------
# 3. Создание RW DMG и наполнение
# ---------------------------------------------------------------------------
APP_MB=$(du -sm "$APP_PATH" | awk '{print $1}')
DMG_MB=$(( APP_MB + 60 ))
echo "==> Создание RW DMG (~${DMG_MB}MB)"
hdiutil create -size "${DMG_MB}m" -fs HFS+ -volname "$VOLNAME" -ov "$RW_DMG" >/dev/null

echo "==> Монтирование RW DMG"
MOUNT_DIR="/Volumes/$VOLNAME"
# ВАЖНО: монтируем БЕЗ -nobrowse, иначе Finder не «видит» том и оформление
# через osascript падает с ошибкой -1728 («Can't get disk»).
DEVICE=$(hdiutil attach "$RW_DMG" -noautoopen -mountpoint "$MOUNT_DIR" | egrep '^/dev/' | head -1 | awk '{print $1}')
echo "    устройство: $DEVICE  точка монтирования: $MOUNT_DIR"

echo "==> Копирование содержимого в DMG"
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"
BG_NAME=""
if [[ -n "$BG_IMAGE" ]]; then
	mkdir -p "$MOUNT_DIR/.background"
	BG_NAME="$(basename "$BG_IMAGE")"
	cp "$BG_IMAGE" "$MOUNT_DIR/.background/$BG_NAME"
fi

# ---------------------------------------------------------------------------
# 4. Оформление окна через Finder/osascript (best-effort)
# ---------------------------------------------------------------------------
STYLED=0
echo "==> Оформление окна DMG (best-effort)"
set +e
if [[ -n "$BG_NAME" ]]; then
osascript <<APPLESCRIPT
tell application "Finder"
	tell disk "$VOLNAME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {400, 120, $((400 + WIN_W)), $((120 + WIN_H))}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to $ICON_SIZE
		set background picture of viewOptions to file ".background:$BG_NAME"
		set position of item "$APP_NAME.app" of container window to {$APP_ICON_X, $APP_ICON_Y}
		set position of item "Applications" of container window to {$APPS_ICON_X, $APPS_ICON_Y}
		update without registering applications
		delay 1
		close
	end tell
end tell
APPLESCRIPT
	STYLED=$?
else
	STYLED=1
fi
set -e

if [[ "$STYLED" -eq 0 ]]; then
	echo "==> Оформление применено успешно (styled)"
else
	echo "!! Оформление не применено (osascript/Finder недоступен) — будет ПЛОСКИЙ DMG (fallback)"
fi

# Дать Finder записать .DS_Store
sync
sleep 1

# ---------------------------------------------------------------------------
# 5. Размонтирование и конвертация в сжатый UDZO
# ---------------------------------------------------------------------------
echo "==> Размонтирование"
hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true

echo "==> Конвертация в сжатый DMG (UDZO)"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL_DMG" >/dev/null
rm -f "$RW_DMG"

# ---------------------------------------------------------------------------
# 6. Итог
# ---------------------------------------------------------------------------
echo ""
if [[ "$STYLED" -eq 0 ]]; then
	echo "==> ГОТОВО (styled DMG): $FINAL_DMG"
else
	echo "==> ГОТОВО (plain/fallback DMG): $FINAL_DMG"
fi
ls -lh "$FINAL_DMG"
