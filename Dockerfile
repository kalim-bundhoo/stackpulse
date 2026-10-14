# Stage 1: Build / Preparation Stage
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Runtime Stage
FROM ubuntu:24.04 AS runtime
LABEL maintainer="kalim <stackpulse@local>"
ENV DEBIAN_FRONTEND=noninteractive

ARG USERNAME=iskalim
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    sudo \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/stackpulse

COPY --chown=$USER_UID:$USER_GID . /opt/stackpulse

USER $USERNAME

EXPOSE 8080

CMD ["bash"]
