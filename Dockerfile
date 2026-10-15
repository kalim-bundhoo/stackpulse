FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

FROM ubuntu:24.04 AS runtime

LABEL maintainer="Platform Engineering <devops@stackpulse.internal>"

ENV DEBIAN_FRONTEND=noninteractive \
    USERNAME=appuser \
    USER_UID=1001 \
    USER_GID=1001

RUN groupadd --gid ${USER_GID} ${USERNAME} 2>/dev/null || true \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} 2>/dev/null || true

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app /app

RUN chown -R ${USERNAME}:${USERNAME} /app

USER ${USERNAME}

ENTRYPOINT ["/usr/bin/tini", "--"]
EXPOSE 8080
CMD ["echo", "Container running successfully"]
