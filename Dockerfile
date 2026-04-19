FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

# Disable Python stdout buffering to ensure logs are printed immediately
ENV PYTHONUNBUFFERED=1

# Store Playwright browsers outside the volume mount so the build-time
# install survives the /opt/data volume overlay at runtime.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# Добавляем curl и репозиторий Node.js 22
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg build-essential python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps git && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Non-root user for runtime; UID can be overridden via HERMES_UID at runtime
RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# ---------- Layer-cached dependency install ----------
# Copy only package manifests first so npm install + Playwright are cached
# unless the lockfiles themselves change.
COPY package.json package-lock.json ./
COPY scripts/whatsapp-bridge/package.json scripts/whatsapp-bridge/package-lock.json scripts/whatsapp-bridge/
COPY web/package.json web/package-lock.json web/

# 1. Основные зависимости
RUN npm install --prefer-offline --no-audit --no-fund --loglevel verbose

# 2. Скачивание Chromium (самый долгий этап, может занимать 5-10 минут)
RUN npx playwright install --with-deps chromium --only-shell

# 3. WhatsApp Bridge
RUN cd scripts/whatsapp-bridge && npm install --prefer-offline --no-audit

# 4. Web интерфейс
RUN cd web && npm install --prefer-offline --no-audit

# 5. Очистка кэша
RUN npm cache clean --force

# ---------- Source code ----------
# .dockerignore excludes node_modules, so the installs above survive.
COPY --chown=hermes:hermes . .

# Build web dashboard (Vite outputs to hermes_cli/web_dist/)
RUN cd web && npm run build

# ---------- Python virtualenv ----------
RUN chown hermes:hermes /opt/hermes
USER hermes
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

# ---------- Runtime ----------
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
