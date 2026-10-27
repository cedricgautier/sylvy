# Lesson 5 — Sockets, ports and `/proc/net`

> For **F3**. How to find every listening port and tie each one back to the process that opened it. Guided — you write the parser.

## Why listening ports matter

A **listening port** is a process waiting for incoming network connections. Legitimate ones are known: your SSH server on 22, a web server on 80. A **backdoor** is a process that opens a new listening port so an attacker can connect in. So the rule is simple: record which ports are listening when the agent starts (the baseline), and alert on any new one that appears afterwards.

## Reading the ports: `/proc/net/tcp`

The kernel lists every TCP socket in two virtual files: `/proc/net/tcp` (IPv4) and `/proc/net/tcp6` (IPv6). **You must read both**, or an IPv6-only backdoor slips past. Look at the raw shape first:

```bash
head -3 /proc/net/tcp       # columns, all hexadecimal
ss -tlnp                    # the friendly version, to check your parsing against
```

Each line is one socket. Three columns matter, and they are all **hexadecimal**:

- **local_address**, formatted `ADDRESS:PORT` — e.g. `0100007F:1F90` is 127.0.0.1 port 8080 (0x1F90 = 8080).
- **state** — `0A` means `TCP_LISTEN`. You only care about listening sockets.
- **inode** — a number identifying the socket. This is the bridge to the owning process.

`ss` is just a polished reader of this same data via a Netlink API; for F3, parsing the file is simpler and pure Go.

## How to parse it from Go

- `os.ReadFile` each of the two files, split into lines, and **skip the header line**.
- For each line, `strings.Fields` to get columns; keep only those whose state column equals `0A`.
- Split the local-address column on the last `:`, and parse the port with `strconv.ParseUint(portHex, 16, 16)` — base **16**.
- Read the inode column as the socket identifier.

Build a function returning a map of `port -> inode`. Call it once at startup to record the baseline set, then on a timer to spot new ports.

## Tying a socket to a process: the inode bridge

`/proc/net/tcp` gives you a socket **inode** but not a PID. An open socket is a file descriptor in the owning process, and `/proc/<pid>/fd/<n>` is a symlink whose target is the string `socket:[INODE]`. So to find the owner: walk every numeric directory in `/proc`, read each entry under its `fd/`, and compare the link target against `socket:[<your inode>]`. See it by hand:

```bash
# who owns the socket with inode 12345?
sudo ls -l /proc/*/fd/ 2>/dev/null | grep 'socket:\[12345\]'
```

In Go this is `os.ReadDir("/proc")`, filtering names that parse as integers, then `os.ReadDir` on each `fd` directory and `os.Readlink` on each entry. This walk costs one pass over the machine's open descriptors, so do it **only for a newly seen port**, never on every scan.

## Don't poll too hard

Ports change rarely, so scanning every few seconds is plenty — the brief asks for a few-second interval. A `time.Ticker` at 3–5 seconds keeps CPU near zero while still catching a backdoor within the 10-second budget the contract allows. Add each new port to your baseline set after you alert, so you alert only once.

**Documentation to lean on:** `man 5 proc` (see the `/proc/net/tcp` and `/proc/<pid>/fd` sections), and the Go docs for `os.ReadFile`, `os.ReadDir`, `os.Readlink`, `strconv.ParseUint` and `time.Ticker`.

## Check yourself

- Why must you read `/proc/net/tcp6` as well as `/proc/net/tcp`?
- The port column reads `01BB`. What port is that? *(0x01BB = 443.)*
- Why resolve the PID only for new ports, not on every scan? *(The fd walk is expensive; ports rarely change.)*
- Which column tells you a socket is listening rather than connected? *(State `0A`.)*
