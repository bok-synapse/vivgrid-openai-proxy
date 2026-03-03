# ─────────────────────────────────────────────
# Stage 1 – Build
# ─────────────────────────────────────────────
FROM node:22-alpine AS builder

# Enable pnpm via corepack (matches the project toolchain)
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Copy manifests first so dependency layers are cached independently of source
COPY package.json ./

# Install all dependencies (dev + prod); no lockfile in repo so skip frozen check
RUN pnpm install --no-frozen-lockfile

# Copy source files
COPY tsconfig.json ./
COPY src           ./src

# Compile TypeScript → dist/
RUN pnpm run build

# Drop dev-only packages to shrink the final image
RUN pnpm prune --prod

# ─────────────────────────────────────────────
# Stage 2 – Runtime (lean production image)
# ─────────────────────────────────────────────
FROM node:22-alpine AS runner

# Create a dedicated non-root user/group
RUN addgroup -S vivgrid && adduser -S vivgrid -G vivgrid

WORKDIR /app

# Copy only the compiled output and production node_modules
COPY --from=builder --chown=vivgrid:vivgrid /app/dist          ./dist
COPY --from=builder --chown=vivgrid:vivgrid /app/node_modules  ./node_modules
COPY --from=builder --chown=vivgrid:vivgrid /app/package.json  ./

# Config directory – keys.json / models.json are mounted here at runtime
# so they never bake secrets into the image layer
RUN mkdir -p /app/config && chown vivgrid:vivgrid /app/config

USER vivgrid

EXPOSE 8787

# Health-check hits the /health endpoint the app already exposes
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget -qO- "http://localhost:${PROXY_PORT:-8787}/health" || exit 1

CMD ["node", "dist/main.js"]
