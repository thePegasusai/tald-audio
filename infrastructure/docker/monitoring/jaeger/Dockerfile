# Stage 1: Configuration preparation
FROM alpine:3.18 as builder

# Install required packages
RUN apk add --no-cache jq gettext

# Create configuration directories
RUN mkdir -p /etc/jaeger/sampling \
    && mkdir -p /etc/jaeger/tracing \
    && chown -R 1000:1000 /etc/jaeger

# Copy and prepare sampling configuration
COPY --chown=1000:1000 sampling.json /etc/jaeger/sampling/
RUN cat > /etc/jaeger/sampling/sampling.json << 'EOF'
{
    "default_strategy": {
        "type": "probabilistic",
        "param": 1.0
    },
    "service_strategies": [
        {
            "service": "audio-processor",
            "type": "ratelimiting",
            "param": 100,
            "operation_strategies": [
                {
                    "operation": "dsp_processing",
                    "type": "probabilistic",
                    "param": 0.8
                },
                {
                    "operation": "buffer_management",
                    "type": "ratelimiting",
                    "param": 50
                }
            ]
        },
        {
            "service": "ai-processor",
            "type": "probabilistic",
            "param": 0.5,
            "operation_strategies": [
                {
                    "operation": "model_inference",
                    "type": "probabilistic",
                    "param": 0.6
                }
            ]
        },
        {
            "service": "spatial-processor",
            "type": "probabilistic",
            "param": 0.75,
            "operation_strategies": [
                {
                    "operation": "hrtf_calculation",
                    "type": "probabilistic",
                    "param": 0.8
                }
            ]
        }
    ]
}
EOF

# Prepare tracing configuration
RUN cat > /etc/jaeger/tracing/config.json << 'EOF'
{
    "audio_pipeline": {
        "service": "audio-processor",
        "spans": [
            "dsp_processing",
            "ai_enhancement",
            "spatial_processing",
            "buffer_management",
            "format_conversion"
        ]
    },
    "ai_pipeline": {
        "service": "ai-processor",
        "spans": [
            "model_inference",
            "feature_extraction",
            "enhancement_processing",
            "model_selection",
            "inference_optimization"
        ]
    },
    "spatial_pipeline": {
        "service": "spatial-processor",
        "spans": [
            "hrtf_processing",
            "room_modeling",
            "head_tracking",
            "position_calculation",
            "acoustic_simulation"
        ]
    }
}
EOF

# Stage 2: Final Jaeger image
FROM jaegertracing/all-in-one:1.47.0

# Set environment variables
ENV SPAN_STORAGE_TYPE="badger" \
    BADGER_EPHEMERAL=false \
    BADGER_DIRECTORY_VALUE=/badger/data \
    BADGER_DIRECTORY_KEY=/badger/key \
    COLLECTOR_ZIPKIN_HOST_PORT=:9411 \
    MEMORY_MAX_TRACES=100000 \
    QUERY_BASE_PATH=/jaeger

# Copy configurations from builder
COPY --from=builder --chown=jaeger:jaeger /etc/jaeger /etc/jaeger

# Create necessary directories with proper permissions
RUN mkdir -p /badger/data /badger/key /tmp/jaeger \
    && chown -R jaeger:jaeger /badger /tmp/jaeger \
    && chmod 755 /badger /tmp/jaeger

# Set security context
USER jaeger

# Expose ports
EXPOSE 5775/udp 6831/udp 6832/udp 5778 16686 14250 14268 14269 9411

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:16686/ || exit 1

# Set resource limits
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0"

# Volume configuration
VOLUME ["/badger", "/tmp/jaeger"]

# Command with optimized configurations for audio processing
CMD ["--sampling.strategies-file=/etc/jaeger/sampling/sampling.json", \
     "--query.ui-config=/etc/jaeger/tracing/config.json", \
     "--collector.grpc.tls.enabled=true", \
     "--collector.grpc.tls.cert=/etc/jaeger/certs/collector.crt", \
     "--collector.grpc.tls.key=/etc/jaeger/certs/collector.key", \
     "--collector.tags=cluster=tald-unia,environment=production", \
     "--memory.max-traces=100000", \
     "--query.max-clock-skew-adjustment=1s", \
     "--query.timeout=30s"]