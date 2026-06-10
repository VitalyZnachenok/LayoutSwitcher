#!/usr/bin/env bash
#
# Сборка, подпись (Developer ID), нотаризация и упаковка LayoutSwitcher в DMG.
#
# Что делает:
#   1. Архивирует Release-сборку с Hardened Runtime.
#   2. Экспортирует .app, подписанный сертификатом "Developer ID Application".
#   3. Собирает DMG (с ярлыком /Applications для drag-n-drop установки).
#   4. Отправляет DMG на нотаризацию через notarytool и ждёт результат.
#   5. Пристёгивает (staple) тикет нотаризации к DMG.
#
# Предварительная настройка (один раз):
#   - Установите сертификат "Developer ID Application" в Keychain (Xcode → Settings → Accounts → Manage Certificates).
#   - Сохраните профиль notarytool с app-specific паролем:
#       xcrun notarytool store-credentials "LayoutSwitcherNotary" \
#         --apple-id "ваш@apple.id" --team-id "AVSS84MH6D" --password "xxxx-xxxx-xxxx-xxxx"
#     (app-specific пароль создаётся на https://appleid.apple.com → Sign-In and Security)
#
# Запуск:
#   ./scripts/package.sh
#   NOTARY_PROFILE="ИмяПрофиля" ./scripts/package.sh        # другой профиль
#   SKIP_NOTARIZE=1 ./scripts/package.sh                     # только собрать DMG, без нотаризации
#
set -euo pipefail

# --- Конфигурация ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/LayoutSwitcher.xcodeproj"
SCHEME="LayoutSwitcher"
APP_NAME="LayoutSwitcher"
TEAM_ID="AVSS84MH6D"
NOTARY_PROFILE="${NOTARY_PROFILE:-LayoutSwitcherNotary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "==> Очистка прошлых артефактов"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$BUILD_DIR"

echo "==> Архивирование (Release, Hardened Runtime, автоматическая подпись)"
# Архивируем с автоматической подписью проекта (Apple Development).
# Перекодирование на "Developer ID Application" выполняет шаг exportArchive
# с ExportOptions.plist (method=developer-id). Ручной override CODE_SIGN_IDENTITY
# здесь конфликтует с automatic signing, поэтому его не задаём.
xcodebuild archive \
	-project "$PROJECT" \
	-scheme "$SCHEME" \
	-configuration Release \
	-archivePath "$ARCHIVE_PATH" \
	-destination "generic/platform=macOS" \
	CODE_SIGN_STYLE=Automatic \
	DEVELOPMENT_TEAM="$TEAM_ID"

echo "==> Экспорт .app"
xcodebuild -exportArchive \
	-archivePath "$ARCHIVE_PATH" \
	-exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
	-exportPath "$EXPORT_DIR"

if [[ ! -d "$APP_PATH" ]]; then
	echo "Ошибка: не найден $APP_PATH" >&2
	exit 1
fi

echo "==> Проверка подписи"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# --- Создание DMG ---
# Сначала пытаемся собрать КРАСИВЫЙ (styled) DMG с фоном и раскладкой иконок,
# как в scripts/make-dmg.sh. Если что-то идёт не так (нет фона, недоступен
# Finder/osascript в headless-окружении) — откатываемся на ПРОСТОЙ DMG.
# Стилизация НЕ должна ставить под угрозу нотаризуемый результат.

SRC_BG="$SCRIPT_DIR/assets/dmg-background.png"
WIN_W=660
WIN_H=440
ICON_SIZE=110
APP_ICON_X=165
APP_ICON_Y=255
APPS_ICON_X=495
APPS_ICON_Y=255

make_plain_dmg() {
	echo "==> Создание ПРОСТОГО DMG"
	rm -rf "$DMG_STAGE" "$DMG_PATH"
	mkdir -p "$DMG_STAGE"
	cp -R "$APP_PATH" "$DMG_STAGE/"
	ln -s /Applications "$DMG_STAGE/Applications"
	hdiutil create \
		-volname "$APP_NAME" \
		-srcfolder "$DMG_STAGE" \
		-ov -format UDZO \
		"$DMG_PATH"
}

make_styled_dmg() {
	# Возвращает 0 при успехе оформления, иначе ненулевой код.
	local bg_work="$BUILD_DIR/dmg-bg"
	local rw_dmg="$BUILD_DIR/$APP_NAME-rw.dmg"
	local volname="$APP_NAME"
	local mount_dir="/Volumes/$volname"
	local bg_image="" bg_name="" device=""

	rm -rf "$bg_work" "$rw_dmg" "$DMG_PATH"
	mkdir -p "$bg_work"

	[[ -f "$SRC_BG" ]] || { echo "!! Фон не найден ($SRC_BG)"; return 1; }

	sips -z "$WIN_H" "$WIN_W" "$SRC_BG" --out "$bg_work/background.png" >/dev/null 2>&1 || true
	sips -z $((WIN_H * 2)) $((WIN_W * 2)) "$SRC_BG" --out "$bg_work/background@2x.png" >/dev/null 2>&1 || true
	if [[ -f "$bg_work/background.png" && -f "$bg_work/background@2x.png" ]] \
		&& tiffutil -cathidpicheck "$bg_work/background.png" "$bg_work/background@2x.png" \
			-out "$bg_work/background.tiff" >/dev/null 2>&1; then
		bg_image="$bg_work/background.tiff"
	elif [[ -f "$bg_work/background.png" ]]; then
		bg_image="$bg_work/background.png"
	else
		echo "!! Не удалось подготовить фон"
		return 1
	fi

	local app_mb dmg_mb
	app_mb=$(du -sm "$APP_PATH" | awk '{print $1}')
	dmg_mb=$(( app_mb + 60 ))
	hdiutil create -size "${dmg_mb}m" -fs HFS+ -volname "$volname" -ov "$rw_dmg" >/dev/null || return 1

	device=$(hdiutil attach "$rw_dmg" -noautoopen -mountpoint "$mount_dir" 2>/dev/null | egrep '^/dev/' | head -1 | awk '{print $1}')
	[[ -n "$device" ]] || { echo "!! Не удалось смонтировать RW DMG"; return 1; }

	# Гарантируем размонтирование при любом выходе из функции.
	_cleanup_styled() {
		hdiutil detach "$device" -force >/dev/null 2>&1 \
			|| hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
	}

	cp -R "$APP_PATH" "$mount_dir/" || { _cleanup_styled; return 1; }
	ln -s /Applications "$mount_dir/Applications" || { _cleanup_styled; return 1; }
	mkdir -p "$mount_dir/.background"
	bg_name="$(basename "$bg_image")"
	cp "$bg_image" "$mount_dir/.background/$bg_name" || { _cleanup_styled; return 1; }

	local styled=0
	set +e
	osascript <<APPLESCRIPT
tell application "Finder"
	tell disk "$volname"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {400, 120, $((400 + WIN_W)), $((120 + WIN_H))}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to $ICON_SIZE
		set background picture of viewOptions to file ".background:$bg_name"
		set position of item "$APP_NAME.app" of container window to {$APP_ICON_X, $APP_ICON_Y}
		set position of item "Applications" of container window to {$APPS_ICON_X, $APPS_ICON_Y}
		update without registering applications
		delay 1
		close
	end tell
end tell
APPLESCRIPT
	styled=$?
	set -e

	sync
	sleep 1
	_cleanup_styled

	[[ "$styled" -eq 0 ]] || { echo "!! osascript/Finder недоступен (код $styled)"; rm -f "$rw_dmg"; return 1; }

	hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null || { rm -f "$rw_dmg"; return 1; }
	rm -f "$rw_dmg"
	return 0
}

echo "==> Создание DMG (попытка styled, с откатом на plain)"
DMG_STYLE="plain"
set +e
make_styled_dmg
STYLE_RC=$?
set -e
if [[ "$STYLE_RC" -eq 0 && -f "$DMG_PATH" ]]; then
	DMG_STYLE="styled"
	echo "==> DMG оформлен (styled)"
else
	echo "==> Откат на ПРОСТОЙ DMG (styled недоступен)"
	make_plain_dmg
fi

echo "==> Подпись DMG (Developer ID) для корректной оценки Gatekeeper"
# Подписываем сам .dmg сертификатом Developer ID Application с защищённой
# меткой времени. Без подписи DMG spctl --context primary-signature не может
# его оценить ("no usable signature"), хотя степлинг и работает.
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
	echo "==> Нотаризация пропущена (SKIP_NOTARIZE=1). DMG не заверен Apple."
	echo "==> Готово (без нотаризации): $DMG_PATH"
	exit 0
fi

echo "==> Нотаризация (профиль: $NOTARY_PROFILE)"
xcrun notarytool submit "$DMG_PATH" \
	--keychain-profile "$NOTARY_PROFILE" \
	--wait

echo "==> Степлинг тикета нотаризации"
xcrun stapler staple "$DMG_PATH"

echo "==> Проверка результата"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" || true

echo "==> Готово ($DMG_STYLE DMG): $DMG_PATH"
