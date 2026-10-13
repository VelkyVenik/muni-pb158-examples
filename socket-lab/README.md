# socket-lab

A TCP server and client in C, talking to each other over loopback, while
`tcpdump` shows every packet they exchange. Optionally, `strace` shows every
system call, or `gdb` steps through the code line by line. Everything runs inside one
Linux container, so it behaves the same on Windows, macOS and Linux.

## Running

You only need Docker (or Podman).

```bash
git clone https://github.com/VelkyVenik/muni-pb158-examples.git
cd muni-pb158-examples/socket-lab
docker compose run --rm lab
```

The first run builds the image, which takes a few minutes. After that it starts in
seconds. Run `docker compose build` again only if you change the `Dockerfile`.

With Podman, use `podman compose run --rm lab`.

Two more modes run the same demo with extra detail:

```bash
docker compose run --rm strace   # system calls under each socket call
docker compose run --rm step     # the C code, line by line, as it runs
```

See [Watching system calls](#watching-system-calls-strace) and
[Stepping through the code](#stepping-through-the-code-step).

## What you are looking at

```text
+--------------------+--------------------+
| SERVER             | CLIENT             |
+--------------------+--------------------+
| PACKETS                                 |
+-----------------------------------------+
```

- **SERVER** (top left): `./server`, built from `server.c`. Waits for a client on `127.0.0.1:8080`.
- **CLIENT** (top right): `./client`, built from `client.c`. Connects, sends `Hello server!`, gets `Hello client!` back.
- **PACKETS** (bottom): every TCP packet to or from port 8080, captured by `tcpdump`.
  See [Reading the packets](#reading-the-packets).

Both programs print each socket call *before* making it and its result *after*,
so a line ending in `waiting...` with nothing below it means the call is blocked.
The programs pause for 2 seconds at a few points so you can see this.

## What to observe

Keep `server.c` and `client.c` open next to the demo.

1. **`socket()` returns a file descriptor.** It is usually `fd=3`. Why not 0, 1 or 2?
2. **`accept()` returns a *new* fd** (`fd=4`). The listening socket (`fd=3`) stays open for the next client.
   Which fd do the server's `recv()` and `send()` use?
3. **`accept()` blocks.** The server sits at `waiting for connection...` until the client starts.
4. **`recv()` blocks.** The server waits for data while the client sleeps. Later the client waits while the server sleeps.
   The packet pane shows these as `+2.00s` gaps.
5. **`connect()` = the three-way handshake.** `SYN`, `SYN-ACK`, `ACK`. No data has been sent yet.
6. **One `send()` produces one `DATA` packet** with 13 bytes, followed by an `ACK` in the other direction.
7. **Ports.** The server uses 8080. The client got a random port from the kernel. Find it in
   the client's output (`my address is ...`) and in the packet pane.
8. **Closing.** The client's `close()` sends a `FIN`. The server's `recv()` then returns `0`,
   the server closes its fd, which sends the second `FIN`.
9. **Most socket calls send nothing at all.** See below.

## Reading the packets

The bottom pane runs `./packets`, which is `tcpdump` with its output rewritten to
one readable line per packet:

```text
    TIME  FROM            TO              TYPE      LEN  DATA
 +0.000s  CLIENT:49142 → SERVER:8080   SYN       0
 +0.000s  SERVER:8080  → CLIENT:49142  SYN-ACK   0
 +0.000s  CLIENT:49142 → SERVER:8080   ACK       0
 +2.002s  CLIENT:49142 → SERVER:8080   DATA      13   "Hello server!"
 +0.000s  SERVER:8080  → CLIENT:49142  ACK       0
 +2.005s  SERVER:8080  → CLIENT:49142  DATA      13   "Hello client!"
 +0.000s  CLIENT:49142 → SERVER:8080   ACK       0
 +0.000s  CLIENT:49142 → SERVER:8080   FIN       0
 +0.000s  SERVER:8080  → CLIENT:49142  FIN       0
 +0.000s  CLIENT:49142 → SERVER:8080   ACK       0
```

- **TIME**: time since the *previous* packet. A long gap means a program was blocked or sleeping.
- **FROM → TO**: both sides are `127.0.0.1`, so they differ only by port. 8080 is the server.
- **TYPE**: what the packet is for. **LEN**: bytes of data it carries. **DATA**: those bytes.

Which line of C code caused each packet:

| Packet               | Sent because of                                    |
|----------------------|----------------------------------------------------|
| `SYN`                | client's `connect()`                               |
| `SYN-ACK`            | the server's **kernel**: `accept()` is not involved |
| `ACK` (3rd)          | the client's kernel; then `connect()` returns      |
| `DATA` client→server | client's `send()`                                  |
| `ACK` after DATA     | the receiver's **kernel**, not `recv()`            |
| `DATA` server→client | server's `send()`                                  |
| `FIN` client→server  | client's `close()`                                 |
| `FIN` server→client  | server's `close()`                                 |
| last `ACK`           | the client's kernel                                |

And what does **not** appear at all: `socket()`, `bind()`, `listen()`, `accept()`
and `recv()` produce no packets. The kernel completes the handshake on its own and
queues the connection. `accept()` only picks it up from that queue. Arriving data is
acknowledged by the kernel and kept in a buffer. `recv()` only copies it out.
Only `connect()`, `send()` and `close()` put packets on the wire.

Try `./client` while the server is *not* running: the `SYN` is answered by `RST`
(reset) and `connect()` fails with `Connection refused`.

### Raw tcpdump

`./packets` hides details such as sequence numbers, window size and TCP options.
To see what tcpdump really prints, press `Ctrl-C` in the PACKETS pane and run:

```bash
tcpdump -i lo -nn 'tcp port 8080'
```

| `./packets` | raw tcpdump flags |
|-------------|-------------------|
| `SYN`       | `[S]`             |
| `SYN-ACK`   | `[S.]`            |
| `ACK`       | `[.]`             |
| `DATA`      | `[P.]` and `length 13` |
| `FIN`       | `[F.]`            |
| `RST`       | `[R.]`            |

The `.` means "ACK flag set". tcpdump also labels the data `HTTP`, but that is only
a guess based on port 8080. The port does not define the protocol.

## Watching system calls (strace)

`strace` shows every call a program makes into the kernel. Start the lab in
strace mode:

```bash
docker compose run --rm strace
```

It is the same demo, but the server and client panes now show the real system
calls (indented and coloured) right below each `printf`:

```text
SERVER: calling accept()
SERVER: waiting for connection...
    accept(3, {sa_family=AF_INET, sin_port=htons(57268), ...}, [16]) = 4
SERVER: accept() -> fd=4   <-- NEW fd for this connection
```

What to observe:

1. **Blocking happens in the kernel.** While the server waits, its last line is an
   unfinished `accept(3, `. It completes when the client connects. The same happens with `recvfrom(`.
2. **`recv()` and `send()` are library functions.** The C library turns them into the
   `recvfrom()` and `sendto()` system calls, with extra arguments set to `NULL`/`0`.
3. **The kernel hands out the fds.** Compare the `= 3` / `= 4` results with the numbers the programs print.
4. **`close(3)` before `main()`.** The two `close(3)` lines at the very top come from
   the dynamic loader opening and closing a library file. That is why `socket()` gets 3 again.
5. **The data is right there.** `recvfrom(4, "Hello server!", ...) = 13`: the return value is the
   number of bytes, exactly what the program prints next.

To trace something by hand, press `Ctrl-C` in a pane (or use a free shell) and run:

```bash
./trace ./client                         # what strace mode runs: highlighted socket calls
strace -e trace=network,close ./server   # plain strace: networking calls + close
strace ./client                          # everything, including memory and file calls
```

## Stepping through the code (step)

```bash
docker compose run --rm step
```

The server and client run under the `gdb` debugger, which executes `main()` one
line at a time and prints each line of C code just *before* running it:

```text
│  54      printf("SERVER: calling listen()\n");
SERVER: calling listen()
│  55      rc = listen(listen_fd, 5);
│  56      if (rc < 0) {
...
│  69          int conn_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &client_len);
```

The number is the line in `server.c` / `client.c`, so you can follow along in your editor.

What to observe:

1. **Where a program blocks.** The last line on screen is the one running *now*. When it is
   `accept(...)` or `recv(...)` and nothing moves, the program is waiting inside that call.
2. **Which `if` branches run.** The error branches (`if (rc < 0) {`) are checked but skipped.
   After the client closes, the server goes through `if (n == 0)`.
3. **The loop.** After one client, the server jumps back to `for (;;)` and stops at `accept()` again.
4. **Both sides at once.** Watch the client's `send(...)` line and the server's `recv(...)` line
   finish at the same moment, and the `DATA` packet appear below.

Too fast or too slow? In a pane, `Ctrl-C`, then for example `STEP_DELAY=1 ./step ./client`.

### Stepping yourself with gdb

To control the stepping yourself, press `Ctrl-C` in the SERVER pane and run:

```bash
gdb -tui ./server
```

The top half shows the source with the current line highlighted. Useful commands:

| Command      | Meaning                                       |
|--------------|-----------------------------------------------|
| `break main` | stop when `main()` starts                     |
| `run`        | start the program                             |
| `n`          | run the current line (next)                   |
| `p listen_fd`| print a variable                              |
| `c`          | continue until the end or a breakpoint        |
| `q`          | quit                                          |

Step over `accept()` with `n` and gdb seems to freeze. It is waiting for a client.
Run `./client` in the CLIENT pane and watch the line complete.

## Experimenting

The server keeps running and waits for the next client. In the CLIENT pane you can:

```bash
./client              # run the client again
make                  # rebuild after editing server.c / client.c on your machine
```

Your local files are mounted into the container, so edit them in your usual
editor, then run `make` inside. To restart the server, press `Ctrl-C` in its pane and
run `./server`.

`make clean` removes the built programs.

## tmux basics

`Ctrl-b` means: press Ctrl+b, release it, then press the next key.

| Action                    | Keys                                     |
|---------------------------|------------------------------------------|
| Move to another pane      | click it, or `Ctrl-b` + arrow key        |
| Scroll up in a pane       | mouse wheel, or `Ctrl-b [` then arrows / PgUp. `q` stops scrolling |
| Zoom a pane to full size  | `Ctrl-b z` (again to unzoom)             |
| Quit the lab              | `Ctrl-b d`                               |

Quitting stops the container. The next `docker compose run --rm lab` starts fresh.

## Files

| File          | Purpose                                              |
|---------------|------------------------------------------------------|
| `server.c`    | the server                                           |
| `client.c`    | the client                                           |
| `Makefile`    | builds both with `-g -O0 -Wall -Wextra -Wpedantic`   |
| `start.sh`    | builds, creates the tmux layout, starts everything (`bash start.sh strace` / `step` for the other modes) |
| `trace`       | runs a program under strace and highlights the system calls |
| `step`        | runs a program under gdb, printing each line of C code as it runs |
| `packets`     | runs tcpdump and prints one readable line per packet |
| `Dockerfile`  | Debian 12 with gcc, make, gdb, strace, tcpdump, tmux, iproute2 |
| `compose.yaml`| runs the container and mounts this directory at `/lab` |
