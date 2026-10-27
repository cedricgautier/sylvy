# Lesson 6 — Privilege, root and capabilities

> For the **oral**, and to run the agent at all. Why Sylvy needs root, and how a well-behaved privileged tool limits the power it takes.

## Why the agent needs privilege

Most of what Sylvy does is reading other people's processes: their `/proc/<pid>/exe`, their open sockets, their command lines. The kernel protects that information — as a normal user you can only inspect your own processes. To see *every* process on the machine, the agent needs elevated privilege. That is also why a monitoring agent is a sensitive, high-value target: the same access that lets it watch everything would let an attacker who subverts it do anything.

## root is not one switch

We say "root" (UID 0) as if privilege were a single on/off switch, but Linux actually splits root's power into about 40 independent **capabilities**. Each one grants a specific ability. A few relevant here:

- `CAP_NET_ADMIN` — network administration.
- `CAP_SYS_PTRACE` / `CAP_DAC_READ_SEARCH` — read files and process state regardless of ownership.
- `CAP_SYS_ADMIN` — a catch-all for many powerful operations.

You can see a process's capabilities:

```bash
grep Cap /proc/self/status
capsh --decode=0000000000003000     # turn a hex bitmask into names
```

## The principle of least privilege

A good privileged tool takes **only** the capabilities it truly needs, and drops the rest. If the agent is ever exploited, the blast radius is limited to what it kept. For Sylvy running the proc connector and reading `/proc`, the honest answer at M2 level is: it needs to read all processes, so it runs as root for simplicity — but you should be able to *say* which capabilities would suffice and why dropping the others matters. That reasoning is what the oral rewards, more than a perfect implementation.

For these two days you will simply run `sudo ./sylvy`. If you have spare time, investigate dropping to a minimal capability set after the Netlink socket is open; mention it as future work either way.

## Protecting the agent itself

Because the agent is a target, a mature version would also: refuse to be killed by non-root users (systemd can restart it and log the event), protect its output and any config file from tampering, and never trust input it reads (a malicious filename must not crash it). You are not graded on building all this in two days, but naming these risks — ideally with a one-line threat model — is exactly the kind of security maturity an M2 project is meant to show.

## Check yourself

- Why can't a normal user read `/proc/1/exe`?
- What does "principle of least privilege" mean for this agent specifically?
- Name one way an attacker could attack the *monitor* rather than evade it, and one defence. *(e.g. kill it → systemd restart + alert; feed it a crafted filename → validate input.)*
