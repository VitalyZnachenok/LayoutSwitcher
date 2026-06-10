# Упаковка и распространение (Developer ID + нотаризация)

Сборка распространяемого `.dmg` вне Mac App Store.

## Разовая настройка

1. **Сертификат.** Установите «Developer ID Application» в Keychain:
   Xcode → Settings → Accounts → выберите команду → Manage Certificates → «+» → Developer ID Application.

2. **Профиль нотаризации.** Создайте app-specific пароль на
   https://appleid.apple.com → Sign-In and Security → App-Specific Passwords, затем:

   ```bash
   xcrun notarytool store-credentials "LayoutSwitcherNotary" \
     --apple-id "ваш@apple.id" \
     --team-id "AVSS84MH6D" \
     --password "xxxx-xxxx-xxxx-xxxx"
   ```

## Сборка DMG

```bash
cd layoutswitcher/LayoutSwitcher
./scripts/package.sh
```

Результат: `build/LayoutSwitcher.dmg` — подписанный, нотаризованный, со степлингом.

### Опции

- `SKIP_NOTARIZE=1 ./scripts/package.sh` — собрать DMG без нотаризации (для локальной проверки).
- `NOTARY_PROFILE="ДругоеИмя" ./scripts/package.sh` — использовать другой профиль notarytool.

## Что внутри

- Конфигурация Release уже включает **Hardened Runtime** (обязательно для нотаризации).
- App Sandbox **выключен** (нужно для глобального перехвата клавиатуры и Accessibility).
- Минимальная поддерживаемая версия — **macOS 13.0 (Ventura)**.

## Проверка у пользователя

После скачивания DMG Gatekeeper не должен ругаться (приложение нотаризовано). Проверить:

```bash
spctl -a -t open --context context:primary-signature -v build/LayoutSwitcher.dmg
xcrun stapler validate build/LayoutSwitcher.dmg
```
