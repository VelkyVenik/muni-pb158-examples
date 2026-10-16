# step.py - loaded into gdb by ./step and ./step_strace (gdb has Python built in).
#
# Steps through main() one line at a time and prints each line of C just
# before it runs, together with the comment above it. With STEP_SYSCALLS=1
# (./step_strace) it also prints the socket system calls each line makes,
# much like strace does:
#
#   │      /* 4. accept() takes the next connection from the kernel's queue.
#   │  73          printf("SERVER: calling accept()\n");
#   ...
#   │  77          int conn_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &client_len);
#         ↳ accept(3, 127.0.0.1:56042) = 4
#
# The keyboard controls the pace. The program stops before every line that
# makes a socket call (socket(), connect(), send(), ...) and waits for a key:
#
#   Enter  run up to the next socket call
#   n      run just the next line
#   c      keep running, STEP_DELAY seconds per line (any key stops again)
#
# Why not simply run strace as well? A process can only be traced by one
# tool at a time, and gdb is already tracing it. So gdb catches the system
# calls itself ("catch syscall") and this script prints them.

import errno
import os
import re
import select
import socket
import struct
import termios
import time
import tty

import gdb

DELAY = float(os.environ.get("STEP_DELAY", "0.5"))     # seconds per line when running
SHOW_SYSCALLS = os.environ.get("STEP_SYSCALLS") == "1"
SYSCALLS = ["socket", "setsockopt", "bind", "listen", "accept", "accept4",
            "connect", "getsockname", "sendto", "recvfrom", "close", "dup"]

BAR = "\033[1;32m│\033[0m"
NUM, CODE, NAME, DATA, OK, ERR, OFF = (
    "\033[2m", "\033[1;32m", "\033[1;33m", "\033[1;35m", "\033[1;32m", "\033[1;31m", "\033[0m")
NOTE = "\033[2;3m"     # comments: dim italic

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


def signed(value):
    return value - (1 << 64) if value >> 63 else value


def show_syscall(name):
    """Called when the program enters a system call: print it, let it finish, print the result."""
    arg_regs, result_reg = registers()
    a = [register(r) for r in arg_regs]
    # No newline yet: if the call blocks, this unfinished line stays on screen.
    say("      ↳ %s%s%s(%s" % (NAME, name, OFF, args_at_entry(name, a)))

    # "catch syscall" stops the program twice: when it enters the kernel
    # (now) and when the kernel returns. Run until that return.
    run("continue")
    if not gdb.selected_inferior().pid:
        say(")\n")
        return

    # The kernel's own result: 0 or more on success, minus an errno code on
    # failure (the C library turns that into -1 and sets errno).
    result = signed(register(result_reg))
    if result >= 0:
        shown = OK + str(result) + OFF
    else:
        code = -result
        shown = ERR + "-1 %s (%s)" % (errno.errorcode.get(code, code), os.strerror(code)) + OFF
    say("%s) = %s\n" % (args_at_return(name, a, result), shown))


def back_to_main():
    """Run until the C library function (accept(), recv(), perror(), ...) returns
    to main(). It may make more system calls on the way: show those too."""
    while gdb.selected_inferior().pid and gdb.selected_frame().name() != "main":
        last_stop.clear()
        run("finish")
        while last_stop and gdb.selected_inferior().pid:
            show_syscall(last_stop.pop())
            last_stop.clear()


def at_start_of_new_line():
    """True if the program stands at the first instruction of a line not shown yet."""
    if not gdb.selected_inferior().pid:
        return False
    frame = gdb.selected_frame()
    sal = frame.find_sal()
    return sal.symtab is not None and sal.pc == frame.pc() and sal.line != previous_line[0]


# --- keyboard -----------------------------------------------------------------

# A line stops if it calls one of these (the text in "strings" does not count).
SOCKET_CALL = re.compile(r"\b(socket|setsockopt|bind|listen|accept|connect|getsockname|send|recv|close)\s*\(")
STRING = re.compile(r'"(\\.|[^"\\])*"')
KEYS = "Enter: next socket call   n: next line   c: run"

try:
    keyboard = os.open("/dev/tty", os.O_RDONLY)
except OSError:
    keyboard = None                          # no terminal (e.g. a test): just run
# "calls": stop before socket calls, "line": stop before every line, "run": don't stop
pace = ["calls" if keyboard is not None else "run"]
waiting = []                                 # set while the ⏸ hint is on screen


def read_key(timeout=None):
    """One key press, or None if none came within timeout seconds."""
    old = termios.tcgetattr(keyboard)
    try:
        tty.setcbreak(keyboard)              # keys arrive one by one, not after Enter
        ready, _, _ = select.select([keyboard], [], [], timeout)
        return os.read(keyboard, 1).decode(errors="ignore") if ready else None
    finally:
        termios.tcsetattr(keyboard, termios.TCSADRAIN, old)


def wait_before(code):
    """Called after a line is shown and before it runs: wait for a key, or a moment."""
    if pace[0] == "run":
        if keyboard is None:
            time.sleep(DELAY)
            return
        if read_key(DELAY) is None:
            return
        pace[0] = "line"                     # a key stops the running, right here
    if pace[0] == "calls" and not SOCKET_CALL.search(STRING.sub('""', code)):
        time.sleep(DELAY)
        return
    say("%s      ⏸ Enter / n / c%s" % (NUM, OFF))   # short: must fit a narrow pane
    termios.tcflush(keyboard, termios.TCIFLUSH)   # forget keys pressed earlier
    waiting.append(True)
    while True:
        key = read_key()
        if key in ("\n", "\r", " "):
            pace[0] = "calls"
        elif key == "n":
            pace[0] = "line"
        elif key == "c":
            pace[0] = "run"
        else:
            continue
        break
    waiting.clear()
    say("\r\033[2K")                         # remove the hint again


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


def source(symtab):
    path = symtab.fullname()
    if path not in source_files:
        with open(path) as f:
            source_files[path] = f.read().split("\n")
    return source_files[path]


def is_comment(text):
    stripped = text.strip()
    return stripped.startswith(("/*", "*", "//")) or stripped.endswith("*/")


def indent(text):
    return len(text) - len(text.lstrip())


previous_line = [None]  # line shown last


def comment_above(sal):
    """Line numbers of the comments to show before this line of code."""
    lines, table = source(sal.symtab), sal.symtab.linetable()
    here, before = sal.line, previous_line[0]
    previous_line[0] = here
    if before is not None and before < here:
        # Moving forward: comments between the previous line and this one.
        # Skip the ones indented deeper than this line: they belong to a
        # block that was jumped over (e.g. an "if" that was not taken).
        return [n for n in range(before + 1, here)
                if is_comment(lines[n - 1]) and indent(lines[n - 1]) <= indent(lines[here - 1]) + 1]
    # First line, or jumping back (a loop): the comment directly above,
    # up to the previous line that has code.
    found = []
    number = here - 1
    while number >= 1 and not table.has_line(number):
        if is_comment(lines[number - 1]):
            found.insert(0, number)
        number -= 1
    return found


def split_comment(code):
    """Split 'buf[n] = 0; /* note */' into code and its trailing comment."""
    in_string = False
    for i, c in enumerate(code):
        if c == '"' and code[i - 1:i] != "\\":
            in_string = not in_string
        elif not in_string and code.startswith(("/*", "//"), i):
            return code[:i], code[i:]
    return code, ""


last_comment = []    # first line of the comment shown last


def show_line(sal):
    lines = source(sal.symtab)
    comment = comment_above(sal)
    if comment and comment[:1] != last_comment:
        last_comment[:] = comment[:1]
        for number in comment:
            say("%s      %s%s%s\n" % (BAR, NOTE, lines[number - 1], OFF))
        time.sleep(DELAY * len(comment))     # time to read it
    code, note = split_comment(lines[sal.line - 1])
    note = NOTE + note + OFF if note else ""
    say("%s %s%3d%s  %s%s%s%s\n" % (BAR, NUM, sal.line, OFF, CODE, code, OFF, note))


for setting in ["debuginfod enabled off", "pagination off", "confirm off",
                "disable-randomization off"]:   # Docker does not allow turning ASLR off
    run("set " + setting)

gdb.events.stop.connect(on_stop)
gdb.events.exited.connect(on_exit)

run("break main")
# The program writes to the terminal. (gdb closes fd 9 when starting it,
# so open the same terminal again through /proc.)
run("run >> /proc/%d/fd/%d 2>&1" % (os.getpid(), TERMINAL))

if keyboard is not None:
    say("%s %sThe program stops before each socket call (⏸).%s\n" % (BAR, NUM, OFF))
    say("%s %s%s%s\n" % (BAR, NUM, KEYS, OFF))

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
        show_line(sal)
        wait_before(source(sal.symtab)[sal.line - 1])
        last_stop.clear()
        run("next")
        # A system call stops "next" half way. Show it, then finish the line.
        while last_stop and gdb.selected_inferior().pid:
            show_syscall(last_stop.pop())
            back_to_main()
            last_stop.clear()
            if at_start_of_new_line():
                break            # e.g. setsockopt(...); returns right onto the next line
            run("next")
except (Interrupted, KeyboardInterrupt, gdb.error):
    pass

if gdb.selected_inferior().pid:
    # Replace a waiting ⏸ hint; otherwise keep the unfinished line (e.g. "↳ accept(3").
    say("%s%s %s(stopped)%s\n" % ("\r\033[2K" if waiting else "\n", BAR, NUM, OFF))
    gdb.execute("kill", to_string=True)
elif exit_code:
    say("%s %s(program exited with %s)%s\n" % (BAR, NUM, exit_code[0], OFF))
