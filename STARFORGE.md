# Star Forge — визуальные звёзды в Telegram-iOS

## Что добавлено

Виртуальный (визуальный) баланс звёзд: можно ввести любое число, и оно
появится в настоящих экранах баланса Telegram. Ничего не списывается и не
начисляется — меняется только то, что рисует приложение.

## Как пользоваться

1. Настройки → **Данные и память**.
2. Секция **Другое** → строка **Изменить звёзды** (с подписью «визуально»).
3. Ввести количество звёзд и нажать **Применить**.
4. Число начнёт показываться в реальных экранах:
   - Настройки → **Мои звёзды** (большой баланс и верхняя плашка);
   - строка «Мои звёзды» в настройках;
   - магазин подарков и экран выбора подарка;
   - экран покупки звёзд;
   - плашка баланса в экранах отправки звёзд;
   - контекстное меню баланса в магазине подарков.
5. Кнопка **Сбросить к реальному** убирает подмену и возвращает настоящий
   баланс. Подмена живёт до перезапуска приложения.

В том же оверлее внизу остался **визуальный перевод NFT-подарка**: карточка
берёт первый уникальный подарок из профиля (иначе демо-`Plush Pepe #1`),
летит в аватар получателя и взрывается звёздами. По умолчанию получатель —
«Избранное».

GRAM не затрагивается: подменяется только баланс звёзд.

## Файлы

Новые файлы (Bazel подхватывает их автоматически через существующие
`glob(["Sources/**/*.swift"])`, правки BUILD не требуются):

```
submodules/TelegramCore/Sources/StarForgeBalanceOverride.swift
submodules/TelegramUI/Sources/StarForge/StarForgeModels.swift
submodules/TelegramUI/Sources/StarForge/StarForgeView.swift
submodules/TelegramUI/Sources/StarForge/StarForgeController.swift
```

Правки существующих файлов:

```
submodules/AccountContext/Sources/AccountContext.swift
    + метод протокола SharedAccountContext.makeStarForgeController

submodules/TelegramUI/Sources/SharedAccountContext.swift
    + реализация makeStarForgeController

submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift
    + строка «Изменить звёзды» в секции «Другое»

submodules/TelegramUI/Components/Stars/StarsBalanceOverlayComponent/Sources/StarsBalanceOverlayComponent.swift
submodules/TelegramUI/Components/Gifts/GiftStoreScreen/Sources/BalanceComponent.swift
submodules/TelegramUI/Components/Gifts/GiftStoreScreen/Sources/GiftStoreScreen.swift
submodules/TelegramUI/Components/Gifts/GiftOptionsScreen/Sources/GiftOptionsScreen.swift
submodules/TelegramUI/Components/Stars/StarsTransactionsScreen/Sources/StarsTransactionsScreen.swift
submodules/TelegramUI/Components/Stars/StarsPurchaseScreen/Sources/StarsPurchaseScreen.swift
submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift
    + подстановка визуального баланса только в отображение

submodules/TelegramUI/Sources/ChatControllerNode.swift
    не изменён: жест двойного тапа в чате убран,
    восстановлен из .starforge.bak
```

Как это работает: `StarForgeBalanceOverride` в `TelegramCore` хранит
override-баланс (сессионный, в памяти). UI-компоненты читают его на этапе
отрисовки и подставляют вместо настоящего числа. Логика платежей, движок и
сеть override не видят, поэтому реальные звёзды не тратятся.

## Как собрать IPA

Важно понимать: сам iOS-бинарник компилирует тулчейн Apple (`swiftc`/`clang`
под `arm64-apple-ios`, `iPhoneOS.sdk`, линкер, `codesign`). Он поставляется
только внутри Xcode и только под macOS, поэтому Python-скрипт не может
*заменить* компиляцию — он может только прогнать весь конвейер. Драйвер
`starforge_build.py` делает именно это.

### Диагностика

```bash
python3 starforge_build.py --check
```

### Вариант 1. Свой Mac

Требуется macOS с Xcode (версия из `versions.json`, сейчас `27.1`), Python 3,
около 60 ГБ свободного места и 1–3 часа на первый билд.

```bash
python3 starforge_build.py
```

Драйвер:

1. импортирует тестовые сертификаты из `build-system/fake-codesigning`;
2. запускает `Make.py build` в конфигурации `release_arm64`;
3. находит `Telegram.ipa` и кладёт его в `build-artifacts/`.

Полезные флаги: `--source DIR`, `--out DIR`, `--cache-dir DIR`,
`--build-number N`, `--xcode-version V` (обойти проверку версии Xcode),
`--config PATH`, `--signing DIR`.

### Вариант 2. GitHub Actions (без своего Mac)

В репозиторий добавлен workflow `.github/workflows/build-starforge.yml`,
который собирает unsigned IPA на macOS-раннере. Запушить форк в свой
GitHub, затем:

```bash
python3 starforge_build.py --github ВАШ_ЛОГИН/Telegram-iOS --ref master
```

Драйвер запускает workflow через GitHub CLI (`gh`), ждёт сборку и качает
готовый артефакт. Либо вручную: вкладка Actions → «Star Forge IPA» →
Run workflow. На раннере должен быть доступен Xcode из `versions.json`;
если его нет, workflow предупредит и соберёт на установленной версии
(флаг `--overrideXcodeVersion`).

### Установка

Собранный IPA подписан тестовыми сертификатами, поэтому перед установкой его
нужно переподписать:

1. Sideloadly / AltStore / Xcode;
2. свой Apple ID (бесплатный аккаунт — 7 дней на подпись);
3. установка на подключённый iPhone.

## Откат

Восстановить исходный `ChatControllerNode.swift` из
`ChatControllerNode.swift.starforge.bak`, удалить папку
`submodules/TelegramUI/Sources/StarForge` и файл
`submodules/TelegramCore/Sources/StarForgeBalanceOverride.swift`, затем убрать
из перечисленных выше файлов строки с `StarForgeBalanceOverride` и
`makeStarForgeController`.
