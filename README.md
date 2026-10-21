# LayoutSwitcher

**[Русский](#русский) | [English](#english)**

---

<a name="русский"></a>

## Русский

Лёгкая утилита для строки меню macOS, которая исправляет текст, набранный в неправильной раскладке клавиатуры, и переключает раскладки. Работает в фоне, без иконки в Dock — только значок в строке меню.

Знакомая ситуация: написали `ghbdtn` вместо «привет»? Нажмите горячую клавишу — LayoutSwitcher мгновенно переконвертирует последнее слово или выделенный текст в правильную раскладку и переключит саму раскладку клавиатуры.

### Возможности

- **Конвертация последнего слова или выделения.** По горячей клавише преобразует последнее набранное слово либо текущее выделение между двумя настроенными раскладками. Если выделения нет, приложение само находит последнее слово перед курсором.
- **Замена через Accessibility.** Текст читается и заменяется прямо в поле ввода через AX API: без буфера обмена, синтетических нажатий и задержек (единицы миллисекунд вместо ~300 мс). Приложения, которые этого не поддерживают, автоматически обслуживаются прежним путём через ⌘C/⌘V, причём буфер обмена восстанавливается целиком, включая картинки и файлы.
- **Динамический маппинг клавиш.** Соответствие символов строится из реально установленных в системе раскладок через `UCKeyTranslate`, а не из захардкоженной таблицы. Это корректно работает для нестандартных и национальных раскладок (с фолбэком на встроенную таблицу).
- **Точное переключение по ID раскладки.** Раскладка выбирается по идентификатору из настроенной пары — без «угадывания».
- **Несколько режимов горячих клавиш:**
  - произвольная комбинация (custom combo) — записывается прямо в настройках нажатием;
  - двойной Shift (⇧⇧);
  - Ctrl + Shift (⌃⇧);
  - Fn + Shift (fn⇧);
  - одиночное короткое нажатие Alt (⌥);
  - двойное нажатие Alt (⌥⌥) с настраиваемым интервалом.
- **Автоопределение ввода в неправильной раскладке** с двумя движками детекции на выбор:
  - системный словарь (`NSSpellChecker`);
  - статистическая модель триграмм (ru, en, uk, de), обученная на частотных словарях OpenSubtitles, — ловит и несловарные слова (имена, сленг); на отложенной выборке ~0.1 % ложных срабатываний при ~97 % распознавания. Для других языков автоматически используется словарь.
- **Автодетекция для любой пары раскладок**, не только ru/en: конверсия строится по реальным раскладкам системы, язык определяется из свойств раскладки.
- **Режимы автопереключения:**
  - Выкл;
  - Предупреждение звуком;
  - Авто-исправление (бета) — само меняет слово и переключает раскладку, со звуком при переключении.
- **Список исключённых приложений** — детекция не работает в выбранных программах.
- **Защита полей паролей.** Приложение не трогает поля защищённого ввода (secure input / secure text fields).
- **Запуск при старте системы** (Launch at Login).
- **Двуязычный интерфейс (RU/EN)** — по умолчанию язык системы, переключается на лету.
- **Настраиваемые звуки** с регулировкой громкости.
- **Статистика использования** конвертаций (сохраняется между запусками).

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

1. Откройте `LayoutSwitcher-<версия>.dmg`.
2. Перетащите **LayoutSwitcher** в папку **Applications**.

Релизные сборки начиная с 3.0 подписаны сертификатом **Developer ID** и **нотаризованы** Apple — запускаются без предупреждений Gatekeeper.

### Сборка из исходников

- Откройте `LayoutSwitcher/LayoutSwitcher.xcodeproj` в Xcode и запустите схему **LayoutSwitcher** (конфигурация Release).
- Либо соберите DMG скриптом:

```bash
./LayoutSwitcher/scripts/make-dmg.sh
```

Готовый DMG появится в `build/LayoutSwitcher-<версия>.dmg` (версия берётся из `CFBundleShortVersionString` собранного `.app`). Скрипт использует обычную автоматическую подпись *Apple Development* и **не выполняет нотаризацию** — для локального использования.

Релизный DMG (Developer ID + нотаризация через `notarytool`):

```bash
NOTARY_PROFILE=<имя профиля notarytool> ./LayoutSwitcher/scripts/package.sh
```

Юнит-тесты (схема `LayoutSwitcher`, таргет `LayoutSwitcherTests`): `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'`. Код разложен по папкам `Core/` (конвертация, детекция, Accessibility), `Hotkeys/` (event tap, распознавание) и `UI/`. Модели n-грамм пересобираются скриптом `LayoutSwitcher/scripts/ngram/build_ngram.py` (см. README рядом с ним).

---

<a name="english"></a>

## English

A lightweight macOS menu-bar utility that fixes text typed in the wrong keyboard layout and switches layouts. It runs in the background with no Dock icon — just a status-bar item.

Typed `ghbdtn` instead of `привет`? Press a hotkey and LayoutSwitcher instantly re-converts the last word or the selected text into the correct layout and switches the keyboard layout itself.

### Features

- **Convert the last word or the selection.** A hotkey converts the last typed word or the current selection between two configured layouts. With no selection, the app finds the last word before the caret itself.
- **Replacement via Accessibility.** The text is read and replaced right inside the input field through the AX API: no clipboard, no synthetic keystrokes, no delays (milliseconds instead of ~300 ms). Apps that don't support it automatically fall back to the ⌘C/⌘V path, and the clipboard is restored in full, including images and files.
- **Dynamic key mapping.** The character mapping is built from the real installed layouts via `UCKeyTranslate`, not a hardcoded table. This works correctly for non-standard and national layouts (with a built-in table fallback).
- **Precise layout selection by ID.** The target layout is chosen by ID from the configured layout pair — no guesswork.
- **Multiple hotkey modes:**
  - custom combo — record it right in Settings by pressing it;
  - double Shift (⇧⇧);
  - Ctrl + Shift (⌃⇧);
  - Fn + Shift (fn⇧);
  - single Alt tap (⌥);
  - double Alt tap (⌥⌥) with a configurable interval.
- **Automatic detection of wrong-layout typing** with two selectable engines:
  - system dictionary (`NSSpellChecker`);
  - a statistical trigram model (ru, en, uk, de) trained on OpenSubtitles frequency lists — also catches non-dictionary words (names, slang); ~0.1% false positives at ~97% recall on a held-out set. Other languages fall back to the dictionary automatically.
- **Auto-detection for any layout pair**, not just ru/en: the conversion is built from the real system layouts and the language comes from the layout's properties.
- **Auto-switch modes:**
  - Off;
  - Warning sound;
  - Auto-correct (beta) — replaces the word and switches the layout automatically, with a sound on switch.
- **Per-app exclusion list** — detection is disabled in selected apps.
- **Password/secure-field protection.** The app skips secure input (secure input / secure text fields).
- **Launch at Login.**
- **Bilingual UI (RU/EN)** — defaults to the system language, switchable at runtime.
- **Configurable sounds** with volume control.
- **Usage statistics** for conversions (persisted across launches).

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

1. Open `LayoutSwitcher-<version>.dmg`.
2. Drag **LayoutSwitcher** into the **Applications** folder.

Release builds starting with 3.0 are signed with a **Developer ID** certificate and **notarized** by Apple — they launch without Gatekeeper warnings.

### Build from source

- Open `LayoutSwitcher/LayoutSwitcher.xcodeproj` in Xcode and run the **LayoutSwitcher** scheme (Release configuration).
- Or build a DMG with the script:

```bash
./LayoutSwitcher/scripts/make-dmg.sh
```

The resulting DMG appears at `build/LayoutSwitcher-<version>.dmg` (the version is read from the built `.app`'s `CFBundleShortVersionString`). The script uses ordinary automatic *Apple Development* signing and does **not** notarize — for local use.

Release DMG (Developer ID + notarization via `notarytool`):

```bash
NOTARY_PROFILE=<notarytool profile name> ./LayoutSwitcher/scripts/package.sh
```

Unit tests (scheme `LayoutSwitcher`, target `LayoutSwitcherTests`): `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'`. The code lives in `Core/` (conversion, detection, Accessibility), `Hotkeys/` (event tap, recognizers) and `UI/`. The n-gram models are rebuilt with `LayoutSwitcher/scripts/ngram/build_ngram.py` (see the README next to it).
