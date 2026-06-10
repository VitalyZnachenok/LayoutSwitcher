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

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "==> Очистка прошлых артефактов"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$BUILD_DIR"

echo "==> Архивирование (Release, Hardened Runtime, Developer ID)"
xcodebuild archive \
	-project "$PROJECT" \
	-scheme "$SCHEME" \
	-configuration Release \
	-archivePath "$ARCHIVE_PATH" \
	-destination "generic/platform=macOS" \
	CODE_SIGN_STYLE=Automatic \
	DEVELOPMENT_TEAM="$TEAM_ID" \
	"CODE_SIGN_IDENTITY=Developer ID Application"

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

echo "==> Подготовка содержимого DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

echo "==> Создание DMG"
hdiutil create \
	-volname "$APP_NAME" \
	-srcfolder "$DMG_STAGE" \
	-ov -format UDZO \
	"$DMG_PATH"

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

echo "==> Готово: $DMG_PATH"
