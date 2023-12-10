#!/bin/bash

cd /app/stable-diffusion-webui

[ -z "${ACCELERATE}" ] && unset ACCELERATE
[ -z "${COMMANDLINE_ARGS}" ] && unset COMMANDLINE_ARGS
[ -z "${NO_TCMALLOC}" ] && unset NO_TCMALLOC

[ -d "../repositories" ] && cp -rn ../repositories/* repositories/

if [[ ! -f "venv/bin/activate" ]]; then
    echo 'Creating virtual environment...'
    python3 -m venv venv --system-site-packages
fi

set -x
exec ./webui.sh "$@" --listen --port ${PORT:-7860}
