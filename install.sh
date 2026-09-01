#!/bin/sh
set -eu

# Путь к директории, где находится этот скрипт
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# Директория с .deb пакетами
PACKAGES_DIR="$SCRIPT_DIR/docker/packages"

# Docker config
DAEMON_JSON="/etc/docker/daemon.json"

# ============================================
# Настройки
# ============================================

DOCKER_MIRROR="https://mirror.gcr.io"

# ============================================
# Проверка root
# ============================================

if [ "$(id -u)" -ne 0 ]; then
    echo "Ошибка: скрипт необходимо запускать от root." >&2
    exit 1
fi

# ============================================
# Установка пакетов
# ============================================

if [ ! -d "$PACKAGES_DIR" ]; then
    echo "Ошибка: директория с пакетами не найдена:"
    echo "  $PACKAGES_DIR"
    exit 1
fi

echo "Установка пакетов из:"
echo "  $PACKAGES_DIR"
echo

FOUND_PACKAGES=0

for package in "$PACKAGES_DIR"/*.deb; do
    [ -f "$package" ] || continue

    FOUND_PACKAGES=1

    echo "Установка: $(basename "$package")"
    apt install -y "$package"
done

if [ "$FOUND_PACKAGES" -eq 0 ]; then
    echo "Предупреждение: .deb пакеты не найдены в $PACKAGES_DIR"
fi

# ============================================
# Настройка Docker Registry Mirror
# ============================================

echo
echo "Настройка Docker Registry Mirror:"
echo "  $DOCKER_MIRROR"

# Создаём директорию, если её нет
mkdir -p "$(dirname "$DAEMON_JSON")"

# Если daemon.json уже существует — делаем backup
if [ -f "$DAEMON_JSON" ]; then
    BACKUP="${DAEMON_JSON}.backup.$(date +%Y%m%d-%H%M%S)"

    cp "$DAEMON_JSON" "$BACKUP"

    echo "Создан backup:"
    echo "  $BACKUP"
fi

# ============================================
# Изменение daemon.json
# ============================================

python3 - "$DAEMON_JSON" "$DOCKER_MIRROR" <<'PY'
import json
import os
import sys
import tempfile

daemon_json = sys.argv[1]
mirror = sys.argv[2]

# Читаем существующий конфиг
if os.path.exists(daemon_json) and os.path.getsize(daemon_json) > 0:
    try:
        with open(daemon_json, "r", encoding="utf-8") as f:
            config = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Ошибка: {daemon_json} содержит некорректный JSON:", file=sys.stderr)
        print(e, file=sys.stderr)
        sys.exit(1)
else:
    config = {}

# Проверяем, что корень JSON — объект
if not isinstance(config, dict):
    print(
        f"Ошибка: корнем {daemon_json} должен быть JSON-объект.",
        file=sys.stderr
    )
    sys.exit(1)

# Устанавливаем Docker Registry Mirror
config["registry-mirrors"] = [mirror]

# Записываем сначала во временный файл
directory = os.path.dirname(daemon_json) or "."

fd, temp_path = tempfile.mkstemp(
    prefix=".daemon.json.",
    dir=directory,
    text=True
)

try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # Атомарно заменяем старый конфиг
    os.replace(temp_path, daemon_json)

except Exception:
    try:
        os.unlink(temp_path)
    except OSError:
        pass
    raise
PY

# ============================================
# Проверка конфигурации
# ============================================

echo
echo "Новый $DAEMON_JSON:"
cat "$DAEMON_JSON"

# ============================================
# Перезапуск Docker
# ============================================

echo
echo "Перезапуск Docker..."

systemctl restart docker

echo
echo "Docker status:"
systemctl --no-pager --full status docker || true

echo
echo "Готово."