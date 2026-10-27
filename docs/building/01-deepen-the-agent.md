# Roadmap Lesson 1 — Deepen the Linux agent

> Supports **Phase 1** of the [roadmap](../../learn/skill-roadmap.md). Go. Turns the base agent into something that understands the system, not just execs. Guidance and resources only — you design and write it.

## What you are building and why

A monitor that watches executions is useful; a monitor that also sees file access, memory layout and container context is what defenders actually run. Each addition below teaches a distinct kernel subsystem. Add them one at a time, keeping the idle-CPU and false-positive discipline from the base project.

## Mission 1 — File-access monitoring with fanotify

Watch who opens sensitive files (`/etc/shadow`, SSH private keys, your own config). fanotify is a kernel API that reports, and can even gate, file events.

- Learn the two modes: **notification** (you are told after the fact) and **permission** (`FAN_OPEN_PERM`, the kernel blocks until you answer). Permission mode is powerful and dangerous — if your agent stalls, every open on the watched path hangs. Start in notification mode.
- Map events back to the acting PID, then reuse your `/proc` enrichment from base [lesson 1](../../learn/lessons/01-processes-and-proc.md).
- **Resources:** `man 7 fanotify`, `man 2 fanotify_init`, `man 2 fanotify_mark`; `golang.org/x/sys/unix` exposes the syscalls.
- **Checkpoint:** reading `/etc/shadow` in another shell produces one alert naming the reader, and your agent never hangs a normal `cat`.

## Mission 2 — Memory regions via `/proc/<pid>/maps`

A region that is both writable and executable (`wx`) is a classic sign of code injection or a packed payload unpacking itself.

- Parse `/proc/<pid>/maps`: each line is `start-end perms offset dev inode path`. Flag entries whose perms contain both `w` and `x`.
- Decide when to check — on every exec is expensive; checking flagged processes is cheaper.
- **Resources:** `man 5 proc` (the `maps` section).
- **Checkpoint:** a toy program that `mmap`s a `wx` page is flagged; normal programs are not (watch your false-positive rate — JITs legitimately use `wx`).

## Mission 3 — Container awareness

On a modern host many processes live in containers. Knowing which one matters for triage.

- A process's namespaces appear as symlinks under `/proc/<pid>/ns/` (e.g. `pid`, `net`, `mnt`); two processes sharing a namespace inode are in the same namespace. Its cgroup is in `/proc/<pid>/cgroup`, which for a container usually encodes the container ID.
- Add a `container` field to your events.
- **Resources:** `man 7 namespaces`, `man 7 cgroups`, `man 5 proc`.
- **Checkpoint:** a process started with `unshare` or inside Docker/Podman is labelled distinctly from host processes.

## Mission 4 — ELF basics (the on-ramp to reverse engineering)

For each flagged binary, read its ELF structure. This is pure Go via the standard library and sets up Phase 2.

- Use `debug/elf` to open the binary and read its machine type, entry point, sections and dynamic symbols (imported libraries and functions).
- **Resources:** `man 5 elf`, the Go `debug/elf` package docs, and the ELF specification (searchable as "ELF-64 Object File Format").
- **Checkpoint:** your agent prints, for a flagged binary, its interpreter and the libraries it imports — and you can explain what "dynamically linked" means.

## How to know Phase 1 is done

The agent reports execs, suspicious paths, ports, file access to sensitive paths, `wx` memory regions and container labels, with no regression in idle CPU or false positives. You can explain, for each feature, which `/proc` file or kernel API it reads.
