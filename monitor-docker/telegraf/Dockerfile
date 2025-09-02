
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 ca-certificates \
    fping libcap2-bin \
    jq bash coreutils \
    iproute2 \
 && rm -rf /var/lib/apt/lists/*

RUN curl -s https://repos.influxdata.com/influxdata-archive.key \
  | gpg --dearmor > /usr/share/keyrings/influxdata.gpg && \
  echo "deb [signed-by=/usr/share/keyrings/influxdata.gpg] https://repos.influxdata.com/ubuntu stable main" \
  > /etc/apt/sources.list.d/influxdata.list && \
  apt-get update && apt-get install -y --no-install-recommends telegraf && \
  rm -rf /var/lib/apt/lists/*

RUN setcap cap_net_raw+ep /usr/bin/fping && getcap /usr/bin/fping


WORKDIR /opt/netprobe

RUN mkdir -p /opt/netprobe/scripts

COPY --chmod=755 scripts/fping2influx.sh /opt/netprobe/scripts/fping2influx.sh
COPY --chmod=755 scripts/entrypoint.sh   /entrypoint.sh
COPY telegraf/telegraf.base.conf /etc/telegraf/telegraf.conf
COPY --chmod=755 scripts/view_tables.py /opt/netprobe/scripts/view_tables.py



RUN mkdir -p /var/log/telegraf \
 && chown -R telegraf:telegraf /var/log/telegraf \
 && chmod 775 /var/log/telegraf

# ---- Volumes ----

VOLUME ["/var/log/telegraf", "/etc/telegraf/telegraf.d", "/config"]

# ---- Defaults  ----

ENV ICMP_TARGETS="1.1.1.1,8.8.8.8,cloudflare.com" \
    ICMP_INTERVAL="10s" \
    ICMP_TIMEOUT="1000ms" \
    ICMP_PERIOD_MS="200" \
    TCP_TARGETS="" \
    TCP_TIMEOUT="1s" \
    DNS_SERVERS="" \
    DNS_DOMAINS="" \
    DNS_RECORD_TYPE="A" \
    OUTPUT_FILE="/var/log/telegraf/netprobe_metrics.out"


RUN chown -R telegraf:telegraf /etc/telegraf /opt/netprobe /var/log/telegraf


HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD pgrep -x telegraf >/dev/null || exit 1


ENTRYPOINT ["/entrypoint.sh"]
