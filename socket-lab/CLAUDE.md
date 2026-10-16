# socket-lab

Teaching lab for PB158 (MUNI): a verbose TCP server/client in C, shown at three levels at
once — program output, system calls (strace / gdb catch syscall) and packets (tcpdump) —
in a tmux layout inside one Debian 12 container. Audience: absolute beginners (C, OS,
containers). README.md is the student-facing manual.

## Layout
- `server.c`, `client.c` — the programs. Every comment is shown on screen by `step` mode,
  so comments are teaching text: keep them short, correct, beginner-level.
- `lab.sh` (macOS/Linux/WSL, must work with bash 3.2) and `lab.cmd`→`lab.ps1` (Windows,
  PowerShell 5.1 syntax: no `&&`, ternary, `??`) — host-side launchers: pick docker or podman
  (installed, `info`, hello-world, compose), then `<compose> run --rm <mode>`. Keep them in sync.
- `start.sh <demo|strace|step|step_strace>` — builds (`make -B`), creates tmux panes, starts
  packets → server → client in order. `compose.yaml` has one service per mode (`extends: lab`).
- `packets` (tcpdump → perl), `trace` (strace → perl), `step`/`step_strace` (gdb + `step.py`).

## Rules
- Debian 12 (gdb 13) on purpose: gdb 15+ fails on Apple M4/M5 (SVE). Don't bump the base image.
- Keep the syscall lists in `trace` and `step.py` in sync.
- `step.py`: never hand control back to the main loop while stopped in a libc frame (the
  "no symtab → continue" guard would let the program run free). Syscall results are read
  at the *return* catchpoint (raw kernel value, -errno on failure), not after `finish`.
- Adding C lines *and comment lines* makes `step` mode slower (start.sh waits max 2 min for listen); prefer README text over extra code.
- README line-number examples (`│  77 ...`) must match `server.c`/`client.c` after edits.
- Every predicted outcome in README "Experiments" must be verified in the container.

## Testing (podman/docker via Lima on the maintainer's Mac)
- Headless: `docker run --rm --init --cap-add NET_RAW -v "$PWD":/lab -w /lab socket-lab bash -c '...'`.
- Real path: `docker run -dit ... bash start.sh <mode>`, then `docker exec <c> tmux capture-pane -p -t lab:0.<n>`.
- Background jobs ignore SIGINT in non-interactive bash: use `kill` (TERM) to simulate Ctrl-C.
- Launcher interactive test: `expect` script that waits for "Hello client!", sends `\002d`.
- `nc` (openbsd) keeps the connection open after stdin EOF; use `-N` in scripts.
