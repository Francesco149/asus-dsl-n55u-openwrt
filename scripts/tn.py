#!/usr/bin/env python3
"""Run shell commands on the router over its stock telnetd (BusyBox).

Usage: tn.py [-H host] [-u user] [-p pass] [-t timeout] 'cmd1' ['cmd2' ...]
Telnet must be enabled first (Administration > System > Enable Telnet). Login = web admin creds.
"""
import argparse
import socket
import sys
import time

IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240


class Telnet:
    def __init__(self, host, port=23, timeout=10):
        self.s = socket.create_connection((host, port), timeout=timeout)
        self.buf = b""

    def _recv(self):
        data = self.s.recv(65536)
        if not data:
            raise EOFError("connection closed")
        out, i = bytearray(), 0
        while i < len(data):
            b = data[i]
            if b == IAC and i + 1 < len(data):
                cmd = data[i + 1]
                if cmd in (DO, DONT, WILL, WONT) and i + 2 < len(data):
                    opt = data[i + 2]
                    # refuse everything; we just want a dumb byte stream
                    reply = WONT if cmd in (DO, DONT) else DONT
                    self.s.sendall(bytes([IAC, reply, opt]))
                    i += 3
                    continue
                if cmd == SB:
                    j = data.find(bytes([IAC, SE]), i)
                    i = len(data) if j < 0 else j + 2
                    continue
                i += 2
                continue
            out.append(b)
            i += 1
        self.buf += bytes(out)

    def read_until(self, token: bytes, timeout=10):
        end = time.time() + timeout
        while token not in self.buf:
            if time.time() > end:
                raise TimeoutError(f"waiting for {token!r}; got {self.buf[-200:]!r}")
            self.s.settimeout(max(0.1, end - time.time()))
            self._recv()
        i = self.buf.index(token) + len(token)
        out, self.buf = self.buf[:i], self.buf[i:]
        return out

    def send(self, line: str):
        self.s.sendall(line.encode() + b"\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-H", "--host", default="192.168.1.1")
    ap.add_argument("-u", "--user", default="admin")
    ap.add_argument("-p", "--password", default="admin")
    ap.add_argument("-t", "--timeout", type=float, default=30)
    ap.add_argument("-s", "--stream", action="store_true",
                    help="stream output of the (single) command live instead of at the end")
    ap.add_argument("cmds", nargs="+")
    a = ap.parse_args()
    if a.stream:
        return stream(a)

    t = Telnet(a.host, timeout=a.timeout)
    t.read_until(b"login: ")
    t.send(a.user)
    t.read_until(b"assword: ")
    t.send(a.password)
    t.read_until(b"# ", a.timeout)
    for n, c in enumerate(a.cmds):
        # Bracket the output with markers built at runtime ("__B" "EG..."), so the terminal's
        # echo of the command line (which BusyBox may wrap) can never match them.
        beg, end = f"__BEG{n}__", f"__END{n}__"
        t.send(f"echo __B\"\"EG{n}__; {c}; echo; echo __E\"\"ND{n}__")
        t.read_until(f"\n{beg}".encode(), a.timeout)
        out = t.read_until(f"\n{end}".encode(), a.timeout).decode(errors="replace")
        t.read_until(b"# ", a.timeout)  # consume the next prompt
        body = out[: -len(end)].replace("\r", "").strip("\n")
        sys.stdout.write(body + "\n")
        sys.stdout.flush()
    t.send("exit")


def stream(a):
    """Run one command and copy its output to stdout as it arrives (until a marker or timeout)."""
    t = Telnet(a.host, timeout=a.timeout)
    t.read_until(b"login: ")
    t.send(a.user)
    t.read_until(b"assword: ")
    t.send(a.password)
    t.read_until(b"# ", a.timeout)
    mark = b"__STREAM_END__"
    t.send(f"{' ; '.join(a.cmds)}; echo; echo {mark.decode()}")
    end = time.time() + a.timeout
    t.buf = b""
    while time.time() < end:
        t.s.settimeout(max(0.1, end - time.time()))
        try:
            t._recv()
        except (socket.timeout, TimeoutError):
            continue
        if b"\n" in t.buf:
            lines, t.buf = t.buf.rsplit(b"\n", 1)
            for ln in lines.split(b"\n"):
                if mark in ln and b"echo" not in ln:
                    t.send("exit")
                    return
                sys.stdout.write(ln.decode(errors="replace").rstrip("\r") + "\n")
            sys.stdout.flush()
    t.send("exit")


if __name__ == "__main__":
    main()
