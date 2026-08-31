FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        iverilog \
        verilator \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER vscode