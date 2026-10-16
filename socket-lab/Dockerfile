# Debian 12 rather than Ubuntu 24.04: its gdb 13 works on Apple M4/M5 Macs,
# where gdb 15+ fails with "Unable to fetch SVE/SSVE vector length".
# Full name (docker.io/...) so Podman does not ask which registry to use.
FROM docker.io/library/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc libc6-dev make gdb strace tcpdump tmux iproute2 procps less \
      netcat-openbsd \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /lab
CMD ["bash", "start.sh"]
