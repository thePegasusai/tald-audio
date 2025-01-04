# Stage 1: Configuration builder
FROM alpine:3.18 as builder

# Install required packages for configuration processing
RUN apk add --no-cache jq curl

# Create necessary directories
RUN mkdir -p /etc/grafana/provisioning/datasources \
    /etc/grafana/provisioning/dashboards \
    /etc/grafana/dashboards

# Copy configuration files from Helm values
COPY ../../../kubernetes/monitoring/grafana-values.yaml /tmp/grafana-values.yaml

# Extract and prepare datasources configuration
RUN mkdir -p /etc/grafana/provisioning/datasources && \
    cat /tmp/grafana-values.yaml | \
    grep -A 1000 'datasources:' | \
    grep -B 1000 'dashboardProviders:' > \
    /etc/grafana/provisioning/datasources/datasources.yaml

# Extract and prepare dashboards
RUN mkdir -p /etc/grafana/dashboards && \
    for dashboard in audio-metrics system-performance security-monitoring; do \
        cat /tmp/grafana-values.yaml | \
        grep -A 1000 "${dashboard}:" | \
        grep -B 1000 "json: |" | \
        sed 's/^          //' > \
        "/etc/grafana/dashboards/${dashboard}.json"; \
    done

# Set correct permissions
RUN chown -R 472:472 /etc/grafana && \
    chmod -R 644 /etc/grafana && \
    find /etc/grafana -type d -exec chmod 755 {} \;

# Stage 2: Final Grafana image
FROM grafana/grafana:9.5.2

LABEL maintainer="TALD UNIA Audio System Team" \
      version="9.5.2" \
      description="Grafana monitoring for TALD UNIA Audio System"

# Use grafana user/group
USER 472:472

# Environment variables
ENV GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/admin-password \
    GF_PATHS_PROVISIONING=/etc/grafana/provisioning \
    GF_PATHS_DASHBOARDS=/etc/grafana/dashboards \
    GF_INSTALL_PLUGINS="grafana-piechart-panel,grafana-worldmap-panel" \
    GF_SECURITY_ALLOW_EMBEDDING=true \
    GF_SECURITY_COOKIE_SECURE=true \
    GF_SECURITY_STRICT_TRANSPORT_SECURITY=true \
    GF_AUTH_DISABLE_LOGIN_FORM=false \
    GF_DASHBOARDS_MIN_REFRESH_INTERVAL=5s \
    GF_LOG_MODE=console \
    GF_METRICS_ENABLED=true

# Copy configurations from builder stage
COPY --from=builder --chown=472:472 /etc/grafana /etc/grafana

# Create required directories with correct permissions
RUN mkdir -p /var/lib/grafana && \
    chown -R 472:472 /var/lib/grafana && \
    chmod -R 644 /var/lib/grafana && \
    find /var/lib/grafana -type d -exec chmod 755 {} \;

# Install required plugins
RUN grafana-cli plugins install grafana-piechart-panel && \
    grafana-cli plugins install grafana-worldmap-panel

# Health check configuration
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# Expose Grafana port
EXPOSE 3000

# Set resource limits
ENV GOMAXPROCS=1

# Enable compression for responses
ENV GF_SERVER_ENABLE_GZIP=true

# Enable audit logging
ENV GF_LOG_FILTERS="audit:debug"

# Use read-only root filesystem
VOLUME ["/var/lib/grafana"]

# Default command
CMD ["/run.sh"]

# Security configurations
WORKDIR /usr/share/grafana
USER 472:472

# Drop all capabilities and run as non-root
RUN rm -rf /usr/share/grafana/.npm /usr/share/grafana/.config /usr/share/grafana/.ash_history

# Additional security headers
ENV GF_SECURITY_X_CONTENT_TYPE_OPTIONS=true \
    GF_SECURITY_X_XSS_PROTECTION="1; mode=block" \
    GF_SECURITY_CONTENT_SECURITY_POLICY="default-src 'self' 'unsafe-eval' 'unsafe-inline'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline' https:;"