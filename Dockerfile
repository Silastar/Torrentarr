FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    jq \
    mediainfo \
    mktorrent \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /config
CMD ["./torrent_creator.sh"]
