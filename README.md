<div align="center">

# KEQDIS

**Современный Proxy-клиент на базе Xray и sing-box**

[![Platform](https://img.shields.io/badge/platform-Windows-blue?style=flat-square&logo=windows)](https://github.com)
[![Platform](https://img.shields.io/badge/platform-Android-green?style=flat-square&logo=android)](https://github.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-1.3.0-green?style=flat-square)](https://github.com/Lemonochka/keqdis/releases/tag/A1.3.0)

</div>

---

## О проекте

KEQDIS — Proxy-клиент с графическим интерфейсом на Flutter. Использует [Xray-core](https://github.com/XTLS/Xray-core) и [sing-box](https://github.com/SagerNet/sing-box), поддерживает гибкую маршрутизацию трафика.

Доступен для **Windows** и **Android**.

---

## Возможности

### Серверы
- Добавление серверов вручную (vless://, vmess://, trojan://, ss://)
- Подписки с авто-обновлением
- Пинг-тест серверов
- Определение страны сервера по флагу

### Маршрутизация
- Правила для доменов: прямое подключение, через VPN, блокировка
- Правила для IP-адресов и подсетей (CIDR)
- Готовые пресеты: Россия, Google, Microsoft, соцсети и другие

### Split Tunneling (Android)
- Выбор конкретных приложений которые идут через VPN
- Режим «только выбранные»
- Режим «всё кроме выбранных»

### Интерфейс
- Светлая и тёмная тема
- Анимированная кнопка подключения
- Плавный свайп между вкладками

---

## Установка

### Android

1. Скачайте `.apk` из [Releases](https://github.com/Lemonochka/keqdis/releases)
2. Разрешите установку из неизвестных источников
3. Установите и запустите

> Только для устройств с архитектурой **arm64-v8a**

### Windows — Portable

1. Скачайте архив из [Releases](https://github.com/Lemonochka/keqdis/releases)
2. Распакуйте в любую папку
3. Запустите `keqdis.exe`

> Для TUN-режима запустите от имени администратора

### Системные требования

| Платформа | Требования |
|-----------|-----------|
| Android | Android 5.0+, архитектура arm64 |
| Windows | Windows 10+, права администратора для TUN |

---

## Быстрый старт

1. Добавьте сервер через кнопку **+**
2. Выберите сервер в списке
3. Нажмите кнопку подключения

---

## Сборка из исходников

### Зависимости
- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x
- Для Windows: Visual Studio 2022 (компонент «Разработка классических приложений на C++»)
- Для Android: Android SDK, JDK 17+

```bash
git clone https://github.com/Lemonochka/keqdis.git
cd keqdis
flutter pub get

# Windows
flutter build windows --release

```

### Бинарные зависимости (Windows)

Положите в `assets/bin/`:

| Файл | Источник |
|------|---------|
| `xray.exe` | [XTLS/Xray-core](https://github.com/XTLS/Xray-core/releases) |
| `sing-box.exe` | [SagerNet/sing-box](https://github.com/SagerNet/sing-box/releases) |
| `wintun.dll` | [wintun.net](https://www.wintun.net) |
| `geoip.dat` | [v2fly/geoip](https://github.com/v2fly/geoip/releases) |
| `geosite.dat` | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community/releases) |

---

<div align="center">
  <sub>Сделано с Flutter для моих друзяшек и тд ❤️</sub>
</div>
