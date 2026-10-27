# Learn: the internals Sylvy stands on

> A self-contained, build-it-yourself course in the Linux and kernel foundations that Sylvy is built on. You don't need this to *deploy* Sylvy — you need it to *build and extend* Sylvy with confidence. Everything is taught from scratch, in order, with no prior kernel knowledge assumed. The lessons guide you to write the code yourself; they don't hand you solutions.

Back to [Sylvy](../README.md).

## Start here

1. **[Quick start](quickstart.md)** — set up a Linux VM (any distro), do the kernel warm-up, and write your first process watcher.
2. **[Kernel study notes](kernel-study.md)** — what the kernel is, its history, and why kernel-level observation is the source of truth.
3. **[Base lessons](lessons/)** — processes and `/proc`, fork/exec and the exec race, Netlink, path attacks, sockets and ports, privilege and capabilities.
4. **[The first project: a process monitor](build-it.md)** — a pure-Go agent that watches every execution on a Linux host and flags suspicious behaviour, proven by an automatic [test harness](tests/sylvy-test.sh). This is the foundation everything else grows from.
5. **[Skill roadmap](skill-roadmap.md)** — how these foundations extend into a full Linux security-engineering skill set: eBPF, reverse engineering, MCP, AI/ML triage, vulnerability research, containment, and identity.

## How this connects to Sylvy

Each milestone here demystifies a tool the platform integrates: you write process monitoring by hand before consuming Tetragon, boot a microVM yourself before driving Firecracker, build a toy attestor before wiring in SPIRE. Understand it small, then stand on the real thing. The platform's own build guides live in [`../docs/building/`](../docs/building/).

## Notes

- Everything runs inside a **Linux VM you control**, never on infrastructure you don't own.
- The [test plan](test-plan.md) explains the scenarios and how the harness scores the first project.
- `grading/` contains a stricter grading harness and notes, useful if you run this course for others.

> ⚠️ **Ethics:** all attack-simulation exercises run only inside a VM you control.
