# syntax=docker/dockerfile:1
#FROM --platform=$TARGETPLATFORM alpine:latest
FROM alpine:latest
ARG TARGETPLATFORM
COPY src/entrypoint.sh /
RUN --mount=type=cache,target=/var/cache/apk \
    /bin/sh -c set -xe && \
    chmod +x /entrypoint.sh && \
    addgroup -g 1004 openconnect && \
    adduser -G openconnect -u 1004 -D -H -s /bin/sh openconnect && \
    apk add --no-cache \
      iptables-legacy \
      ca-certificates \
      tzdata \
      openconnect && \
    update-ca-certificates && \
    mkdir -p /etc/openconnect && \
    touch /etc/openconnect/openconnect.conf && \
    mkdir /certs && chown -R 1004:1004 /certs && \
    echo -e "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && \
    echo -e "net.ipv6.conf.all.forwarding=1\nnet.ipv6.conf.default.forwarding=1" \ 
     >> /etc/sysctl.conf && \
    for cmd in iptables ip6tables iptables-restore ip6tables-restore iptables-save ip6tables-save; do \
        ln -sfT /usr/sbin/${cmd}-legacy /usr/sbin/${cmd}; \
        done
HEALTHCHECK --interval=20s --timeout=3s --start-period=5s --retries=3 \
    CMD pidof openconnect >/dev/null || exit 1
ENTRYPOINT ["/entrypoint.sh"]
