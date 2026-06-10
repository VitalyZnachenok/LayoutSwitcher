# LayoutSwitcher

**[Русский](#русский) | [English](#english)**

---

<a name="русский"></a>

## Русский

Лёгкая утилита для строки меню macOS, которая исправляет текст, набранный в неправильной раскладке клавиатуры, и переключает раскладки. Работает в фоне, без иконки в Dock — только значок в строке меню.

Знакомая ситуация: написали `ghbdtn` вместо «привет»? Нажмите горячую клавишу — LayoutSwitcher мгновенно переконвертирует последнее слово или выделенный текст в правильную раскладку и переключит саму раскладку клавиатуры.

### Возможности

- **Конвертация последнего слова или выделения.** По горячей клавише преобразует последнее набранное слово либо текущее выделение между двумя настроенными раскладками. Если выделения нет, приложение само определяет и выделяет последнее слово.
- **Динамический маппинг клавиш.** Соответствие символов строится из реально установленных в системе раскладок через `UCKeyTranslate`, а не из захардкоженной таблицы. Это корректно работает для нестандартных и национальных раскладок (с фолбэком на встроенную таблицу).
- **Точное переключение по ID раскладки.** Раскладка выбирается по идентификатору из настроенной пары — без «угадывания».
- **Несколько режимов горячих клавиш:**
  - произвольная комбинация (custom combo);
  - двойной Shift (⇧⇧);
  - Ctrl + Shift (⌃⇧);
  - Fn + Shift (fn⇧);
  - одиночное короткое нажатие Alt (⌥);
  - двойное нажатие Alt (⌥⌥) с настраиваемым интервалом.
- **Автоопределение ввода в неправильной раскладке** с двумя движками детекции на выбор:
  - системный словарь (`NSSpellChecker`);
  - статистическая модель n-грамм — ловит и несловарные слова (имена, сленг).
- **Режимы автопереключения:**
  - Выкл;
  - Предупреждение звуком;
  - Авто-исправление (бета) — само меняет слово и переключает раскладку, со звуком при переключении.
- **Список исключённых приложений** — детекция не работает в выбранных программах.
- **Защита полей паролей.** Приложение не трогает поля защищённого ввода (secure input / secure text fields).
- **Запуск при старте системы** (Launch at Login).
- **Двуязычный интерфейс (RU/EN)** — по умолчанию язык системы, переключается на лету.
- **Настраиваемые звуки** с регулировкой громкости.
- **Статистика использования** конвертаций.

### Требования

- macOS 13.0 (Ventura) или новее.
- Apple Silicon и Intel (универсальная сборка).

### Разрешения

Приложению нужен доступ к **Универсальному доступу (Accessibility)** — чтобы читать выделение и эмулировать нажатия клавиш.

Как выдать:

1. Откройте **Системные настройки → Конфиденциальность и безопасность → Универсальный доступ**.
2. Включите переключатель напротив **LayoutSwitcher** (при необходимости добавьте приложение кнопкой «+»).
3. Перезапустите LayoutSwitcher.

### Установка

1. Откройте `LayoutSwitcher-2.1.dmg`.
2. Перетащите **LayoutSwitcher** в папку **Applications**.

> **Внимание (Gatekeeper).** Текущая сборка подписана сертификатом *Apple Development* и **не нотаризована** Apple. При первом запуске macOS покажет предупреждение. Откройте приложение через **правый клик (Control + клик) → «Открыть»** и подтвердите запуск. Это нужно сделать один раз.

### Сборка из исходников

- Откройте `LayoutSwitcher/LayoutSwitcher.xcodeproj` в Xcode и запустите схему **LayoutSwitcher** (конфигурация Release).
- Либо соберите DMG скриптом:

```bash
./LayoutSwitcher/scripts/make-dmg.sh
```

Готовый DMG появится в `build/LayoutSwitcher-2.1.dmg`. Скрипт использует обычную автоматическую подпись *Apple Development* и **не выполняет нотаризацию**.

> Скрипт `LayoutSwitcher/scripts/package.sh` предназначен для будущего релизного пути с сертификатом **Developer ID Application** и **нотаризацией** через `notarytool`. Используйте его, когда появится Developer ID-сертификат и профиль notarytool.

---

<a name="english"></a>

## English

A lightweight macOS menu-bar utility that fixes text typed in the wrong keyboard layout and switches layouts. It runs in the background with no Dock icon — just a status-bar item.

Typed `ghbdtn` instead of `привет`? Press a hotkey and LayoutSwitcher instantly re-converts the last word or the selected text into the correct layout and switches the keyboard layout itself.

### Features

- **Convert the last word or the selection.** A hotkey converts the last typed word or the current selection between two configured layouts. With no selection, the app detects and selects the last word automatically.
- **Dynamic key mapping.** The character mapping is built from the real installed layouts via `UCKeyTranslate`, not a hardcoded table. This works correctly for non-standard and national layouts (with a built-in table fallback).
- **Precise layout selection by ID.** The target layout is chosen by ID from the configured layout pair — no guesswork.
- **Multiple hotkey modes:**
  - custom combo;
  - double Shift (⇧⇧);
  - Ctrl + Shift (⌃⇧);
  - Fn + Shift (fn⇧);
  - single Alt tap (⌥);
  - double Alt tap (⌥⌥) with a configurable interval.
- **Automatic detection of wrong-layout typing** with two selectable engines:
  - system dictionary (`NSSpellChecker`);
  - a statistical n-gram model — also catches non-dictionary words (names, slang).
- **Auto-switch modes:**
  - Off;
  - Warning sound;
  - Auto-correct (beta) — replaces the word and switches the layout automatically, with a sound on switch.
- **Per-app exclusion list** — detection is disabled in selected apps.
- **Password/secure-field protection.** The app skips secure input (secure input / secure text fields).
- **Launch at Login.**
- **Bilingual UI (RU/EN)** — defaults to the system language, switchable at runtime.
- **Configurable sounds** with volume control.
- **Usage statistics** for conversions.

### Requirements

- macOS 13.0 (Ventura) or later.
- Apple Silicon and Intel (universal build).

### Permissions

The app needs **Accessibility** access — to read the selection and simulate keystrokes.

How to grant it:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Enable the toggle next to **LayoutSwitcher** (add it with the “+” button if needed).
3. Restart LayoutSwitcher.

### Install

1. Open `LayoutSwitcher-2.1.dmg`.
2. Drag **LayoutSwitcher** into the **Applications** folder.

> **Gatekeeper note.** This build is signed with an *Apple Development* certificate and is **not notarized** by Apple. On first launch macOS will show a warning. Open the app via **right-click (Control-click) → “Open”** and confirm. You only need to do this once.

### Build from source

- Open `LayoutSwitcher/LayoutSwitcher.xcodeproj` in Xcode and run the **LayoutSwitcher** scheme (Release configuration).
- Or build a DMG with the script:

```bash
./LayoutSwitcher/scripts/make-dmg.sh
```

The resulting DMG appears at `build/LayoutSwitcher-2.1.dmg`. The script uses ordinary automatic *Apple Development* signing and does **not** notarize.

> The `LayoutSwitcher/scripts/package.sh` script is for the future release path with a **Developer ID Application** certificate and **notarization** via `notarytool`. Use it once a Developer ID certificate and a notarytool profile are available.
