# step.py - loaded into gdb by ./step and ./step_strace (gdb has Python built in).
#
# Steps through main() one line at a time and prints each line of C just
# before it runs. With STEP_SYSCALLS=1 (./step_strace) it also prints the
# socket system calls each line makes, much like strace does:
#
#   │  69          int conn_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &client_len);
#         ↳ accept(3, 127.0.0.1:56042) = 4
#
# Why not simply run strace as well? A process can only be traced by one
# tool at a time, and gdb is already tracing it. So gdb catches the system
# calls itself ("catch syscall") and this script prints them.

import errno
import os
import socket
import struct
import time

import gdb

DELAY = float(os.environ.get("STEP_DELAY", "0.5"))     # seconds per line
SHOW_SYSCALLS = os.environ.get("STEP_SYSCALLS") == "1"
SYSCALLS = ["socket", "setsockopt", "bind", "listen", "accept", "accept4",
            "connect", "getsockname", "sendto", "recvfrom", "close"]
INT_RESULT = {"sendto": False, "recvfrom": False}      # these return ssize_t, the rest int

BAR = "\033[1;32m│\033[0m"
NUM, CODE, NAME, DATA, OK, ERR, OFF = (
    "\033[2m", "\033[1;32m", "\033[1;33m", "\033[1;35m", "\033[1;32m", "\033[1;31m", "\033[0m")

# gdb prints a lot of its own messages ("Breakpoint 1, main () at ...").
# Send all of gdb's output to /dev/null and write ours to the terminal
# through fd 9. The program gets the terminal too (see "run" below).
# STEP_DEBUG=1 keeps gdb's output, for when something goes wrong.
TERMINAL = 9
os.dup2(1, TERMINAL)
if not os.environ.get("STEP_DEBUG"):
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)


def say(text):
    os.write(TERMINAL, text.encode())


class Interrupted(Exception):
    """Ctrl-C was pressed."""


def run(command):
    gdb.execute(command, to_string=True)
    if interrupted:
        raise Interrupted()


# --- reading the program's memory and registers ------------------------------

def registers():
    """CPU registers holding a system call's arguments, and a function's result."""
    if "aarch64" in gdb.selected_inferior().architecture().name():
        return ["x0", "x1", "x2", "x3", "x4", "x5"], "x0"
    return ["rdi", "rsi", "rdx", "r10", "r8", "r9"], "rax"     # x86-64


def register(name):
    return int(gdb.selected_frame().read_register(name)) & 0xFFFFFFFFFFFFFFFF


def memory(address, size):
    return bytes(gdb.selected_inferior().read_memory(address, size))


def text(address, size):
    """Bytes in the program's memory, shown as a short "string"."""
    data = memory(address, min(size, 40))
    shown = "".join(chr(b) if 32 <= b < 127 else "\\n" if b == 10 else "\\x%02x" % b
                    for b in data)
    return DATA + '"' + shown + '"' + ("..." if size > 40 else "") + OFF


def address(pointer):
    """A struct sockaddr_in in the program's memory, as ip:port."""
    if not pointer:
        return "NULL"
    raw = memory(pointer, 8)
    if struct.unpack("<H", raw[:2])[0] != socket.AF_INET:
        return "{...}"
    return "%s:%d" % (socket.inet_ntoa(raw[4:8]), struct.unpack(">H", raw[2:4])[0])


# --- printing one system call -------------------------------------------------

def args_at_entry(name, a):
    """Arguments we can show when the call starts."""
    if name == "socket":
        return "%s, %s, %d" % ("AF_INET" if a[0] == 2 else a[0],
                               "SOCK_STREAM" if a[1] == 1 else a[1], a[2])
    if name == "setsockopt":
        return "%d, %s, %s, ..." % (a[0], "SOL_SOCKET" if a[1] == 1 else a[1],
                                    "SO_REUSEADDR" if a[2] == 2 else a[2])
    if name in ("bind", "connect"):
        return "%d, %s" % (a[0], address(a[1]))
    if name == "listen":
        return "%d, %d" % (a[0], a[1])
    if name == "sendto":
        return "%d, %s, %d" % (a[0], text(a[1], a[2]), a[2])
    return "%d" % a[0]           # the rest is only known when the call returns


def args_at_return(name, a, result):
    """Arguments the kernel filled in, shown when the call returns."""
    if name in ("accept", "accept4", "getsockname") and result >= 0:
        return ", " + address(a[1])
    if name == "recvfrom":
        return ", %s, %d" % (text(a[1], result) if result >= 0 else "...", a[2])
    return ""


def signed(value, name):
    bits = 32 if INT_RESULT.get(name, True) else 64
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def show_syscall(name):
    """Called when the program enters a system call: print it, let it finish, print the result."""
    arg_regs, result_reg = registers()
    a = [register(r) for r in arg_regs]
    # No newline yet: if the call blocks, this unfinished line stays on screen.
    say("      ↳ %s%s%s(%s" % (NAME, name, OFF, args_at_entry(name, a)))

    # Run until the C library function (accept(), recv(), ...) returns to main().
    while gdb.selected_inferior().pid and gdb.selected_frame().name() != "main":
        run("finish")
    if not gdb.selected_inferior().pid:
        say(")\n")
        return

    result = signed(register(result_reg), name)
    if result >= 0:
        shown = OK + str(result) + OFF
    else:
        code = int(gdb.parse_and_eval("*(int *) __errno_location()"))
        shown = ERR + "-1 %s (%s)" % (errno.errorcode.get(code, code), os.strerror(code)) + OFF
    say("%s) = %s\n" % (args_at_return(name, a, result), shown))


# --- stepping -----------------------------------------------------------------

catchpoints = {}     # catchpoint number -> system call name
last_stop = []       # system call that stopped the program, if any
exit_code = []
interrupted = []     # set when Ctrl-C stopped the program


def on_stop(event):
    if isinstance(event, gdb.SignalEvent) and event.stop_signal == "SIGINT":
        interrupted.append(True)
    for bp in getattr(event, "breakpoints", []):
        if bp.number in catchpoints:
            last_stop.append(catchpoints[bp.number])


def on_exit(event):
    exit_code.append(getattr(event, "exit_code", None))


source_files = {}


def source_line(sal):
    path = sal.symtab.fullname()
    if path not in source_files:
        with open(path) as f:
            source_files[path] = f.read().split("\n")
    return source_files[path][sal.line - 1]


for setting in ["debuginfod enabled off", "pagination off", "confirm off",
                "disable-randomization off"]:   # Docker does not allow turning ASLR off
    run("set " + setting)

gdb.events.stop.connect(on_stop)
gdb.events.exited.connect(on_exit)

run("break main")
# The program writes to the terminal. (gdb closes fd 9 when starting it,
# so open the same terminal again through /proc.)
run("run >> /proc/%d/fd/%d 2>&1" % (os.getpid(), TERMINAL))

if SHOW_SYSCALLS:
    for name in SYSCALLS:
        run("catch syscall " + name)
        catchpoints[max(bp.number for bp in gdb.breakpoints())] = name

try:
    while gdb.selected_inferior().pid:
        sal = gdb.selected_frame().find_sal()
        if not (sal.symtab and sal.line):
            run("continue")      # main() has returned: let the program finish
            continue
        say("%s %s%3d%s  %s%s%s\n" % (BAR, NUM, sal.line, OFF, CODE, source_line(sal), OFF))
        time.sleep(DELAY)
        last_stop.clear()
        run("next")
        # A system call stops "next" half way. Show it, then finish the line.
        while last_stop and gdb.selected_inferior().pid:
            show_syscall(last_stop.pop())
            last_stop.clear()
            run("next")
except (Interrupted, KeyboardInterrupt, gdb.error):
    pass

if gdb.selected_inferior().pid:
    say("\n%s %s(stopped)%s\n" % (BAR, NUM, OFF))
    gdb.execute("kill", to_string=True)
elif exit_code:
    say("%s %s(program exited with %s)%s\n" % (BAR, NUM, exit_code[0], OFF))
