FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/opt/venv/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    g++ \
    make \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    iverilog \
    verilator \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install cocotb pyuvm

WORKDIR /workspace
COPY . /workspace

RUN groupadd --system dev && useradd --system --gid dev --create-home --home-dir /home/dev dev \
    && chown -R dev:dev /workspace /opt/venv

USER dev

CMD ["bash", "-lc", "make help"]
