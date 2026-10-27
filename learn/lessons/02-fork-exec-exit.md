# Lesson 2 — fork, exec, and the exec race

> For **F1**. Explains how a program starts, and the race condition at the heart of the project.

## How a program is launched

When a shell runs `ls`, two system calls happen in sequence:

1. **`fork`** (technically `clone` on Linux): the kernel makes a copy of the shell process. Now there are two nearly identical processes — the parent (shell) and a child with a new PID.
2. **`execve`**: the child replaces its own memory image with the `ls` binary. Same PID, but now it *is* `ls`. When `ls` finishes it calls **`exit`**, and the kernel notifies the parent.

You can watch this directly:

```bash
strace -f -e trace=clone,execve,exit_group bash -c 'ls'
```

The key insight: **`execve` is the moment a new program starts running.** That is the single event your agent cares about for F1. Every command, script, daemon, and yes every piece of malware, begins with an `execve`.

## PID vs TGID (threads)

A process can have several **threads**, which the kernel treats as tasks sharing one PID space. The number that identifies the whole process is the **TGID** (thread group ID); it equals the PID of the main thread. When the proc connector (lesson 3) reports an event it gives you both a PID and a TGID — for F1 you want the **TGID**, because that is what `/proc/<tgid>` is keyed on and what a human calls "the process".

## The exec race

Here is the problem. The sequence for a short command is:

```
kernel: execve happens  →  kernel sends you an event  →  you read /proc/<pid>
                                                          ↑
                         the process may have already exited here
```

For `ls`, the whole program runs and exits in under a millisecond. By the time your agent receives the event and opens `/proc/<pid>/exe`, the directory may already be gone. You get empty fields — you will see this the moment your minimal watcher ([quick start](../quickstart.md#4-your-first-milestone-a-minimal-process-watcher)) runs: some executions arrive with no binary path.

This is a genuine, unavoidable **race condition**: two things happen concurrently (the process running, your agent reading) and you cannot control the order. You cannot eliminate it from user space in pure Go. What you can do:

- **Read `/proc` as fast as possible** after the event, before doing anything else.
- **Always emit the `EXEC` event anyway**, with whatever fields you managed to read (the interface contract requires this). An event with an empty `exe` is still information: something ran and vanished instantly, which is itself mildly suspicious.
- **Count how often it happens** and report it. Explaining this trade-off at the demo is worth real marks.

A production tool (Falco, Tetragon) avoids the race by capturing the binary path *inside the kernel* at `execve` time using eBPF. That needs C, so it is out of scope here — but knowing *why* those tools exist is exactly the kind of understanding the oral rewards.

## Check yourself

- Why can't you just "read `/proc` a bit later" to fix the race? *(The process is already gone; later is worse, not better.)*
- A process shows `exe` = empty but a valid `cmdline`. How is that possible? *(Different files, read microseconds apart; one succeeded, one didn't.)*
- Which identifier do you store as `pid` in your alert, and why the TGID?
