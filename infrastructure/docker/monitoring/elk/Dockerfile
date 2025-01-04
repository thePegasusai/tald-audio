# Elasticsearch Stage
FROM docker.elastic.co/elasticsearch/elasticsearch:7.17.3 AS elasticsearch
LABEL maintainer="TALD UNIA Audio System Team"

# Security hardening
USER root
RUN groupadd -g 1000 elk && \
    useradd -u 1000 -g elk elk && \
    chown -R elk:elk /usr/share/elasticsearch

# System configuration
RUN ulimit -n 65535 && \
    sysctl -w vm.max_map_count=262144

# Set environment variables
ENV discovery.type=single-node \
    ES_JAVA_OPTS="-Xms4g -Xmx4g" \
    xpack.security.enabled=true \
    xpack.monitoring.collection.enabled=true \
    xpack.security.audit.enabled=true \
    cluster.name=tald-unia-monitoring \
    node.name=tald-unia-node \
    bootstrap.memory_lock=true

# Create required directories
RUN mkdir -p /usr/share/elasticsearch/data && \
    mkdir -p /usr/share/elasticsearch/config/certs && \
    chown -R elk:elk /usr/share/elasticsearch

# Add index templates
COPY --chown=elk:elk elasticsearch/templates/audio-metrics.json /usr/share/elasticsearch/config/templates/
COPY --chown=elk:elk elasticsearch/templates/system-metrics.json /usr/share/elasticsearch/config/templates/

# Configure security
RUN chmod 0600 /usr/share/elasticsearch/config/elasticsearch.keystore

USER elk

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -s http://localhost:9200/_cluster/health || exit 1

EXPOSE 9200 9300
VOLUME ["/usr/share/elasticsearch/data", "/usr/share/elasticsearch/config/certs"]

# Logstash Stage
FROM docker.elastic.co/logstash/logstash:7.17.3 AS logstash
LABEL maintainer="TALD UNIA Audio System Team"

# Security hardening
USER root
RUN groupadd -g 1000 elk && \
    useradd -u 1000 -g elk elk && \
    chown -R elk:elk /usr/share/logstash

# Set environment variables
ENV LS_JAVA_OPTS="-Xms1g -Xmx1g" \
    xpack.monitoring.enabled=true \
    pipeline.workers=2 \
    pipeline.batch.size=125 \
    config.reload.automatic=true

# Copy pipeline configurations
COPY --chown=elk:elk logstash/pipeline/audio_processing.conf /usr/share/logstash/pipeline/
COPY --chown=elk:elk logstash/pipeline/system_metrics.conf /usr/share/logstash/pipeline/

# Create required directories
RUN mkdir -p /usr/share/logstash/certs && \
    chown -R elk:elk /usr/share/logstash

USER elk

EXPOSE 5044 5045 9600
VOLUME ["/usr/share/logstash/pipeline", "/usr/share/logstash/config", "/usr/share/logstash/certs"]

# Kibana Stage
FROM docker.elastic.co/kibana/kibana:7.17.3 AS kibana
LABEL maintainer="TALD UNIA Audio System Team"

# Security hardening
USER root
RUN groupadd -g 1000 elk && \
    useradd -u 1000 -g elk elk && \
    chown -R elk:elk /usr/share/kibana

# Set environment variables
ENV ELASTICSEARCH_HOSTS="http://elasticsearch:9200" \
    ELASTICSEARCH_USERNAME=kibana_system \
    xpack.security.enabled=true \
    xpack.reporting.enabled=true \
    telemetry.enabled=false

# Copy dashboard configurations
COPY --chown=elk:elk kibana/dashboards/audio_quality_monitoring.ndjson /usr/share/kibana/config/dashboards/
COPY --chown=elk:elk kibana/dashboards/system_performance.ndjson /usr/share/kibana/config/dashboards/

# Create required directories
RUN mkdir -p /usr/share/kibana/certs && \
    chown -R elk:elk /usr/share/kibana

# Add Prometheus exporter
COPY --chown=elk:elk monitoring/exporters/elasticsearch-exporter /usr/local/bin/
RUN chmod +x /usr/local/bin/elasticsearch-exporter

USER elk

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -s http://localhost:5601/api/status || exit 1

EXPOSE 5601 9114 9115
VOLUME ["/usr/share/kibana/config", "/usr/share/kibana/certs"]

# Security capabilities
RUN setcap cap_net_bind_service=+ep /usr/local/bin/elasticsearch-exporter

# Add security labels
LABEL seccomp.security.alpha.kubernetes.io/pod=runtime/default
LABEL selinux.type=container_t
LABEL selinux.level=s0:c123,c456

# Set read-only root filesystem
VOLUME ["/tmp", "/var/run"]
RUN chmod 1777 /tmp /var/run

# Default command
CMD ["kibana-docker"]