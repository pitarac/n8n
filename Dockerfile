# ---------- STAGE 1: BUILDER ----------
FROM node:20-bullseye AS builder

# Ativa corepack e pnpm (recomendado no Node 20+)
RUN corepack enable && corepack prepare pnpm@latest --activate

# Otimiza cache de deps
WORKDIR /app
COPY pnpm-lock.yaml package.json ./
# Se for monorepo com workspaces, copie tbm o pnpm-workspace.yaml
# (comente a linha abaixo se não existir)
COPY pnpm-workspace.yaml ./

# Copia manifests dos pacotes (melhor cache em monorepos)
# Se tiver uma pasta "packages", descomente:
# COPY packages/*/package.json packages/*/package.json
# Se tiver "packages" + "packages/@n8n/*", comente/ajuste conforme seu layout

# Instala dependências (sem ainda copiar o código todo)
RUN pnpm install --frozen-lockfile

# Agora copia o restante do código
COPY . .

# Build completo do monorepo (gera dist/ de cada pacote)
RUN pnpm build

# Gera árvore só de produção para runtime (pasta /out)
# O deploy do pnpm copia o código + node_modules por pacote filtrado.
# Ajuste o filtro para apontar para o CLI do n8n no teu fork (geralmente @n8n/cli).
RUN pnpm -r deploy --filter @n8n/cli --prod /out


# ---------- STAGE 2: RUNTIME ----------
FROM node:20-alpine AS runtime

# Usuário sem privilégios
RUN addgroup -S n8n && adduser -S -G n8n n8n

WORKDIR /app

# Copia o build de produção gerado no /out
COPY --from=builder /out/ ./

# Opcional: instala tini para melhor gestão de sinais (graceful shutdown)
RUN apk add --no-cache tini

# Variáveis padrão (ajusta no docker-compose em produção)
ENV N8N_PORT=5678 \
    N8N_PROTOCOL=http \
    N8N_HOST=0.0.0.0 \
    N8N_BASIC_AUTH_ACTIVE=false

# Porta padrão do n8n
EXPOSE 5678

# Permissões
RUN chown -R n8n:n8n /app
USER n8n

# HEALTHCHECK simples (ajuste caminho/timeout se usar auth)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD wget -qO- http://localhost:5678/ || exit 1

# Usa tini como init process e starta o bin do CLI
ENTRYPOINT ["/sbin/tini", "--"]

# O bin do n8n geralmente fica em packages/cli/bin/n8n dentro do deploy.
# Se o pnpm deploy colocou numa pasta diferente, ajuste abaixo.
CMD ["node", "packages/cli/bin/n8n"]
