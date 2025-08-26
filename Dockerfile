# syntax=docker/dockerfile:1

############################################
# STAGE 1 — BUILDER
############################################
FROM node:22-bullseye AS builder

# Habilita corepack e pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Copia manifestos p/ maximizar cache de dependências
COPY package.json pnpm-lock.yaml ./
# Se seu fork é monorepo, este arquivo deve existir
COPY pnpm-workspace.yaml . 
# Patches exigidos pelo package.json (pnpm.patches)
COPY patches/ ./patches/

# Instala dependências travadas pelo lockfile
RUN pnpm install --frozen-lockfile

# Copia restante do código
COPY . .

# Build do projeto/monorepo
RUN pnpm build

# Gera artefatos só de produção para o pacote do CLI do n8n
# ⚠️ Se o nome do pacote do CLI no teu fork for diferente, ajusta o filtro abaixo.
RUN pnpm -r deploy --filter @n8n/cli --prod /out


############################################
# STAGE 2 — RUNTIME
############################################
FROM node:22-alpine AS runtime

# tini para shutdown/ sinais limpos
RUN apk add --no-cache tini wget

# Usuário não-root
RUN addgroup -S n8n && adduser -S -G n8n n8n

WORKDIR /app

# Copia artefatos de produção do builder
COPY --from=builder /out/ ./

# Variáveis NÃO sensíveis (credenciais vão no docker-compose, não aqui)
ENV N8N_PORT=5678 \
    N8N_PROTOCOL=http \
    N8N_HOST=0.0.0.0

# Porta padrão
EXPOSE 5678

# Permissões
RUN chown -R n8n:n8n /app
USER n8n

# Healthcheck simples (ajuste se usar auth básica)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD wget -qO- http://localhost:5678/ || exit 1

ENTRYPOINT ["/sbin/tini","--"]

# ⚠️ Ajuste o caminho do bin se necessário.
# No n8n oficial, o executável fica em packages/cli/bin/n8n dentro do deploy.
CMD ["node","packages/cli/bin/n8n"]
