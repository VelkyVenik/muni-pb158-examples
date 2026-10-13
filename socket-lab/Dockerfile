FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc libc6-dev make gdb strace tcpdump tmux iproute2 procps less \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /lab
CMD ["bash", "start.sh"]
