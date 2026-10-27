# Lesson 1 — Processes and `/proc`

> For **F1**. Read this first. By the end you can read any process's identity from Go — code you write yourself, guided here.

## What a process is

A **process** is a running program: the kernel loads a binary from disk into memory and gives it a slot to execute. Each process has a numeric identity the kernel assigns and tracks:

- **PID** (process ID): a unique number for this process.
- **PPID** (parent PID): the PID of the process that started it. Processes form a tree; at the root is PID 1 (your init system).
- **UID** (user ID): the user the process runs as. `0` is root; regular users are 1000 and up; `65534` is `nobody`, a deliberately powerless user.

The kernel keeps all of this in an internal C structure called `task_struct`. You never touch that structure directly — instead the kernel exposes it through a virtual filesystem.

## The `/proc` filesystem

`/proc` looks like a directory of files, but nothing is on disk. Every time you read a file under `/proc`, the kernel generates its contents on the fly from `task_struct`. There is one directory per process, named after its PID. Explore it by hand first:

```bash
ls /proc/self/              # "self" is a shortcut to the process doing the reading
cat /proc/self/status       # identity: Name, PPid, Uid, memory...
readlink /proc/self/exe     # absolute path of the running binary
cat /proc/self/cmdline | tr '\0' ' '   # the command line, NUL-separated
```

Three files matter for F1 — learn their exact shape, because you will parse them:

- **`/proc/<pid>/exe`** is a symbolic link to the binary the kernel actually loaded. Reading the link (not the file) gives the absolute path. This is the ground truth: even if the process was started through a confusing name, `exe` points at the real file ([lesson 4](04-path-attacks.md) abuses exactly this). For a deleted binary the kernel appends ` (deleted)`; for an in-memory one it reads `/memfd:...`.
- **`/proc/<pid>/cmdline`** holds the arguments (`argv`) separated by **NUL bytes** (`\0`), not spaces. If you print it raw it looks like the arguments are glued together.
- **`/proc/<pid>/status`** is human-readable text with one `key:\tvalue` per line. The lines you want are `PPid:\t1234` and `Uid:\treal\teffective\tsaved\tfs` — take the **first** (real) UID.

## How to read these from Go

You need no special library — these are ordinary files and symlinks. Map each file to a standard-library call and parse the shape above yourself:

- `os.Readlink` on `/proc/<pid>/exe` for the binary path.
- `os.ReadFile` on `/proc/<pid>/cmdline`, then split on the NUL byte (`\x00`) and rejoin with spaces.
- `os.ReadFile` on `/proc/<pid>/status`, scan line by line (`strings.Split` on `\n`, then `strings.Fields`), and pick out the `PPid:` and `Uid:` lines. `strconv.Atoi` turns the numbers into ints.

Write a single helper that takes a PID and returns a small struct with `Exe`, `Cmdline`, `PPID`, `UID`. You will call it for every event in F1.

**Documentation to lean on:** `man 5 proc` is the authoritative reference for every field under `/proc`; the Go standard library docs for `os`, `strings` and `strconv` cover every call above.

## The catch

`/proc/<pid>` exists only while the process is alive. If the process exits before you read it, `Readlink` and `ReadFile` return an error and you get empty fields. That is not a bug in your code — it is the exec race, and [lesson 2](02-fork-exec-exit.md) is entirely about it. Design your helper to return partial data gracefully rather than failing.

## Check yourself

- Why does `cat /proc/self/cmdline` look like it has no spaces? *(Arguments are separated by NUL, which the terminal does not show.)*
- What does `/proc/1/exe` point to, and why does reading it need root?
- Run `sleep 100 &` then `readlink /proc/$!/exe`. Try the same after the sleep finishes — what changes, and what does your helper return then?
