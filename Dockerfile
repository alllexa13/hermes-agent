FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg build-essential python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps git && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes
COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# КЭШИРУЕМ ЗАВИСИМОСТИ (Они не будут переустанавливаться при изменении кода)
COPY package.json package-lock.json ./
RUN npm install --prefer-offline --no-audit --no-fund --ignore-scripts

# КЭШИРУЕМ PYTHON ЗАВИСИМОСТИ (Это сэкономит те самые 20 минут)
COPY pyproject.toml ./
RUN uv venv && uv pip install --no-cache-dir -e ".[all]" || true

# Устанавливаем playwright
RUN node node_modules/agent-browser/scripts/postinstall.js || true
RUN npx playwright install --with-deps chromium --only-shell

# Копируем остальное (теперь любое изменение кода не сбросит установку библиотек сверху)
COPY --chown=hermes:hermes . .

RUN cd web && npm run build
RUN chown hermes:hermes /opt/hermes
USER hermes

ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]

ENTRYPOINT ["/bin/bash", "-c", "mkdir -p /opt/data && echo 'provider: openai' > /opt/data/config.yaml && echo \"model: $HERMES_MODEL\" >> /opt/data/config.yaml && echo 'auxiliary_provider: openai' >> /opt/data/config.yaml && echo \"auxiliary_model: $HERMES_MODEL\" >> /opt/data/config.yaml && source .venv/bin/activate && hermes gateway"]
