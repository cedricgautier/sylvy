# Lesson 3 — Netlink and the proc connector

> For **F1**. This is how your agent learns about executions without burning CPU. It guides you to build the minimal watcher from the [quick start](../quickstart.md#4-your-first-milestone-a-minimal-process-watcher) — you write the code.

## The wrong way: polling

The naive monitor scans `/proc` in a loop: list the directories, diff against last time, spot new PIDs. This is terrible. It misses every short-lived process (the ones most worth catching), and it burns CPU doing nothing most of the time. Sylvy forbids it for exactly these reasons.

## The right way: let the kernel push

Linux can **push** an event to you the instant something happens, so you sleep until there is real work. The transport is **Netlink**: a socket family (`AF_NETLINK`) designed for the kernel to talk to user-space programs. The specific service that reports process lifecycle events is the **proc connector**.

See it with a ready-made tool first, to build intuition for what you are about to receive:

```bash
sudo forkstat -e exec        # Debian/Ubuntu; else: sudo perf trace -e execve
```

Everything that scrolls past, your program will produce — `forkstat` is itself a thin wrapper over the proc connector.

## The four steps you implement

1. **Open** a Netlink socket of type `NETLINK_CONNECTOR` (`unix.Socket` with `AF_NETLINK`, `SOCK_DGRAM`).
2. **Bind** it, setting the socket's groups to the process-event connector group so the kernel will multicast events to you (`unix.Bind` with a `*unix.SockaddrNetlink`).
3. **Subscribe** by sending one message whose payload is the "listen" opcode (`PROC_CN_MCAST_LISTEN`). This is a handful of little-endian integers laid out as the headers below.
4. **Loop** on `unix.Recvfrom`. Parse each datagram into Netlink messages (`syscall.ParseNetlinkMessage`), and for each one inspect the event type.

Because you block in `Recvfrom`, an idle machine costs ~0 % CPU — that is how you hit the idle target.

## The message layout (reference)

Netlink messages are raw bytes with nested headers. You build the subscribe message and parse the incoming ones against this layout, which comes straight from the kernel UAPI headers `linux/connector.h` and `linux/cn_proc.h`. Treat this as your map; the parsing code is yours to write (read and write the integers with `encoding/binary`, native byte order).

From outside in, every connector message is:

| Part | Size | Notes |
|------|------|-------|
| `nlmsghdr` | 16 B | Netlink header: total length, type, flags, seq, pid |
| `cn_msg` | 20 B | Connector header: id `{idx, val}` = `{CN_IDX_PROC, CN_VAL_PROC}`, seq, ack, length |
| `proc_event` header | 16 B | `what` (event type), `cpu`, `timestamp_ns` |
| event body | varies | fields depend on `what` |

The `what` field is the key. For an **exec** event (`PROC_EVENT_EXEC`), the body carries the process's PID and TGID. Take the **TGID** ([lesson 2](02-fork-exec-exit.md) explains why), then enrich from `/proc` ([lesson 1](01-processes-and-proc.md)).

You do not need to memorise the numeric constants — define them in your code from the header names above, and keep a comment pointing at the UAPI header so a reader (and the oral examiner) can follow.

**Documentation to lean on:** `man 7 netlink`, the kernel source for `cn_proc.h` and `connector.h` (browse on elixir.bootlin.com), and the `golang.org/x/sys/unix` package docs for `Socket`, `Bind`, `Sendto`, `Recvfrom` and `SockaddrNetlink`.

## Reliability: the buffer can overflow

The kernel delivers events into a socket buffer. Under a storm of executions (the P3/P4 burst test), if you read too slowly the buffer fills and the kernel drops events, signalling `ENOBUFS` on the read. Two defences:

- Enlarge the receive buffer with `SetsockoptInt` and `SO_RCVBUF`.
- Keep the read loop tight: read, hand off the slow work (`/proc`, hashing) without blocking the next read for long.

Detecting `ENOBUFS` and logging "events lost" beats missing them silently — and P4 only requires 90 % capture, so a reasonable implementation passes.

## Check yourself

- Why does blocking on `Recvfrom` give near-zero idle CPU, while polling `/proc` does not?
- What is `ENOBUFS` telling you, and what are two ways to reduce it?
- The proc connector also reports `fork` and `exit`. Why does F1 only need `exec`?
- In your subscribe message, which field says "I want the process-event group", and which integer is the listen opcode?
