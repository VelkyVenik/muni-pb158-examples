#!/usr/bin/env bash
#
# Build the programs and start the demo in tmux:
#
#   +-----------------+-----------------+
#   | SERVER          | CLIENT          |
#   +-----------------+-----------------+
#   | PACKETS                           |
#   +-----------------------------------+
#
# Usage:  bash start.sh               program output + system calls (strace) + packets
#         bash start.sh plain         program output + packets only
#         bash start.sh step          the C code line by line (gdb), you control the pace
#         bash start.sh step_strace   step + the system calls each line makes
#
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-strace}"
SESSION=lab
PORT=8080
export TERM="${TERM:-xterm-256color}"   # tmux refuses to start without it

# What runs in each pane. Later exercises can swap these, e.g. "gdb ./server".
TCPDUMP_CMD="./packets"   # tcpdump, one readable line per packet

case "$MODE" in
    strace)
        SERVER_CMD="./trace ./server"   # strace with highlighted output
        CLIENT_CMD="./trace ./client"
        SERVER_TITLE="SERVER (output + system calls)"
        CLIENT_TITLE="CLIENT (output + system calls)"
        ;;
    plain)
        SERVER_CMD="./run ./server"     # just the program, with timestamps
        CLIENT_CMD="./run ./client"
        SERVER_TITLE="SERVER"
        CLIENT_TITLE="CLIENT"
        ;;
    step)
        SERVER_CMD="./step ./server"    # gdb, one line of C at a time
        CLIENT_CMD="./step ./client"
        SERVER_TITLE="SERVER (step)"
        CLIENT_TITLE="CLIENT (step)"
        ;;
    step_strace)
        SERVER_CMD="./step_strace ./server"   # gdb + system calls
        CLIENT_CMD="./step_strace ./client"
        SERVER_TITLE="SERVER (step + syscalls)"
        CLIENT_TITLE="CLIENT (step + syscalls)"
        ;;
    *)
        echo "unknown mode: $MODE (use: strace, plain, step, step_strace)" >&2
        exit 1
        ;;
esac

# Wait (max 2 min) until a command succeeds. In step modes the server needs
# a while to reach listen(), more on slow computers. If it never succeeds
# (e.g. the server is stopped in gdb), the demo just goes on.
wait_for() {
    for _ in $(seq 1200); do
        if eval "$1" >/dev/null 2>&1; then return 0; fi
        sleep 0.1
    done
    return 1
}

# 1. Build in a working folder inside the container. Your lab folder is
# shared read-only, so nothing is ever written to your computer. The .c files
# and the Makefile here are links to yours: edit them on your computer, then
# run "make" in the lab. The helper scripts are copied, so they are always
# executable (a ZIP download can lose that).
SRC="$PWD"
WORK=/work
rm -rf "$WORK"
mkdir -p "$WORK"
for f in "$SRC"/*.c "$SRC"/Makefile "$SRC"/step.py; do
    ln -s "$f" "$WORK/"
done
for f in packets trace step step_strace stamp run; do
    cp "$SRC/$f" "$WORK/$f"
    chmod +x "$WORK/$f"
done
cd "$WORK"
make

# The clock for all timestamps: seconds since now. The panes inherit it
# through tmux, so the SERVER, CLIENT and PACKETS panes all use it.
LAB_T0=$(date +%s.%N)
export LAB_T0

# 2. Start from a clean slate.
tmux kill-session -t "$SESSION" 2>/dev/null || true

# 3. Create the layout, sized to the current terminal.
cols=$(tput cols 2>/dev/null || echo 0)
rows=$(tput lines 2>/dev/null || echo 0)
[ "$cols" -ge 40 ] || cols=160
[ "$rows" -ge 15 ] || rows=48

server=$(tmux new-session -d -s "$SESSION" -x "$cols" -y "$rows" -P -F '#{pane_id}')
tcpdump=$(tmux split-window -v -t "$server" -l 35% -P -F '#{pane_id}')
client=$(tmux split-window -h -t "$server" -l 50% -P -F '#{pane_id}')

tmux set -g mouse on
tmux set -g history-limit 10000
tmux set -g pane-border-status top
tmux set -g pane-border-format ' #{@title} '
tmux set -g status-right ' Ctrl-b d: quit '
# The colour legend, for all panes: what a system call or packet is part of.
tmux set -g window-status-format ''
tmux set -g window-status-current-format ''
tmux set -g status-left-length 100
tmux set -g status-left '#[fg=yellow,bold] setup #[fg=magenta]data→server #[fg=cyan]data→client #[fg=red]closing #[fg=white,nobold,dim]no packet #[default]'
tmux set -p -t "$server"  @title "$SERVER_TITLE"
tmux set -p -t "$client"  @title "$CLIENT_TITLE"
tmux set -p -t "$tcpdump" @title 'PACKETS (tcpdump on lo, port 8080)'
tmux select-pane -t "$server"

# 4.-6. Start tcpdump, then the server, then the client - each one only
# when the previous one is ready. Runs in the background so you can
# watch it happen after attaching.
(
    tmux send-keys -t "$tcpdump" "$TCPDUMP_CMD" Enter
    wait_for '[ -n "$(ss -H -0)" ]' || true                    # capture socket open

    tmux send-keys -t "$server" "$SERVER_CMD" Enter
    wait_for '[ -n "$(ss -H -ltn "sport = :$PORT")" ]' || true  # server listening

    sleep 2   # let students see the server blocked in accept()
    tmux send-keys -t "$client" "$CLIENT_CMD" Enter
) >/dev/null 2>&1 &

# 7. Hand the terminal over to tmux.
exec tmux attach -t "$SESSION"
