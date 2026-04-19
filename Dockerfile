FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

# Отключаем буферизацию вывода Python для мгновенного появления логов
ENV PYTHONUNBUFFERED=1

# Путь для браузеров Playwright
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# 1. Установка системных зависимостей и Node.js 22
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg build-essential python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps git && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Создаем пользователя hermes
RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# 2. Копируем манифесты пакетов для кэширования слоев
COPY package.json package-lock.json ./
COPY scripts/whatsapp-bridge/package.json scripts/whatsapp-bridge/package-lock.json scripts/whatsapp-bridge/
COPY web/package.json web/package-lock.json web/

# 3. Установка JS-зависимостей (без автоматических скриптов)
RUN npm install --prefer-offline --no-audit --no-fund --ignore-scripts

# 4. Установка бинарных файлов агента
RUN node node_modules/agent-browser/scripts/postinstall.js || true

# 5. Установка браузера Chromium (этот шаг стабилен)
RUN npx playwright install --with-deps chromium --only-shell

# 6. Установка зависимостей для внутренних модулей
RUN cd scripts/whatsapp-bridge && npm install --prefer-offline --no-audit
RUN cd web && npm install --prefer-offline --no-audit

# 7. Очистка кэша NPM
RUN npm cache clean --force

# 8. Копируем исходный код
COPY --chown=hermes:hermes . .

# 9. Сборка веб-панели
RUN cd web && npm build || cd web && npm run build

# 10. Настройка Python окружения (виртуальная среда)
RUN chown hermes:hermes /opt/hermes
USER hermes
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

# Настройки запуска
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
