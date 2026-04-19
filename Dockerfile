FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

# Из оригинала: логи без задержек и путь к браузерам
ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# Обновляем систему и ставим NodeSource 22 (фикс совместимости)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg build-essential python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps git && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Пользователь hermes (из оригинала)
RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# ---------- Ускоренная установка зависимостей (Кэширование) ----------
COPY package.json package-lock.json ./
COPY scripts/whatsapp-bridge/package.json scripts/whatsapp-bridge/package-lock.json scripts/whatsapp-bridge/
COPY web/package.json web/package-lock.json web/
COPY pyproject.toml ./

# Ставим всё сразу (как в оригинале), но с кэшированием
RUN npm install --prefer-offline --no-audit --no-fund --ignore-scripts && \
    (cd scripts/whatsapp-bridge && npm install --prefer-offline --no-audit) && \
    (cd web && npm install --prefer-offline --no-audit) && \
    uv venv && uv pip install --no-cache-dir -e ".[all]" || true && \
    npx playwright install --with-deps chromium --only-shell

# ---------- Исходный код ----------
COPY --chown=hermes:hermes . .

# Сборка фронтенда
RUN cd web && npm run build

# Права доступа
RUN chown -R hermes:hermes /opt/hermes /opt/data
USER hermes

ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]

# ---------- Запуск с фиксом OpenAI и вспомогательной модели ----------
ENTRYPOINT ["/bin/bash", "-c", " \
    mkdir -p /opt/data && \
    echo -e \"model:\\n  provider: \\\"openai\\\"\\n  default: \\\"$HERMES_MODEL\\\"\\n  auxiliary_provider: \\\"openai\\\"\\n  auxiliary_model: \\\"$HERMES_MODEL\\\"\" > /opt/data/config.yaml && \
    source .venv/bin/activate && \
    hermes gateway\" "]
