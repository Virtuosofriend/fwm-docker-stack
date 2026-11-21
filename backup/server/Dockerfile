FROM alpine:3.24.4

ARG TARGETARCH

RUN apk add --no-cache bash openssh-client curl ca-certificates

# Pinned releases, verified against their published checksums
RUN set -eu; \
    case "$TARGETARCH" in \
        amd64) RESTIC_SHA256=f415415624dcc452f2a02b8c33641791a8c6d6d3b65bbb3543fcf9a25151585c; SUPERCRONIC_SHA1=1692066e350a88ff4d7d6474fe3c7a6c41ec5e89 ;; \
        arm64) RESTIC_SHA256=a5f64aaab53d51e311fa3829124c5b703f2d14cf187d8640b6be3b2b49376465; SUPERCRONIC_SHA1=9d4c2000493215a1898502b2fc2dada3e8ea8c7a ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/restic.bz2 "https://github.com/restic/restic/releases/download/v0.19.1/restic_0.19.1_linux_${TARGETARCH}.bz2"; \
    echo "$RESTIC_SHA256  /tmp/restic.bz2" | sha256sum -c -; \
    bunzip2 -c /tmp/restic.bz2 > /usr/local/bin/restic; \
    curl -fsSL -o /usr/local/bin/supercronic "https://github.com/aptible/supercronic/releases/download/v0.2.51/supercronic-linux-${TARGETARCH}"; \
    echo "$SUPERCRONIC_SHA1  /usr/local/bin/supercronic" | sha1sum -c -; \
    chmod +x /usr/local/bin/restic /usr/local/bin/supercronic; \
    rm /tmp/restic.bz2

COPY crontab run.sh backup.sh notify.sh /app/
RUN chmod +x /app/run.sh /app/backup.sh /app/notify.sh

ENTRYPOINT ["supercronic", "/app/crontab"]
