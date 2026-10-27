# 🚀 Quick start: get Sylvy going

> Goal: a VM ready in about an hour, then **understand what the kernel does** before writing any real code, then run a first monitor in pure Go. Read the [lessons](lessons/) alongside this page. Companion to the [build-it milestone](build-it.md) and the [test plan](test-plan.md).

## 1. The VM in 15 minutes

Use **any modern Linux distribution** in a VM (2 vCPU, 4 GB RAM, 20 GB disk, NAT + host-only network). The project is distro-neutral — it only relies on the Linux kernel's `/proc`, Netlink and fanotify interfaces, which every mainstream distro ships. Pick what you are comfortable with; the table maps the package names.

A kernel **≥ 5.3** is enough (any distro from 2020 onward). Everything below works the same once the tools are installed.

### Install Go (same on every distro)

Prefer the official tarball over the distro package — distro Go is often too old, and this keeps every machine identical:

```bash
curl -LO https://go.dev/dl/go1.22.5.linux-amd64.tar.gz      # use linux-arm64 on ARM VMs
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc && source ~/.bashrc
```

### Install the tools

You need three groups: a build toolchain, a few programs to *observe* the kernel while you learn, and the handful the test script calls (`jq`, `python3`, `setpriv` from util-linux, `ss` from iproute2). Pick your package manager:

| Distro family | Build + observe | Test-script tools |
|---------------|-----------------|-------------------|
| Debian / Ubuntu | `sudo apt install -y git make gcc strace lsof htop` | `sudo apt install -y jq python3 util-linux iproute2` |
| Fedora / RHEL / Rocky | `sudo dnf install -y git make gcc strace lsof htop` | `sudo dnf install -y jq python3 util-linux iproute` |
| Arch / Manjaro | `sudo pacman -S --needed git make gcc strace lsof htop` | `sudo pacman -S --needed jq python util-linux iproute2` |
| openSUSE | `sudo zypper install -y git make gcc strace lsof htop` | `sudo zypper install -y jq python3 util-linux iproute2` |

Optional but nice for the warm-up: `forkstat` and `fatrace` exist on Debian/Ubuntu; on other distros use `perf trace`, `execsnoop` (from bcc or bpftrace), or plain `strace` instead — the warm-up table notes the alternative.

**Recommended comfort:** develop from your host with **VS Code + the Remote-SSH extension** (`ssh user@vm-ip`), and take a snapshot named `clean` now.

**Check:** `go version` prints 1.22+, `uname -r` prints your kernel (≥ 5.3), and running any command in one terminal produces events in another when you watch with `strace -f -e execve` or `sudo forkstat`.

## 2. Read the lessons in order

Each lesson is one page and teaches one concept: the idea, a hands-on part to see it on your own machine, the exact APIs and man pages to use, and checkpoints to know you have understood it. The lessons **guide you to write the code yourself** — they do not hand you the solution. Read them as you reach each requirement.

| # | Lesson | Covers | Needed for |
|---|--------|--------|-----------|
| 1 | [Processes and `/proc`](lessons/01-processes-and-proc.md) | What a process is, PID/PPID/UID, the `/proc` filesystem | F1 |
| 2 | [fork, exec and the exec race](lessons/02-fork-exec-exit.md) | How a program is launched, why a process can vanish before you read it | F1 |
| 3 | [Netlink and the proc connector](lessons/03-netlink-proc-connector.md) | How the kernel pushes events to you instead of you polling | F1 |
| 4 | [Attack techniques on the binary path](lessons/04-path-attacks.md) | `/tmp`, deleted binaries, `memfd`, masquerading | F2 |
| 5 | [Sockets, ports and `/proc/net`](lessons/05-sockets-and-ports.md) | Listening ports, matching a socket to its process | F3 |
| 6 | [Privilege, root and capabilities](lessons/06-privilege-and-capabilities.md) | Why the agent needs root, and how to keep it honest | oral, F1 |

## 3. Kernel warm-up (about 45 minutes)

Do these with the tools above before coding. Each shows a kernel mechanism your agent will reproduce in Go. The matching lesson explains what you see.

| # | Try this | What to notice |
|---|----------|----------------|
| 1 | `ls -l /proc/$$/` then `cat /proc/$$/status`, `readlink /proc/$$/exe` | `/proc` is virtual: the kernel builds these files on the fly (lesson 1) |
| 2 | `strace -f -e trace=execve ls` | Running a program is the `execve` system call (lesson 2) |
| 3 | `sudo forkstat -e exec` (or `sudo perf trace -e execve`, or `strace -f -e execve <cmd>`) while you work in another terminal | The kernel *pushes* events; no need to scan `/proc` in a loop (lesson 3) |
| 4 | `ss -tlnp` then `sudo lsof -i -P` | Listening ports, and which process owns each (lesson 5) |
| 5 | `grep Cap /proc/$$/status` | root is a set of separate *capabilities* (lesson 6) |

## 4. Your first milestone: a minimal process watcher

Before touching the full requirements, build the smallest possible program that **prints every execution on the machine**. It is the seed of F1, and once it runs, the rest of F1 is enrichment and formatting.

```bash
mkdir -p ~/sylvy/hello && cd ~/sylvy/hello
go mod init hello && go get golang.org/x/sys/unix
# write main.go yourself, guided by Lesson 3
CGO_ENABLED=0 go build -o hello . && sudo ./hello
```

[Lesson 3](lessons/03-netlink-proc-connector.md) walks you through exactly what to build, step by step: open a `NETLINK_CONNECTOR` socket, subscribe to process events, and read them in a loop. It gives you the message layout, the Go functions to call, and checkpoints — but you write the code. When it works you will see executions scroll by as you type commands in another terminal, including some that vanish before you can read their details (the exec race from [lesson 2](lessons/02-fork-exec-exit.md)).

**Milestone reached when:** your program prints a line for every command you run in another shell, and you can explain why some lines are missing their binary path.

From here, F1 is: take the PID from each event, read `/proc/<pid>` to add PPID, UID and the binary path ([lesson 1](lessons/01-processes-and-proc.md)), and print the result as JSON in the [contract](build-it.md#interface-contract) format. Then F2, F3 and F4 each add one focused piece.

## 5. A suggested order for the milestone

The [build-it milestone](build-it.md) is milestone A1. A sensible order to tackle it:

| Step | Goal | Done when… |
|------|------|-----------|
| 1 | VM ready, warm-up done, lessons 1–3 read, minimal watcher (section 4) running | You see your own commands scroll by |
| 2 | **F1** (add PPID/UID from `/proc/<pid>/status`) + **F4** (JSON in the [contract](build-it.md#interface-contract) format) + **F2** (suspicious paths, `deleted`, `memfd`) — read lesson 4 | Run the [test script](test-plan.md#3-run-the-automatic-tests): T1, T2, A1–A3 pass |
| 3 | **F3** (scan `/proc/net/tcp` and `tcp6` every 5 s, inode → PID via `/proc/*/fd`) — read lesson 5 | T3, A4 pass |
| 4 | False positives, performance; bonus B1 (package provenance) if you want it | No false positive on normal system services |
| 5 | Full test run, write up what the agent misses and why | The harness prints 0 failures |

**Golden rule:** get F1–F4 working roughly before polishing any one of them. A simple agent that catches the four scenarios beats an elegant one that catches only one.

## 6. Suggested repository layout

```text
sylvy/
├── cmd/sylvy/        # entry point
├── internal/procmon/    # proc connector (F1)
├── internal/check/      # paths (F2), optional package provenance (B1)
├── internal/ports/      # scan /proc/net/tcp (F3)
├── internal/alert/      # JSON output (F4)
└── tests/sylvy-test.sh  # provided, do not modify
```

## ⚠️ Common pitfalls

- **`sudo go run` fails:** `sudo` does not have your `PATH`. Build first, then `sudo ./binary`.
- **Duplicate events:** an old agent is still running in the background (`pgrep -a sylvy`).
- **`/proc/net/tcp` is hexadecimal:** address and port are in hex, state `0A` means `LISTEN`, and the `inode` column links back to the process via the `socket:[inode]` targets in `/proc/<pid>/fd/` (lesson 5).
- **The agent watching itself:** its own reads of `/proc` generate events. Filter out your own PID from the start.
