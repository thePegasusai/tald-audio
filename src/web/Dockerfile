# Stage 1: Builder
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies and security tools
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    && npm install -g npm@9.x.x

# Copy package files
COPY package*.json ./

# Install dependencies with strict security and frozen lockfile
RUN npm ci --ignore-scripts \
    && npm audit fix \
    && npm prune --production

# Copy source code and configuration files
COPY . .

# Build optimized production bundle
RUN npm run build \
    && npm run typecheck \
    && npm run lint

# Clean up build artifacts and dependencies
RUN rm -rf node_modules/.cache \
    && rm -rf src \
    && rm -rf tests

# Stage 2: Production
FROM nginx:1.25-alpine

# Install security updates and remove unnecessary packages
RUN apk update && apk upgrade \
    && apk add --no-cache curl tzdata \
    && rm -rf /var/cache/apk/*

# Create non-root nginx user
RUN addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# Copy nginx configuration with security hardening
COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.security.conf /etc/nginx/conf.d/security.conf

# Copy built assets from builder stage
COPY --from=builder --chown=nginx:nginx /app/dist /usr/share/nginx/html

# Set correct permissions
RUN chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && chown -R nginx:nginx /etc/nginx/conf.d \
    && touch /var/run/nginx.pid \
    && chown -R nginx:nginx /var/run/nginx.pid \
    && chmod 644 /etc/nginx/nginx.conf

# Configure security headers
RUN echo "add_header X-Frame-Options 'SAMEORIGIN' always;" >> /etc/nginx/conf.d/security.conf \
    && echo "add_header X-Content-Type-Options 'nosniff' always;" >> /etc/nginx/conf.d/security.conf \
    && echo "add_header X-XSS-Protection '1; mode=block' always;" >> /etc/nginx/conf.d/security.conf \
    && echo "add_header Referrer-Policy 'strict-origin-when-cross-origin' always;" >> /etc/nginx/conf.d/security.conf \
    && echo "add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://api.tald-unia.com wss://api.tald-unia.com;\" always;" >> /etc/nginx/conf.d/security.conf

# Set environment variables
ENV NODE_ENV=production \
    NGINX_WORKER_PROCESSES=auto \
    NGINX_WORKER_CONNECTIONS=1024

# Set resource limits
ENV NGINX_WORKER_RLIMIT_NOFILE=65535 \
    NGINX_WORKER_CONNECTIONS=1024

# Expose port
EXPOSE 80

# Switch to non-root user
USER nginx

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:80/ || exit 1

# Container metadata
LABEL maintainer="TALD UNIA Development Team" \
    version="1.0.0" \
    description="TALD UNIA Web Frontend" \
    security.capabilities="minimal" \
    monitoring.enabled="true"

# Start nginx
CMD ["nginx", "-g", "daemon off;"]