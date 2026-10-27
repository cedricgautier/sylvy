# 🧪 Test plan: what to watch and how the harness scores it

> The test plan for the [build-it milestone](build-it.md). Start with the [quick start](quickstart.md) and the [lessons](lessons/). Everything runs inside a **dedicated Linux VM you control**, never on infrastructure you don't own.

## 1. Tools needed on the VM

The test script is distro-neutral and needs only `jq`, `python3`, `setpriv` (from util-linux) and `ss` (from iproute2), plus basics every distro ships (`sleep`, `tail`). Install them with your package manager:

| Distro family | Command |
|---------------|---------|
| Debian / Ubuntu | `sudo apt install -y jq python3 util-linux iproute2` |
| Fedora / RHEL / Rocky | `sudo dnf install -y jq python3 util-linux iproute` |
| Arch / Manjaro | `sudo pacman -S --needed jq python util-linux iproute2` |
| openSUSE | `sudo zypper install -y jq python3 util-linux iproute2` |

## 2. What to watch

### Legitimate processes (must NOT raise an alert)

| Process | Normal behaviour |
|---------|------------------|
| `systemd` (PID 1) | Parent of most services |
| `sshd` | Listens on 22, already present when the agent starts |
| `nginx` | Listens on 80, binary in `/usr/sbin` from a package |
| `sleep`, `tail`, `python3` | Package binaries run from `/usr/bin` |

### Suspicious behaviour (must raise an alert)

| Indicator | Expected rule | Why it is suspicious |
|-----------|---------------|----------------------|
| Execution from `/tmp`, `/dev/shm`, `/var/tmp` | `SUSPICIOUS_PATH` | World-writable directories, typical of dropped payloads |
| `/proc/<pid>/exe` ends with `(deleted)` | `DELETED_BINARY` | Binary erased to hide its traces |
| `/proc/<pid>/exe` starts with `/memfd:` | `MEMFD_EXEC` | No file on disk (*fileless*) |
| A new listening port | `UNKNOWN_LISTEN_PORT` | Possible backdoor |

Lesson 4 explains each attack; lesson 5 explains the ports.

## 3. Run the automatic tests

The script starts your agent, replays every scenario, then checks the JSON output for the right alert **for the right PID**. A scenario that is not detected = **FAIL**.

```bash
go build -o sylvy ./cmd/sylvy
chmod +x tests/sylvy-test.sh   # in case it lost its exec bit on download
sudo ./tests/sylvy-test.sh ./sylvy
```

Runtime: about 90 seconds. Results land in `sylvy-results-<date>/`: `report.md` (the table), `alerts.jsonl` (everything your agent emitted) and `agent.stderr` (its logs). The script exits 0 only when everything passes.

To iterate faster: `IDLE_SECS=5 BURST_N=500 sudo -E ./tests/sylvy-test.sh ./sylvy`.

### What the script checks

| ID | Test | Expected rule | Points |
|----|------|---------------|--------|
| T1a | `/usr/bin/sleep` launched → event with the right PID and `exe` | `EXEC` | 8 |
| T1b | `ppid` and `cmdline` correct | `EXEC` | 5 |
| T1c | Process launched as `nobody` → `uid` = 65534 | `EXEC` | 5 |
| T2a | Copy of `sleep` run from `/tmp/<random>` | `SUSPICIOUS_PATH` | 6 |
| T2b | Copy of `sleep` run from `/dev/shm/<random>` | `SUSPICIOUS_PATH` | 6 |
| T3a | `python3 -m http.server` on a random port | `UNKNOWN_LISTEN_PORT` | 8 |
| T3b | Port attributed to the right PID | `UNKNOWN_LISTEN_PORT` | 2 |
| T4 | Every stdout line is valid JSON with `ts`, `level`, `rule`, `pid` | — | 5 |
| A1 | `kworker` in a hidden directory `/tmp/.<random>/` | `SUSPICIOUS_PATH` | 4 |
| A2 | Binary opened, deleted, then executed via its descriptor | `DELETED_BINARY` | 4 |
| A3 | Binary copied into memory (`memfd_create`) then executed | `MEMFD_EXEC` | 4 |
| A4 | `nc` hidden in `/tmp` listening on a random port | `SUSPICIOUS_PATH` + `UNKNOWN_LISTEN_PORT` | 4 |
| FP1 | No alert on the legitimate processes | none | 2 |
| FP2 | No alert on ports already open before the agent | none | 2 |
| P1 | Idle CPU < 1 % (20 s) | — | 4 |
| P2 | Peak RAM < 30 MB | — | 4 |
| P3 | CPU < 10 % during 3,000 executions | — | 3 |
| P4 | At least 90 % of those executions captured | — | 2 |
| P5 | Agent still alive at the end | — | 2 |
| B1 | *(bonus)* Binary outside any installed package reported | `UNPACKAGED_BINARY` | +4 |

Three rules keep the test honest:

- **Random names and ports** on every run: you cannot hard-code a filename or a port number.
- **Specificity:** a detection test only counts if the same rule was **not** emitted for the legitimate processes. Alerting on everything scores zero.
- **No free points:** performance and false-positive tests only count if the agent actually detects executions (T1a).

## 4. Reproduce a scenario by hand

Useful for debugging. Run `sudo ./sylvy | jq .` in one terminal, then in another:

```bash
# T2a / A1: execution from /tmp, disguised as a kernel thread
mkdir -p /tmp/.x && cp /usr/bin/sleep /tmp/.x/kworker && /tmp/.x/kworker 30 &

# A2: binary deleted before execution
sudo cp /usr/bin/sleep /usr/local/bin/upd
sudo python3 -c "import os; fd=os.open('/usr/local/bin/upd', os.O_RDONLY); os.unlink('/usr/local/bin/upd'); os.execve(fd, ['upd','30'], {})" &

# A3: fileless execution
python3 -c "import os; f=os.memfd_create('x'); os.write(f, open('/usr/bin/sleep','rb').read()); os.execve(f, ['sleep','30'], {})" &

# T3a / A4: new listening port from a binary hidden in /tmp
cp "$(command -v python3)" /tmp/.p && /tmp/.p -c "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',4444)); s.listen(); time.sleep(300)" &

# See what the kernel sees
for p in $(jobs -p); do echo "$p -> $(sudo readlink /proc/$p/exe)"; done
ss -tlnp
```

Cleanup: `kill $(jobs -p); rm -rf /tmp/.x /tmp/.p; sudo rm -f /usr/local/bin/upd`.

## 5. Checklist before the demo

- [ ] Snapshot `clean` restored, then `sudo ./tests/sylvy-test.sh ./sylvy` run end to end
- [ ] The `sylvy-results-*` folder is committed to the repo
- [ ] Failing tests are explained in the README's "known limitations" section
- [ ] You can explain an `exec`'s journey: kernel → proc connector → Netlink → agent → `/proc` → JSON alert
