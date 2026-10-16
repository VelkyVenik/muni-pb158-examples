#!/usr/bin/env bash
#
# Start socket-lab with whichever container engine works on this computer:
# Podman first, then Docker. For each one it checks that
#
#   1. it is installed,
#   2. it is running,
#   3. it can run a container (the tiny "hello-world" test image),
#   4. it has "compose",
#
# and then runs:   <engine> compose run --rm <mode>
#
#   usage: ./lab.sh [lab|strace|step|step_strace]      (default: lab)
#          LAB_ENGINE=docker ./lab.sh                   (use only Docker)
#
# macOS, Linux and WSL. On Windows, run lab.cmd instead.

set -u
cd "$(dirname "$0")"

MODES="lab strace step step_strace"
MODE="${1:-lab}"
case " $MODES " in
    *" $MODE "*) ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Usage: ./lab.sh [${MODES// /|}]"
        exit 2
        ;;
esac

if [ -n "${MSYSTEM:-}" ]; then
    echo "This is Git Bash, where the lab cannot use the terminal properly."
    echo "Open PowerShell or Windows Terminal in this folder and run:  .\\lab.cmd $MODE"
    exit 1
fi

GREEN=$'\e[1;32m' RED=$'\e[1;31m' DIM=$'\e[2m' OFF=$'\e[0m'
ok()   { echo "  ${GREEN}OK${OFF}    $1"; }
fail() { echo "  ${RED}FAIL${OFF}  $1"; }

OS=$(uname -s)
if [ "$OS" = Linux ] && grep -qi microsoft /proc/version 2>/dev/null; then
    OS=WSL
fi

# Lima (limactl) runs Docker or Podman in a Linux VM. Since Lima 2.0 that VM
# only sees your home folder, so the lab folder must be inside it.
if command -v limactl >/dev/null 2>&1; then
    case "$PWD/" in
        "$HOME"/*) ;;
        *)  echo "Warning: this folder ($PWD) is outside your home folder."
            echo "With Lima, containers cannot see it. Move it into your home folder, e.g. ~/socket-lab."
            echo ;;
    esac
fi

# Hide podman's "Executing external compose provider" warning.
export PODMAN_COMPOSE_WARNING_LOGS=false

# What to do when the engine is installed but not running.
not_running_hint() {
    local engine=$1 error=$2 stopped
    if command -v limactl >/dev/null 2>&1; then
        stopped=$(limactl list --format '{{.Name}} {{.Status}}' 2>/dev/null | awk '$2 != "Running" { printf " %s", $1 }')
        echo "If it runs in Lima, start its VM:  limactl start <name>
        (stopped Lima VMs:${stopped:- none}; all of them: limactl list)"
        return
    fi
    case "$engine/$OS" in
        docker/Darwin) echo "Start Docker Desktop and wait until it says it is running." ;;
        docker/WSL)    echo "Start Docker Desktop in Windows. In its Settings > Resources > WSL integration,
        turn it on for this Linux distribution." ;;
        docker/Linux)
            if [[ "$error" == *"permission denied"* ]]; then
                echo "You may not use Docker yet. Run:  sudo usermod -aG docker \$USER
        then log out and back in. (Or run this script with sudo.)"
            else
                echo "Start it:  sudo systemctl start docker"
            fi ;;
        podman/Darwin | podman/WSL)
            echo "Start the Podman machine:  podman machine start
        (the very first time:  podman machine init  and then  podman machine start)" ;;
        *) echo "The error was: $(echo "$error" | tail -1)" ;;
    esac
}

# check <engine>: sets COMPOSE (the compose command to use) or REASON.
check() {
    local engine=$1 out
    COMPOSE=() REASON=""
    echo "Checking $engine..."

    if ! command -v "$engine" >/dev/null 2>&1; then
        fail "$engine is not installed"
        REASON="$engine is not installed."
        return 1
    fi
    ok "installed"

    if ! out=$("$engine" info 2>&1); then
        fail "$engine is installed but not running"
        REASON="$engine is installed but not running. $(not_running_hint "$engine" "$out")"
        return 1
    fi
    ok "running"

    if ! out=$("$engine" run --rm docker.io/library/hello-world 2>&1); then
        fail "$engine cannot run a container"
        REASON="$engine cannot run a container. The error was: $(echo "$out" | tail -1)"
        return 1
    fi
    ok "can run containers"

    # Podman: prefer podman-compose. "podman compose" may hand over to
    # docker-compose, which on Linux needs the Podman socket service.
    if [ "$engine" = podman ] && command -v podman-compose >/dev/null 2>&1; then
        COMPOSE=(podman-compose)
    elif "$engine" compose version >/dev/null 2>&1; then
        COMPOSE=("$engine" compose)
    elif [ "$engine" = docker ] && command -v docker-compose >/dev/null 2>&1; then
        COMPOSE=(docker-compose)
    else
        fail "compose is missing"
        if [ "$engine" = docker ]; then
            REASON="docker works, but compose is missing. Install the Docker Compose plugin:
        https://docs.docker.com/compose/install/"
        else
            REASON="podman works, but compose is missing. Install podman-compose
        (macOS: brew install podman-compose, Linux: from your distribution, e.g. sudo apt install podman-compose)."
        fi
        return 1
    fi
    ok "compose (${COMPOSE[*]})"
    return 0
}

ENGINES="${LAB_ENGINE:-podman docker}"
REASONS=()
for engine in $ENGINES; do
    if check "$engine"; then
        echo
        if [ ! -t 0 ] || [ ! -t 1 ]; then
            echo "Warning: this is not an interactive terminal, the lab may not start."
        fi
        echo "Starting:  ${COMPOSE[*]} run --rm $MODE"
        echo "${DIM}(The first start builds the lab image, which takes a few minutes.)${OFF}"
        echo "${DIM}(To quit the lab: press Ctrl-b, release, then press d.)${OFF}"
        exec "${COMPOSE[@]}" run --rm "$MODE"
    fi
    REASONS+=("$REASON")
    echo
done

echo "${RED}No working container engine found.${OFF} You need Docker or Podman:"
for reason in "${REASONS[@]}"; do
    echo "  - $reason"
done
echo "See the Troubleshooting section in README.md."
exit 1
