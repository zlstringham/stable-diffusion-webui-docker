FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS base

ENV CUDA_HOME=/usr/local/cuda

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md#example-cache-apt-packages
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

ARG NODE_MAJOR=21
ARG TARGETPLATFORM
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-${TARGETPLATFORM} <<EOT
    set -ex

    # nodejs pre-install step. See:
    # https://nodejs.org/en/download/package-manager#debian-and-ubuntu-based-linux-distributions
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get --no-install-recommends install -y \
        ca-certificates \
        curl \
        gnupg
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        | tee /etc/apt/sources.list.d/nodesource.list

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get --no-install-recommends install -y \
        build-essential \
        ffmpeg \
        git \
        libgl1 \
        libglib2.0-0 \
        libtcmalloc-minimal4 \
        nodejs \
        python3 \
        python3-dev \
        python3-opencv \
        python3-packaging \
        python3-pip \
        python3-venv \
        wget
    rm -rf /var/lib/apt/lists/*

    groupadd -g 1000 webui
    useradd -d /app -u 1000 -g webui webui
    chown -R webui:webui /app
EOT

USER webui:webui
ENV PATH="/app/.local/bin:${PATH}"

# Arg to invalidate cached git clone step
ARG GIT_CLONE_CACHE
RUN <<EOT
    set -ex
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git

    cd stable-diffusion-webui
    mkdir -p config-states
    mkdir -p embeddings
    mkdir -p extensions
    mkdir -p interrogate
    mkdir -p log
    mkdir -p models
    mkdir -p node_modules
    mkdir -p repositories
    mkdir -p outputs
    mkdir -p venv
EOT

VOLUME /app/stable-diffusion-webui/config-states
VOLUME /app/stable-diffusion-webui/embeddings
VOLUME /app/stable-diffusion-webui/extensions
VOLUME /app/stable-diffusion-webui/interrogate
VOLUME /app/stable-diffusion-webui/log
VOLUME /app/stable-diffusion-webui/models
VOLUME /app/stable-diffusion-webui/node_modules
VOLUME /app/stable-diffusion-webui/repositories
VOLUME /app/stable-diffusion-webui/outputs
VOLUME /app/stable-diffusion-webui/venv

COPY --chmod=775 --chown=webui:webui ./entrypoint.sh .

ARG PORT=7860
ENV PORT=${PORT}
EXPOSE ${PORT}

ENTRYPOINT ["./entrypoint.sh"]

FROM base AS full

ARG BLIP_COMMIT_HASH
ARG CODEFORMER_COMMIT_HASH
ARG GFPGAN_PACKAGE
ARG K_DIFFUSION_PACKAGE
ARG STABLE_DIFFUSION_COMMIT_HASH
ARG TORCH_COMMAND
RUN --mount=type=cache,uid=1000,gid=1000,target=/app/.cache/pip,sharing=locked,id=pip-${TARGETPLATFORM} <<EOT
    set -ex

    # Having these set to empty string prevents webui from loading defaults.
    [ -z "${BLIP_COMMIT_HASH}" ] && unset BLIP_COMMIT_HASH
    [ -z "${CODEFORMER_COMMIT_HASH}" ] && unset CODEFORMER_COMMIT_HASH
    [ -z "${GFPGAN_PACKAGE}" ] && unset GFPGAN_PACKAGE
    [ -z "${K_DIFFUSION_PACKAGE}" ] && unset K_DIFFUSION_PACKAGE
    [ -z "${STABLE_DIFFUSION_COMMIT_HASH}" ]  && unset STABLE_DIFFUSION_COMMIT_HASH
    [ -z "${TORCH_COMMAND}" ] && unset TORCH_COMMAND

    cd stable-diffusion-webui
    venv_dir=- ./webui.sh --skip-torch-cuda-test --exit

    mv repositories/ ../repositories/
    mkdir -p repositories
EOT
