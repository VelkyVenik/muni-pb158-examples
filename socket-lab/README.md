# socket-lab

Two small C programs, a **server** and a **client**, talk to each other over a TCP
socket. While they do, you watch the same conversation at three levels at once:

| Level | What you see | Tool |
|-------|--------------|------|
| **Your program** | what the C code does, line by line, and what it prints | `printf`, `gdb` |
| **The kernel boundary** | every *system call* the program makes into the operating system | `strace` |
| **The network** | every TCP packet that the kernel puts on the wire | `tcpdump` |

Everything runs inside one Linux container, so it works the same on Windows,
macOS and Linux, and you cannot break anything on your own computer.

## 1. Get the files

You need **Docker** or **Podman**, either one. The lab works the same with both.

With git:

```bash
git clone https://github.com/VelkyVenik/muni-pb158-examples.git
cd muni-pb158-examples/socket-lab
```

Without git: on the [GitHub page](https://github.com/VelkyVenik/muni-pb158-examples)
click **Code → Download ZIP**, unzip it, and in the terminal `cd` into the
`socket-lab` folder inside it. (`cd` means "change directory". Tip: type `cd `
and drag the folder into the terminal window.)

## 2. Start the lab

From the `socket-lab` folder:

| Your computer | Open | Type |
|---------------|------|------|
| **macOS, Linux** | Terminal | `./lab.sh` |
| **Windows** | PowerShell or Windows Terminal (not Git Bash) | `.\lab.cmd` |
| **Windows, inside WSL** | your WSL terminal | `./lab.sh` |

The script finds out whether Docker or Podman works on your computer. It checks that
it is installed, that it is running, that it can run a test container (`hello-world`)
and that it has `compose`. Then it starts the lab:

```text
Checking docker...
  OK    installed
  OK    running
  OK    can run containers
  OK    compose (docker compose)

Starting:  docker compose run --rm lab
```

If a check fails, the script tells you what to do (for example "Start Docker Desktop" or
`podman machine start`). If you have both and want Podman, run `LAB_ENGINE=podman ./lab.sh`
(PowerShell: `$env:LAB_ENGINE="podman"; .\lab.cmd`).

The first start builds the lab image, which takes a few minutes. After that it starts
in seconds. The demo then **runs by itself**: the server starts, waits, and two
seconds later the client connects.

> **To quit, press `Ctrl-b`, release it, then press `d`.** This closes the lab and
> stops the container. See [tmux basics](#tmux-basics) for more keys.

## 3. The four modes

Each mode is the same demo with a different amount of detail. Go through them in this order
(on Windows, `.\lab.cmd strace` and so on):

| Command | Adds | Use it to see |
|---------|------|---------------|
| `./lab.sh` | program output + packets | the big picture: who sends what, and when |
| `./lab.sh strace` | + system calls (`strace`) | what the program asks the kernel, and what it gets back |
| `./lab.sh step` | + the C code, line by line (`gdb`) | which line of C is running, and where it waits |
| `./lab.sh step_strace` | C lines + system calls + packets, all together | one socket call going through every level |

`step_strace` is the goal: one line of C, the system call it makes, the program's
output and the packet that follows, all on one screen. The first three modes
introduce those pieces one at a time.

Without the script, the same thing is `docker compose run --rm <mode>` or
`podman compose run --rm <mode>` (or `podman-compose run --rm <mode>`), where
`<mode>` is `lab`, `strace`, `step` or `step_strace`.

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

<details>
<summary>Answers to 1 and 2</summary>

1. Every program starts with three files already open: `0` = standard input (keyboard),
   `1` = standard output, `2` = standard error (both the terminal). The kernel always
   hands out the **lowest free** number, so the first new one is `3`.
2. `fd=4`, the connection. The listening socket `fd=3` never carries data. Its only job
   is to accept new connections. A server talking to 100 clients has one listening
   socket plus 100 connection sockets.

</details>

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

> **Careful: TCP does not keep messages apart.** Here one `send()` happens to give one
> `DATA` packet and one `recv()`, because the messages are tiny. TCP only promises
> that the *bytes* arrive, in order. The kernel may split one `send()` into several
> packets, or join several sends into one `recv()`. Real programs call `recv()` in a
> loop until they have the whole message. [Experiment 4](#4-a-message-bigger-than-the-buffer) shows this.

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
./lab.sh strace      # Windows: .\lab.cmd strace
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
6. **Errors come back from the kernel too.** Run `./trace ./client` with the server stopped:
   `connect(...) = -1 ECONNREFUSED`. The `dup(2) = 4` and `close(4)` after it come from
   `perror()`, which prints the error message through a copy of stderr (fd 2).

To trace something by hand, press `Ctrl-C` in a pane (or use a free shell) and run:

```bash
./trace ./client                         # what strace mode runs: highlighted socket calls
strace -e trace=network,close ./server   # plain strace: networking calls + close
strace ./client                          # everything, including memory and file calls
```

## Stepping through the code (step)

```bash
./lab.sh step      # Windows: .\lab.cmd step
```

The server and client run under the `gdb` debugger, which executes `main()` one
line at a time and prints each line of C code just *before* running it, together
with the comment above it (in grey):

```text
│          /* 3. listen() turns it into a listening socket. From now on the kernel
│           *    does the TCP handshake with clients by itself and queues finished
│           *    connections (up to 5 here) until we accept() them. */
│  60      printf("SERVER: calling listen()\n");
SERVER: calling listen()
│  61      rc = listen(listen_fd, 5);
│  62      if (rc < 0) {
...
│  77          int conn_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &client_len);
```

The number is the line in `server.c` / `client.c`, so you can follow along in your editor.
The comments come straight from the source: edit a comment, and the demo shows your text.

What to observe:

1. **Where a program blocks.** The last line on screen is the one running *now*. When it is
   `accept(...)` or `recv(...)` and nothing moves, the program is waiting inside that call.
2. **Which `if` branches run.** The error branches (`if (rc < 0) {`) are checked but skipped.
   After the client closes, the server goes through `if (n == 0)`.
3. **The loop.** After one client, the server jumps back to `for (;;)` and stops at `accept()` again.
4. **Both sides at once.** Watch the client's `send(...)` line and the server's `recv(...)` line
   finish at the same moment, and the `DATA` packet appear below.

Too fast or too slow? In a pane, `Ctrl-C`, then for example `STEP_DELAY=1 ./step ./client`.

### Code and system calls together (step_strace)

```bash
./lab.sh step_strace      # Windows: .\lab.cmd step_strace
```

Same as `step`, plus the system calls each line makes, right below it:

```text
│  77          int conn_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &client_len);
      ↳ accept(3, 127.0.0.1:56042) = 4
│  93          ssize_t n = recv(conn_fd, buf, sizeof(buf) - 1, 0);
      ↳ recvfrom(4, "Hello server!", 1023) = 13
```

Now you can follow one call through all layers: the C line, the system call
(`recv()` becomes `recvfrom()`), the program's own output, and the packet below.
While a call is blocked, its line stays unfinished: `↳ accept(3`.

strace itself cannot run together with gdb (a process can only be traced by one
tool at a time), so here gdb catches the system calls (`step.py`). It shows fewer
details than strace, but enough to see what goes into the kernel and what comes back.

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

## Experiments

The server keeps running and waits for the next client, so you can run the
client again in the CLIENT pane (click it first) at any time:

```bash
./client
```

Try the experiments below in the plain `lab` mode first, then in `strace` mode
(there, use `./trace ./client` and `./trace ./server` to see the system calls).
**Guess the result before you look**, then open the answer.

### 1. Two clients at once

In the CLIENT pane run:

```bash
./client > /dev/null & sleep 1; ./client
```

This starts one client in the background (its output is thrown away) and a second one a second later.
The server handles one client at a time. What happens to the second client's `connect()`?
Watch the PACKETS pane.

<details>
<summary>What happens</summary>

The second client's `SYN`, `SYN-ACK`, `ACK` appear **immediately**, and its `connect()`
returns, even though the server program is busy with the first client and has not
called `accept()`. Its `"Hello server!"` is even acknowledged (`ACK`) by the server's kernel.
Only the reply comes later, after the server finishes with the first client.

That is what `listen(listen_fd, 5)` means: the **kernel** accepts up to 5 connections by itself
and queues them. `accept()` only takes the next one from that queue.

</details>

### 2. Kill the client

Run `./client` and press `Ctrl-C` while it says `sleeping 2 s before sending...`.

<details>
<summary>What happens</summary>

The packets show the handshake, then a `FIN` from the client with no `DATA` before it.
The server's first `recv()` returns `0` (`client closed the connection`).

The client never called `close()`. When a program ends, for whatever reason, the kernel
closes all its file descriptors, and closing a TCP socket sends a `FIN`.

</details>

### 3. Be the client yourself

`nc` (netcat) is a ready-made program that connects to a server and sends whatever you type:

```bash
nc 127.0.0.1 8080
```

Type `hello`, press Enter and wait. Then press `Ctrl-C` to quit `nc`.

<details>
<summary>What happens</summary>

The server receives `"hello\n"`, **6 bytes**: Enter adds a newline character (`\n`).
You see `Hello client!` as the reply. Then nothing happens until you press `Ctrl-C`,
because the server waits for the client to close the connection.

The server does not know or care that the other side is not `./client`. A protocol is only
an agreement about which bytes go back and forth.

</details>

### 4. A message bigger than the buffer

The server reads at most 1023 bytes per `recv()` (`BUF_SIZE` is 1024, minus one for the `'\0'`).
Send it 2000. In `client.c`, replace the line

```c
    const char *msg = "Hello server!";
```

with

```c
    char msg[2001];
    memset(msg, 'A', 2000);   /* 2000 times the letter A */
    msg[2000] = '\0';
```

then run `make` and `./client` in the CLIENT pane.

<details>
<summary>What happens</summary>

The packets show **one** `DATA` packet of 2000 bytes. But the server's first `recv()` returns
`1023`, and its *second* `recv()`, the one meant to wait for the close, returns the remaining
`977`. One `send()` was split across two `recv()` calls: TCP is a stream of bytes, not of messages.

Undo your change afterwards (with git: `git checkout client.c`).

</details>

### 5. Start a second server

Click the SERVER pane and press `Ctrl-b "` (Ctrl-b, then the double-quote key). This opens a new pane.
Run `./server` there.

<details>
<summary>What happens</summary>

`bind() failed: Address already in use`. Only one socket can listen on 127.0.0.1:8080.
Close the extra pane with `exit`.

</details>

### Changing the code

Your local files are mounted into the container. Edit `server.c` or `client.c` in
your usual editor on your computer, then **inside the lab** run:

```bash
make                  # rebuild server and client
./client              # run the new client
```

To restart the server, press `Ctrl-C` in its pane and run `./server`.
`make clean` removes the built programs.

## tmux basics

`Ctrl-b` means: press Ctrl+b, release it, then press the next key.

| Action                    | Keys                                     |
|---------------------------|------------------------------------------|
| Move to another pane      | click it, or `Ctrl-b` + arrow key        |
| Scroll up in a pane       | mouse wheel, or `Ctrl-b [` then arrows / PgUp. `q` stops scrolling |
| Zoom a pane to full size  | `Ctrl-b z` (again to unzoom)             |
| Quit the lab              | `Ctrl-b d`                               |

Quitting stops the container. The next `./lab.sh` starts fresh.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `./lab.sh: Permission denied` | The ZIP lost the "executable" bit. Run `bash lab.sh` instead. |
| Windows: `.\lab.cmd` is not recognized | You are not in the `socket-lab` folder. `cd` into it (it contains `lab.cmd`). |
| `This is Git Bash...` / `the input device is not a TTY` | Git Bash cannot run the lab. Use PowerShell or Windows Terminal and `.\lab.cmd`. |
| `docker is installed but not running` | Start Docker Desktop and wait until it says it is running. Linux: `sudo systemctl start docker`. |
| `podman is installed but not running` | macOS/Windows: `podman machine start` (the very first time `podman machine init` first). |
| `permission denied ... docker.sock` (Linux) | Add yourself to the `docker` group ([how](https://docs.docker.com/engine/install/linux-postinstall/)), then log out and in. |
| Linux + Podman: `podman compose` fails with "Cannot connect" | Install `podman-compose` (the script then uses it), or start Podman's socket: `systemctl --user enable --now podman.socket`. |
| `compose is missing` | Docker: install the [Compose plugin](https://docs.docker.com/compose/install/) (Docker Desktop has it). Podman: install `podman-compose`. |
| `cannot run a container` | Usually no internet for downloading the test image, or not enough disk space. The script shows the error. |
| `Permission denied` on SELinux systems (Fedora, RHEL) | `compose.yaml` already sets `label=disable`. If you start the container another way, add `--security-opt label=disable`. |
| `./packets: Permission denied` | The ZIP lost the "executable" bit. Quit and start the lab again (it fixes it), or run `chmod +x packets trace step step_strace`. |
| `cannot execute binary file: Exec format error` | `server`/`client` were built on your computer, not in the container. Run `make -B` inside the lab. |
| The panes are tiny or garbled | Make the terminal window bigger *before* starting. `Ctrl-b z` zooms one pane. |
| I closed the terminal window and the lab is still running | `docker ps` (or `podman ps`) shows it. Stop it with `docker stop <ID>` (or `podman stop <ID>`). |
| I changed the `Dockerfile` | Rebuild the image: `docker compose build` (or `podman compose build`). |
| `make clean` fails on Linux with "Permission denied" | Files built in the container belong to root. Run `make clean` inside the lab. |
| `step` is too slow / too fast | `Ctrl-C` in the pane, then `STEP_DELAY=0.2 ./step ./server` (seconds per line). |

## Files

| File          | Purpose                                              |
|---------------|------------------------------------------------------|
| `server.c`    | the server                                           |
| `client.c`    | the client                                           |
| `Makefile`    | builds both with `-g -O0 -Wall -Wextra -Wpedantic`   |
| `start.sh`    | builds, creates the tmux layout, starts everything (`bash start.sh strace` / `step` / `step_strace` for the other modes) |
| `trace`       | runs a program under strace and highlights the system calls |
| `step`        | runs a program under gdb, printing each line of C code as it runs |
| `step_strace` | the same, plus the system calls each line makes      |
| `step.py`     | the gdb (Python) script behind `step` and `step_strace` |
| `packets`     | runs tcpdump and prints one readable line per packet |
| `lab.sh`      | starts the lab on macOS / Linux / WSL: finds a working Docker or Podman, then runs compose |
| `lab.cmd`, `lab.ps1` | the same for Windows (`lab.cmd` only starts `lab.ps1`) |
| `Dockerfile`  | Debian 12 with gcc, make, gdb, strace, tcpdump, tmux, iproute2, netcat |
| `compose.yaml`| runs the container and mounts this directory at `/lab` |
