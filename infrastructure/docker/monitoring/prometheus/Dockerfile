# Stage 1: Configuration builder
FROM alpine:3.18 AS builder

# Install necessary utilities
RUN apk add --no-cache curl=8.4.0-r0 jq=1.6-r3

# Create configuration directories
RUN mkdir -p /etc/prometheus/rules && \
    chmod 755 /etc/prometheus && \
    chmod 755 /etc/prometheus/rules

# Copy prometheus configuration and rules
COPY prometheus-values.yaml /tmp/prometheus-values.yaml

# Extract and validate configuration
RUN mkdir -p /tmp/prometheus && \
    cat /tmp/prometheus-values.yaml | \
    grep -A 1000 'prometheus:' | \
    sed 's/^prometheus://' > /etc/prometheus/prometheus.yml && \
    chmod 644 /etc/prometheus/prometheus.yml

# Create rule files from configuration
RUN mkdir -p /etc/prometheus/rules && \
    for rule in audio_quality system_performance; do \
        cat /tmp/prometheus-values.yaml | \
        grep -A 1000 "rules:" | \
        grep -A 1000 "$rule:" > "/etc/prometheus/rules/${rule}.rules" && \
        chmod 644 "/etc/prometheus/rules/${rule}.rules"; \
    done

# Stage 2: Final Prometheus image
FROM prom/prometheus:v2.45.0

# Labels for image identification and tracking
LABEL maintainer="TALD UNIA Development Team" \
      version="2.45.0" \
      description="TALD UNIA Audio System Prometheus Monitoring"

# Copy configuration from builder stage
COPY --from=builder /etc/prometheus /etc/prometheus

# Set secure permissions
RUN chown -R nobody:nogroup /etc/prometheus && \
    chmod -R 644 /etc/prometheus && \
    chmod 755 /etc/prometheus/rules

# Create and set permissions for data directory
RUN mkdir -p /prometheus && \
    chown -R nobody:nogroup /prometheus && \
    chmod 644 /prometheus

# Security configurations
USER nobody
EXPOSE 9090

# Set resource limits via environment variables
ENV GOGC="40" \
    GOMAXPROCS="2"

# Configure storage retention and performance settings
ENV PROMETHEUS_STORAGE_TSDB_RETENTION_TIME="30d" \
    PROMETHEUS_STORAGE_TSDB_RETENTION_SIZE="50GB" \
    PROMETHEUS_STORAGE_TSDB_WAL_SEGMENT_SIZE="128MB" \
    PROMETHEUS_STORAGE_TSDB_MIN_BLOCK_DURATION="2h" \
    PROMETHEUS_STORAGE_TSDB_MAX_BLOCK_DURATION="24h"

# Health check configuration
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:9090/-/healthy || exit 1

# Volume configuration for persistent storage
VOLUME ["/prometheus", "/etc/prometheus"]

# Command with security and performance optimizations
ENTRYPOINT [ "/bin/prometheus" ]
CMD [ \
    "--config.file=/etc/prometheus/prometheus.yml", \
    "--storage.tsdb.path=/prometheus", \
    "--storage.tsdb.retention.time=30d", \
    "--storage.tsdb.retention.size=50GB", \
    "--web.console.libraries=/usr/share/prometheus/console_libraries", \
    "--web.console.templates=/usr/share/prometheus/consoles", \
    "--web.enable-lifecycle", \
    "--web.enable-admin-api=false", \
    "--web.external-url=http://localhost:9090", \
    "--web.route-prefix=/", \
    "--log.level=info", \
    "--storage.tsdb.wal-compression", \
    "--storage.tsdb.allow-overlapping-blocks=false", \
    "--query.max-samples=50000000", \
    "--query.timeout=2m", \
    "--query.max-concurrency=20", \
    "--rules.alert.for-grace-period=1m", \
    "--rules.alert.for-outage-tolerance=5m", \
    "--rules.alert.resend-delay=5m" \
]