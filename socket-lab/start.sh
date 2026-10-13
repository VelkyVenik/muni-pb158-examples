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
# Usage:  bash start.sh           the plain demo
#         bash start.sh strace    same, with server and client under strace
#
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-demo}"
SESSION=lab
PORT=8080
export TERM="${TERM:-xterm-256color}"   # tmux refuses to start without it

# What runs in each pane. Later exercises can swap these, e.g. "gdb ./server".
SERVER_CMD="./server"
CLIENT_CMD="./client"
TCPDUMP_CMD="./packets"   # tcpdump, one readable line per packet
SERVER_TITLE="SERVER"
CLIENT_TITLE="CLIENT"

case "$MODE" in
    demo) ;;
    strace)
        SERVER_CMD="./trace ./server"   # strace with highlighted output
        CLIENT_CMD="./trace ./client"
        SERVER_TITLE="SERVER (strace)"
        CLIENT_TITLE="CLIENT (strace)"
        ;;
    *)
        echo "unknown mode: $MODE (use: demo, strace)" >&2
        exit 1
        ;;
esac

# Wait (max 10 s) until a command succeeds. If it never does (e.g. the
# server runs under gdb and is not listening yet), the demo just goes on.
wait_for() {
    for _ in $(seq 100); do
        if eval "$1" >/dev/null 2>&1; then return 0; fi
        sleep 0.1
    done
    return 1
}

# 1. Build.
make

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
