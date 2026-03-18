# 🚀 StealthNet Backup Installer

[![Version](https://img.shields.io/badge/version-0.8--beta-blue.svg)](https://github.com/Balbuto/stealthnet-backup)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange.svg)](https://ubuntu.com/)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://docker.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Автоматизированная система резервного копирования для **Remnawave-STEALTHNET-Bot** с поддержкой Telegram и Email уведомлений.

## 📋 Содержание

- [Особенности](#-особенности)
- [Быстрый старт](#-быстрый-старт)
- [Требования](#-требования)
- [Возможности](#-возможности)
- [Установка](#-установка)
- [Структура](#-структура-после-установки)
- [Использование](#-использование)
- [Конфигурация](#-конфигурация)
- [Мониторинг](#-мониторинг)
- [Безопасность](#-безопасность)
- [Обновление](#-обновление)
- [Устранение проблем](#-устранение-проблем)
- [Известные ограничения](#-известные-ограничения)
- [Лицензия](#-лицензия)

## ✨ Особенности

- 🔄 **Автоматические бэкапы** PostgreSQL базы данных с ротацией
- 📅 **Гибкое расписание** (daily/weekly/monthly) через cron
- 📊 **Политика хранения** с автоматической очисткой старых бэкапов
- 🔔 **Уведомления** в Telegram и по Email о статусе бэкапов
- 🛡️ **Безопасность** – проверки целостности, права доступа, lock-файлы
- 📈 **Индексация бэкапов** в JSON формате для удобного мониторинга
- 🔧 **Простое восстановление** одной командой
- 🐳 **Docker интеграция** – работает с контейнеризированной PostgreSQL
- 🎯 **Автоопределение** параметров из .env файла панели

## 🚀 Быстрый старт

```bash
curl -fsSL https://github.com/Balbuto/stealthnet-backup/raw/refs/heads/main/setup-backup.sh | sudo bash
```

После запуска следуйте интерактивным подсказкам для настройки.

## 📋 Требования

ОС	Ubuntu 24.04

Docker	Последняя версия с официального сайта

Панель	Remnawave-STEALTHNET-Bot (работающий)

Bash	Версия 4.0 или выше

Права	Root доступ (sudo)

## 🎯 Возможности

### 🔐 Типы бэкапов

+---------+------------------------------+------------+---------------------+
| Тип     | Расписание по умолчанию      | Хранение   | Описание            |
+=========+==============================+============+=====================+
| Daily   | 0 2 * * * (2:00)             | 7 дней     | Ежедневные бэкапы   |
+---------+------------------------------+------------+---------------------+
| Weekly  | 0 3 * * 0 (воскресенье 3:00) | 4 недели   | Еженедельные бэкапы |
+---------+------------------------------+------------+---------------------+
| Monthly | 0 4 1 * * (1 число 4:00)     | 12 месяцев | Ежемесячные бэкапы  |
+---------+------------------------------+------------+---------------------+


### 📢 Уведомления

#### Telegram
✅ Уведомления об успешном/неудачном бэкапе

📎 Отправка файлов бэкапов (до 50 МБ)

ℹ️ Детальная информация: размер, длительность, ошибки

🔗 HTML форматирование сообщений

#### Email
📧 Детальные отчеты о бэкапах

📎 Вложения (до 25 МБ)

📋 Поддержка mutt и mailutils

👥 Множество получателей

### 🛠️ Установка

#### Интерактивная установка

Скрипт проведет вас через все шаги установки:

#### 1. Конфигурация панели

* Автоопределение из .env файла
* Поиск контейнера PostgreSQL
* Ручная настройка при необходимости


#### 2. Конфигурация базы данных

* Проверка подключения к контейнеру
* Валидация учетных данных
* Тест соединения

#### 3. Настройка Telegram

* Ввод токена бота
* Проверка Chat ID
* Тестовое сообщение


#### 4. Настройка Email (опционально)

* Gmail аккаунт и App Password
* Список получателей
* Тест отправки

#### 5. Политика хранения

* Количество daily бэкапов
* Количество weekly бэкапов
* Количество monthly бэкапов


#### 6. Расписание

* Настройка времени для каждого типа
* Валидация cron выражений
* Включение/отключение авто-бэкапов


#### 7. Пути установки

* Директория установки
* Хранилище бэкапов
* Проверка прав доступа

### Автоматическое определение

Скрипт автоматически найдет:

🐘 Контейнер PostgreSQL (по compose файлу или запущенным контейнерам)

📝 Параметры БД из .env (POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD)

🤖 Токен Telegram бота из BOT_TOKEN

## 📁 Структура после установки

```text
/opt/stealthnet-backup/
├── config.env              # Конфигурация (права 600)
├── backup.sh               # Основной скрипт бэкапа
├── restore.sh              # Скрипт восстановления
├── cleanup.sh              # Очистка старых бэкапов
├── scheduler.sh            # Управление планировщиком
├── lib/
│   ├── utils.sh            # Утилиты и общие функции
│   ├── telegram.sh         # Telegram уведомления
│   └── email.sh            # Email уведомления
├── logs/                    # Логи
│   ├── backup.log          # Основной лог
│   ├── cron-daily.log      # Лог daily бэкапов
│   ├── cron-weekly.log     # Лог weekly бэкапов
│   └── cron-monthly.log    # Лог monthly бэкапов
├── tmp/                     # Временные файлы
└── backups/                 # Бэкапы
    ├── latest-backup.sql.gz # Симлинк на последний бэкап
    ├── backup-index.json    # Индекс всех бэкапов
    └── YYYY/                 # Структура по годам
        └── MM/
            └── DD/
                └── stealthnet-*-YYYY-MM-DD_HH-MM-SS.sql.gz
```

## 💻 Использование

### Создание бэкапа

```bash
# Ежедневный бэкап
/opt/stealthnet-backup/backup.sh daily

# Еженедельный бэкап
/opt/stealthnet-backup/backup.sh weekly

# Ежемесячный бэкап
/opt/stealthnet-backup/backup.sh monthly

# Тестовый бэкап (без уведомлений)
/opt/stealthnet-backup/backup.sh test
```

### Восстановление

```bash
# Последний бэкап
/opt/stealthnet-backup/restore.sh latest

# По дате (ближайший к указанной)
/opt/stealthnet-backup/restore.sh @2024-01-15

# По имени файла
/opt/stealthnet-backup/restore.sh stealthnet-daily-2024-01-15_02-00-01.sql.gz

# С опциями
/opt/stealthnet-backup/restore.sh latest --force           # Без подтверждения
/opt/stealthnet-backup/restore.sh latest --create-before   # Создать бэкап перед восстановлением
```

### Очистка старых бэкапов

```bash
# Очистить все по политике хранения
/opt/stealthnet-backup/cleanup.sh all

# Очистить только daily
/opt/stealthnet-backup/cleanup.sh daily

# Очистить только weekly
/opt/stealthnet-backup/cleanup.sh weekly

# Очистить только monthly
/opt/stealthnet-backup/cleanup.sh monthly
```

### Управление планировщиком

```bash
# Установить расписание
/opt/stealthnet-backup/scheduler.sh install

# Удалить расписание
/opt/stealthnet-backup/scheduler.sh remove

# Просмотреть текущее расписание
/opt/stealthnet-backup/scheduler.sh status
```

## 🔧 Конфигурация

Все настройки хранятся в /opt/stealthnet-backup/config.env:
```bash
# ==================== БАЗА ДАННЫХ ====================
DB_CONTAINER="stealthnet-postgres-1"     # Имя контейнера PostgreSQL
DB_NAME="stealthnet"                      # Имя базы данных
DB_USER="postgres"                        # Пользователь БД
DB_PASSWORD="your_secure_password"        # Пароль БД

# ==================== TELEGRAM ====================
TELEGRAM_ENABLED=true                      # Включить Telegram уведомления
TELEGRAM_BOT_TOKEN="123456789:ABCdef..."   # Токен бота от @BotFather
TELEGRAM_CHAT_ID="-1001234567890"          # Chat ID (от @userinfobot)

# ==================== EMAIL ====================
EMAIL_ENABLED=false                         # Включить Email уведомления
GMAIL_USER="backup@gmail.com"               # Gmail адрес
GMAIL_APP_PASSWORD="abcd efgh ijkl mnop"    # App Password (16 символов)
EMAIL_RECIPIENTS="admin@example.com"        # Получатели (через запятую)

# ==================== ХРАНЕНИЕ ====================
RETENTION_DAILY=7      # Дней хранения daily бэкапов
RETENTION_WEEKLY=4      # Недель хранения weekly бэкапов
RETENTION_MONTHLY=12    # Месяцев хранения monthly бэкапов

# ==================== РАСПИСАНИЕ ====================
SCHEDULE_DAILY="0 2 * * *"      # Ежедневно в 2:00
SCHEDULE_WEEKLY="0 3 * * 0"      # По воскресеньям в 3:00
SCHEDULE_MONTHLY="0 4 1 * *"     # 1 числа каждого месяца в 4:00

# ==================== ПРОЧЕЕ ====================
BACKUP_PREFIX="stealthnet"                    # Префикс имен файлов
COMPRESSION_LEVEL=6                            # Уровень сжатия gzip (1-9)
NOTIFICATION_TIMEOUT=60                         # Таймаут уведомлений (сек)
MAX_BACKUP_SIZE_MB=100                          # Макс. размер для отправки
```

## 📊 Мониторинг

### Логи

```bash
# Основной лог всех операций
tail -f /opt/stealthnet-backup/logs/backup.log

# Логи cron
tail -f /opt/stealthnet-backup/logs/cron-daily.log
tail -f /opt/stealthnet-backup/logs/cron-weekly.log
tail -f /opt/stealthnet-backup/logs/cron-monthly.log

# Все логи за последние сутки
find /opt/stealthnet-backup/logs -name "*.log" -mtime -1 -exec cat {} \;
```

### Индекс бэкапов

```bash
# Просмотр индекса (с jq для форматирования)
cat /opt/stealthnet-backup/backups/backup-index.json | jq .

# Пример вывода:
{
  "generated": "2024-01-15T02:00:01+00:00",
  "backups": [
    {
      "path": "2024/01/15/stealthnet-daily-2024-01-15_02-00-01.sql.gz",
      "filename": "stealthnet-daily-2024-01-15_02-00-01.sql.gz",
      "date": "2024-01-15 02:00:01",
      "size": 15728640,
      "size_human": "15 МБ"
    }
  ]
}

# Только последние 5 бэкапов
jq '.backups[:5]' /opt/stealthnet-backup/backups/backup-index.json
```

### Статистика

```bash
# Общий размер бэкапов
du -sh /opt/stealthnet-backup/backups

# Количество файлов
find /opt/stealthnet-backup/backups -name "*.sql.gz" | wc -l

# Распределение по типам
ls -la /opt/stealthnet-backup/backups/**/*.sql.gz | grep -c "daily"
ls -la /opt/stealthnet-backup/backups/**/*.sql.gz | grep -c "weekly"
ls -la /opt/stealthnet-backup/backups/**/*.sql.gz | grep -c "monthly"
```

## 🛡️ Безопасность

### Реализованные меры

+-----------------------------+------------------------------------------+
| Мера                        | Описание                                 |
+=============================+==========================================+
| 🔒 Права доступа            | config.env с правами 600, директории 750 |
+-----------------------------+------------------------------------------+
| 🔐 Lock-файлы               | Предотвращение одновременного запуска    |
+-----------------------------+------------------------------------------+
| 🛡️ Валидация путей         | Защита от path traversal атак            |
+-----------------------------+------------------------------------------+
| ✅ Проверка целостности      | Gzip -t для всех архивов                 |
+-----------------------------+------------------------------------------+
| ⏱️ Таймауты                 | Все Docker операции с timeout            |
+-----------------------------+------------------------------------------+
| 🧹 Очистка временных файлов | Автоматическое удаление                  |
+-----------------------------+------------------------------------------+
| 🔍 Проверка прав            | Валидация владельца и прав директорий    |
+-----------------------------+------------------------------------------+
| 📝 Логирование              | Детальное логирование всех операций      |
+-----------------------------+------------------------------------------+


## Рекомендации

1. Регулярно обновляйте систему и скрипт
2. Проверяйте логи на наличие ошибок
3. Тестируйте восстановление периодически
4. Храните бэкапы на отдельном диске/NFS
5. Используйте App Password для Gmail, не основной пароль

## 🔄 Обновление

Для обновления до последней версии:
```bash
# Просто перезапустите скрипт установки
curl -fsSL https://github.com/Balbuto/stealthnet-backup/raw/refs/heads/main/setup-backup.sh | sudo bash

# Скрипт обнаружит существующую установку и спросит о перезаписи
```

При обновлении:

✅ Существующая конфигурация будет сохранена (создается backup)

✅ Все скрипты будут обновлены

✅ Права доступа будут проверены

✅ Планировщик будет переустановлен при необходимости

## 🔍 Устранение проблем

### Проблемы с Docker

```bash
# Проверка запущенных контейнеров
docker ps | grep postgres

# Проверка логов контейнера
docker logs <container_name>

# Проверка подключения к PostgreSQL
docker exec -it <container_name> pg_isready
```

### Проблемы с правами

```bash
# Проверка прав на директории
ls -la /opt/stealthnet-backup/

# Исправление прав (если необходимо)
chmod 600 /opt/stealthnet-backup/config.env
chmod 750 /opt/stealthnet-backup /opt/stealthnet-backup/{logs,tmp,backups}
```

### Проблемы с уведомлениями

#### Telegram:

* Проверьте токен бота
* Убедитесь, что бот добавлен в группу
* Проверьте Chat ID (должен начинаться с - для групп)


#### Email:

* Включите 2FA на Gmail
* Создайте новый App Password
* Проверьте spam папку

### Lock-файлы

Если процесс был прерван и lock-файл остался:
```bash
# Ручное удаление lock-файлов
rm -f /opt/stealthnet-backup/tmp/*.lock

# Проверка процессов
ps aux | grep backup.sh
```

### Логи ошибок

```bash
# Поиск ошибок в логах
grep -i error /opt/stealthnet-backup/logs/*.log

# Последние ошибки
tail -50 /opt/stealthnet-backup/logs/backup.log | grep -i error
```

## ⚠️ Известные ограничения

🐧 Работает только на Ubuntu 24.04

👑 Требуется root доступ

🐳 PostgreSQL должен быть в Docker контейнере

📧 Для Email уведомлений требуется Gmail с App Password

📦 Максимальный размер файла в Telegram: 50 МБ

📎 Максимальный размер вложения email: 25 МБ

🔄 Не поддерживает инкрементальные бэкапы

## 🤝 Вклад в проект

Приветствуются:

🐛 Сообщения об ошибках

💡 Предложения по улучшению

🔧 Pull requests

📚 Документация

## 📝 Лицензия

MIT License

Copyright (c) 2024 Balbuto

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## ⭐ Поддержка проекта

Если вам помог этот инструмент:

1. Поставьте звезду на GitHub
2. Поделитесь с коллегами
3. Сообщите об ошибках
4. Предложите улучшения


### 🚀 StealthNet Backup — надежное резервное копирование для вашего бизнеса.

