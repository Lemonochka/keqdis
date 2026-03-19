<div align="center">

# KEQDIS

**Современный VPN-клиент для Windows на базе Xray и sing-box**

[![Platform](https://img.shields.io/badge/platform-Windows-blue?style=flat-square&logo=windows)](https://github.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-1.3.0-green?style=flat-square)](https://github.com)

</div>

---

## О проекте

KEQDIS — десктопный VPN-клиент с графическим интерфейсом для Windows (в будущем для android) на Flutter. Использует [Xray-core](https://github.com/XTLS/Xray-core) и [sing-box](https://github.com/SagerNet/sing-box), поддерживает два режима работы и гибкую маршрутизацию трафика на уровне доменов, IP-адресов и отдельных приложений.

## Возможности

### Серверы
- Добавление серверов вручную конфигом
- Подписки с авто обновлением каждые 12 часов
- Пинг-тест серверов
- Избранное и сортировка по приоритету
- Определение страны сервера по флагу/имени

### Маршрутизация
- Правила для доменов: прямое подключение, через VPN, блокировка
- Правила для IP-адресов и подсетей (CIDR)
- Готовые пресеты: Россия, Google, Microsoft, соцсети и другие
- **Маршрутизация по приложениям** (только для TUN) — выбор конкретных процессов в удобном графическом списке
  - Режим «только выбранные»
  - Режим «всё кроме выбранных»

### Интерфейс
- Тёмная тема с настраиваемыми цветами
- Кастомный фоновый рисунок с размытием
- Системный трей — сворачивание без закрытия
- Уведомления о статусе подключения

### Банальные возможности
- Автозапуск при старте Windows
- Запуск свёрнутым в трей
- Portable-режим — все настройки хранятся рядом с `.exe`

## Установка

### Portable

1. Скачайте архив из [Releases](https://github.com/releases)
2. Распакуйте в любую папку
3. Запустите `keqdis.exe`

> Для TUN-режима запустите от имени администратора

### Требования
- Windows 10 или новее
- Права администратора — для TUN-режима

## Быстрый старт

1. Добавьте сервер через кнопку **+** или вставьте конфиг из буфера обмена
2. Выберите сервер в списке
3. Нажмите кнопку питания для подключения

## Сборка из исходников

### Зависимости
- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x
- Windows SDK
- Visual Studio 2022 (компонент «Разработка классических приложений на C++»)

```bash
git clone https://github.com/Lemonochka/keqdis.git
cd keqdis
flutter pub get
flutter build windows --release
```

Собранное приложение будет в `build\windows\x64\runner\Release\`.

### Бинарные зависимости

Положите в `assets/bin/`:

| Источники |
| `xray.exe` | [XTLS/Xray-core](https://github.com/XTLS/Xray-core/releases) |
| `sing-box.exe` | [SagerNet/sing-box](https://github.com/SagerNet/sing-box/releases) |
| `wintun.dll` | [wintun.net](https://www.wintun.net) |
| `geoip.dat` | [v2fly/geoip](https://github.com/v2fly/geoip/releases) |
| `geosite.dat` | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community/releases) |

##

<div align="center">
  <sub>Сделано с Flutter для моих друзяшек и тд❤️</sub>
</div>
