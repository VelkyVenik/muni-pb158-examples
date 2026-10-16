# socket-lab

Teaching lab for PB158 (MUNI): a verbose TCP server/client in C, shown at three levels at
once — program output, system calls (strace / gdb catch syscall) and packets (tcpdump) —
in a tmux layout inside one Debian 12 container. Audience: absolute beginners (C, OS,
containers). README.md is the student-facing manual.

## Layout
- `server.c`, `client.c` — the programs. Every comment is shown on screen by `step` mode,
  so comments are teaching text: keep them short, correct, beginner-level.
- `lab.sh` (macOS/Linux/WSL, must work with bash 3.2) and `lab.cmd`→`lab.ps1` (Windows,
  PowerShell 5.1 syntax: no `&&`, ternary, `??`) — host-side launchers: pick podman, then docker
  (installed, `info`, hello-world, compose), then `<compose> run --rm <mode>`. Keep them in sync.
- `start.sh <demo|strace|step|step_strace>` — builds in container-local `/work` (symlinks to
  `/lab` sources, which is mounted `:ro`: never write to the host mount), creates tmux panes, starts
  packets → server → client in order. `compose.yaml` has one service per mode (`extends: lab`).
- `packets` (tcpdump → perl), `trace` (strace → perl, `LAB_DELAY` slow motion via `inject=...:delay_exit`),
  `step`/`step_strace` (gdb + `step.py`, keyboard pacing via /dev/tty, echo off), `run`. All panes
  share one clock: `LAB_T0` (exported by start.sh) and `stamp` (timestamps + SERVER/CLIENT colours).
- Modes (menu order): `lab` = strace mode, `step_strace`, `step`, `nc` (nc -N in CLIENT pane,
  focus there), `plain`. `./lab.sh` without an argument shows a menu (lab.sh and lab.ps1). Launchers run `compose build lab` first.
- Colours (keep `trace`, `step.py`, `packets`, tmux legend in start.sh in sync): yellow 33 setup
  (connect/accept, SYN), magenta 35 data→server, cyan 36 data→client, red 31 closing (socket close,
  recvfrom=0, errors, FIN/RST), grey 2 local (no packet). Side of an fd: connect→client, accept→server.
  Both filters also print `open fds:` after calls that change the socket table.
- Pane width can be ~40 cols: anything erased with `\r\e[2K` must fit on one row.

## Rules
- Debian 12 (gdb 13) on purpose: gdb 15+ fails on Apple M4/M5 (SVE). Don't bump the base image.
- Keep the syscall lists in `trace` and `step.py` in sync.
- `step.py`: never hand control back to the main loop while stopped in a libc frame (the
  "no symtab → continue" guard would let the program run free). Syscall results are read
  at the *return* catchpoint (raw kernel value, -errno on failure), not after `finish`.
- Adding C lines *and comment lines* makes `step` mode slower (start.sh waits max 2 min for listen); prefer README text over extra code.
- README line-number examples (`│  77 ...`) must match `server.c`/`client.c` after edits.
- Every predicted outcome in README "Experiments" must be verified in the container.

## Distribution
- Students get `socket-lab.zip` from IS. Build it from the repo root (commit first; HEAD + path,
  not `HEAD:socket-lab`, or the folder's .gitattributes — CRLF, export-ignore — are not applied):
  `git archive --format=zip -o socket-lab.zip HEAD socket-lab`

## Testing (podman/docker via Lima on the maintainer's Mac; students use Lima too)
- Stock Lima templates share `~` read-only and nothing outside `~` (Lima ≥ 2.0). iCloud Drive
  (~/Library/Mobile Documents) fails with statfs EPERM (macOS TCC); lab.sh checks folder visibility.
- Headless: `docker run --rm --init --cap-add NET_RAW -v "$PWD":/lab -w /lab socket-lab bash -c '...'`.
- Real path: `docker run -dit ... bash start.sh <mode>`, then `docker exec <c> tmux capture-pane -p -t lab:0.<n>`.
- Background jobs ignore SIGINT in non-interactive bash: use `kill` (TERM) to simulate Ctrl-C.
- Launcher interactive test: `expect` script that waits for "Hello client!", sends `\002d`.
- `nc` (openbsd) keeps the connection open after stdin EOF; use `-N` in scripts.
