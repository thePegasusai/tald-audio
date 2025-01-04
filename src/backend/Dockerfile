# Build stage
FROM node:18-alpine AS builder

# Install build essentials
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    curl \
    git

# Set working directory
WORKDIR /app

# Copy package files first for better layer caching
COPY package*.json ./

# Install all dependencies including devDependencies
RUN npm ci

# Copy source code and config files
COPY tsconfig.json ./
COPY src/ ./src/

# Build the application
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# Runtime stage
FROM node:18-alpine

# Install dumb-init for proper signal handling
RUN apk add --no-cache \
    dumb-init \
    curl \
    tzdata

# Create non-root user/group
RUN addgroup -g 1001 -S node && \
    adduser -u 1001 -S node -G node

# Set working directory
WORKDIR /app

# Set environment variables
ENV NODE_ENV=production \
    TZ=UTC \
    TENSORFLOW_CUDA=1 \
    AUDIO_BUFFER_SIZE=1024

# Copy built artifacts and dependencies from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./

# Create and set permissions for required directories
RUN mkdir -p /app/models /app/cache && \
    chown -R node:node /app && \
    chmod -R 755 /app

# Switch to non-root user
USER node

# Volume configuration
VOLUME ["/app/models", "/app/cache"]

# Expose ports
EXPOSE 3000 8080

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Set resource limits
ENV NODE_OPTIONS="--max-old-space-size=4096"

# Security configurations
LABEL security.capabilities.drop="ALL" \
      security.capabilities.add="NET_BIND_SERVICE" \
      security.no-new-privileges="true"

# Use dumb-init as entrypoint for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Start the application
CMD ["node", "dist/main"]