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
        cmake \
        curl \
        git \
        libc6 \
        libc6-dev \
        libgl1-mesa-dev \
        libglib2.0-0 \
        libnuma1 \
        libnuma-dev \
        libsm6 \
        libtcmalloc-minimal4 \
        libtool \
        libxext6 \
        libxrender1 \
        nodejs \
        pkg-config \
        python3 \
        python3-dev \
        python3-packaging \
        python3-pip \
        python3-venv \
        wget \
        yasm
    rm -rf /var/lib/apt/lists/*

    # Install ffmpeg from source
    # https://docs.nvidia.com/video-technologies/video-codec-sdk/12.1/ffmpeg-with-nvidia-gpu/index.html
    git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    cd nv-codec-headers && make install && cd -
    git clone https://git.ffmpeg.org/ffmpeg.git
    cd ffmpeg
    ./configure --enable-nonfree --enable-cuda-nvcc --enable-libnpp \
        --extra-cflags=-I/usr/local/cuda/include --extra-ldflags=-L/usr/local/cuda/lib64 \
        --disable-static --enable-shared
    make -j$(nproc) && make install && cd -
    rm -rf nv-codec-headers ffmpeg

    groupadd -g 1000 webui
    useradd -d /app -u 1000 -g webui webui
    chown -R webui:webui /app
EOT

USER webui:webui
ENV PATH="/app/.local/bin:${PATH}"

ARG GIT_BRANCH=master
# Arg to invalidate cached git clone step
ARG GIT_CLONE_CACHE
RUN <<EOT
    set -ex
    git clone -b ${GIT_BRANCH} --depth 1 \
        https://github.com/AUTOMATIC1111/stable-diffusion-webui.git

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
    venv_dir=- ./webui.sh --skip-torch-cuda-test --xformers --exit

    mv repositories/ ../repositories/
    mkdir -p repositories
EOT
