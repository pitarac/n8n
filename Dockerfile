# ---------- STAGE 1: BUILDER ----------
FROM node:22-bullseye AS builder

# Habilita corepack e pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Copia arquivos necessários para resolver deps com cache eficiente
COPY package.json pnpm-lock.yaml ./
# Se existirem estes arquivos, copie-os também:
COPY pnpm-workspace.yaml . 2>/dev/null || true
COPY patches ./patches 2>/dev/null || true

# Instala dependências (usa lockfile)
RUN pnpm install --frozen-lockfile

# Agora copia o restante do código
COPY . .

# Build do monorepo/projeto
RUN pnpm build

# Gera artefatos só de produção do pacote CLI para /out
# ajuste o filtro se o nome do pacote for diferente
RUN pnpm -r deploy --filter @n8n/cli --prod /out


# ---------- STAGE 2: RUNTIME ----------
FROM node:22-alpine AS runtime

# tini para shutdown limpo
RUN apk add --no-cache tini

# Usuário não-root
RUN addgroup -S n8n && adduser -S -G n8n n8n
WORKDIR /app

# Copia artefatos de produção
COPY --from=builder /out/ ./

# Variáveis padrão (coloque credenciais no compose, não aqui)
ENV N8N_PORT=5678 \
    N8N_PROTOCOL=http \
    N8N_HOST=0.0.0.0 \
    N8N_BASIC_AUTH_ACTIVE=false

EXPOSE 5678

RUN chown -R n8n:n8n /app
USER n8n

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD wget -qO- http://localhost:5678/ || exit 1

ENTRYPOINT ["/sbin/tini","--"]

# ajuste o caminho do bin se necessário
CMD ["node","packages/cli/bin/n8n"]
