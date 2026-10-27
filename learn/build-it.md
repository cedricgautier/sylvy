# 🧪 Build-it milestone: the process monitor

> The first hands-on milestone of the [study path](README.md) — study milestone **A1**, the foundation the whole project grows from. You build a pure-Go agent that watches every execution on a Linux host and flags suspicious behaviour, then prove it with the automatic [test harness](tests/sylvy-test.sh). Start with the [quick start](quickstart.md) and read the [lessons](lessons/) as you go.

This milestone exists to make the kernel concepts concrete. By the end you will have watched real processes from a program you wrote, hit the exec race in person, and have an agent whose behaviour is verified by a test suite — the understanding every later phase builds on.

## What to build

| ID | Requirement |
|----|-------------|
| F1 | Detect every `exec` via the **Netlink proc connector**: PID, PPID, UID, binary path, command line |
| F2 | Flag **suspicious paths**: execution from `/tmp`, `/dev/shm`, `/var/tmp`; `(deleted)` binaries; `memfd:` execution |
| F3 | List **listening ports** (`/proc/net/tcp` and `tcp6`), attach each to its process, alert on a new one |
| F4 | **Alerts** as JSON Lines on stdout, in the exact format below |
| B1 | *(optional)* **Package provenance**: does the binary belong to a package your distro's package manager installed? |
| B2 | *(optional)* SHA-256 of binaries with a per-inode cache |

## Interface contract

The [test harness](tests/sylvy-test.sh) checks the output automatically, so the agent must follow this format exactly or its detections won't register.

- Launch: `sudo ./sylvy`, no argument. It runs until killed.
- **stdout**: one JSON object per line, flushed immediately. **stderr**: everything else (logs, debug).
- Fields: `ts` (RFC 3339), `level` (`info`, `warn` or `alert`), `rule`, `pid`, `ppid`, `uid`, `exe` (value of `/proc/<pid>/exe`), `cmdline`, `port` (network rules), `reason` (free text).

| `rule` | `level` | When to emit it |
|--------|---------|-----------------|
| `EXEC` | `info` | On **every** execution, even if `/proc` could not be read (empty fields) |
| `SUSPICIOUS_PATH` | `alert` | The real binary is under `/tmp/`, `/dev/shm/` or `/var/tmp/` |
| `DELETED_BINARY` | `alert` | `exe` ends with ` (deleted)` |
| `MEMFD_EXEC` | `alert` | `exe` starts with `/memfd:` |
| `UNKNOWN_LISTEN_PORT` | `alert` | A TCP port (IPv4 or IPv6) starts listening that was not open when the agent started; `pid` = owning process |
| `UNPACKAGED_BINARY` | `warn` | *(bonus B1)* The binary belongs to no installed package |

Maximum delays: **2 s** for exec-related rules, **10 s** for `UNKNOWN_LISTEN_PORT`.

```json
{"ts":"2026-10-02T09:14:03.512Z","level":"alert","rule":"SUSPICIOUS_PATH","pid":4242,"ppid":1337,"uid":1000,"exe":"/tmp/.x/kworker","cmdline":"/tmp/.x/kworker","reason":"executed from /tmp/"}
```

An agent that alerts on everything gains nothing: the harness also checks each rule against legitimate processes, and a wrongful alert cancels the credit.

## Performance targets

| Metric | Target |
|--------|--------|
| Idle CPU | **< 1 %** of one core |
| CPU during a burst of 3,000 executions | **< 10 %** of one core, with at least 90 % of `exec` captured |
| Resident RAM | **< 30 MB** |

**Design rules:** process events pushed by the kernel (no polling `/proc` in a loop), port scan limited to a few-second interval.

## Technical constraints

- **100 % Go ≥ 1.22**, not a single line of C, `CGO_ENABLED=0`. Only allowed external dependency: `golang.org/x/sys`.
- **Target:** any modern Linux VM (see the [quick start](quickstart.md)).
- **Launch:** a single binary, `sudo ./sylvy`.

## Proving it

Run the harness and read its report; the full scenario list and how it scores are in the [test plan](test-plan.md).

```bash
go build -o sylvy ./cmd/sylvy
chmod +x tests/sylvy-test.sh
sudo ./tests/sylvy-test.sh ./sylvy
```

You're done with A1 when the harness passes and you can explain an `exec`'s journey end to end — kernel → proc connector → Netlink → your agent → `/proc` → JSON alert. From here the [skill roadmap](skill-roadmap.md) extends this into eBPF and beyond, and the [project roadmap](../docs/roadmap.md) turns it toward Sylvy.

> ⚠️ **Ethics:** all attack-simulation tests run only inside a VM you control.
