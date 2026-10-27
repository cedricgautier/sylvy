# 📖 Study notes: the Linux kernel

> Personal study notes on what the kernel is, where it came from, and why the whole project depends on it. Written in my own words, then fact-checked and corrected. Companion to the base [lessons](lessons/) and the [architecture](../docs/architecture.md).

> **How to read this:** the ✅ notes are what I had right; the ⚠️ notes are corrections to what I first wrote, kept visible on purpose so I remember the distinction.

## What the kernel is

The kernel is the software that **binds actionable software to the hardware**. It's the core that controls all actions — the king of the system, the top of the tree. It holds the **highest authorization** in the system and runs in its **own space, separated from user space** where applications run.

The reason for that separation is enforced by the CPU itself: the processor has privilege levels (rings). The kernel runs in the most privileged level (kernel mode, ring 0) where it can touch any hardware; applications run in user mode (ring 3) where the dangerous instructions are forbidden. The boundary is a **hardware wall**, not a convention — which is exactly why kernel-level enforcement can't be bypassed by a program in user space.

## Syscalls: the one doorway

A program can't touch hardware itself. The only way across the wall is a **system call** (syscall). Calls like `open`, `read`, `write`, `execve` (run a program), `connect` (open a network connection), and `fork`/`clone` (make a new process) are all syscalls — every one of them is the program **asking the kernel** to do something on its behalf.

> ⚠️ **Correction:** these are *system calls*, not "commands." A command is a shell thing like `ls`; `ls` is a program that *makes* syscalls. The syscall is the programmatic request to the kernel underneath.

Because a program can do **nothing** meaningful without a syscall, the kernel sees every action. That's why **kernel logging is the source of truth, better than an application log**: the application can lie about what it did; it cannot avoid making the syscall, and it can't reach across the wall to tamper with the kernel's record.

## History: where it came from

> ⚠️ **Corrections folded in:** I had the people and the machine slightly tangled.

Unix began at Bell Labs around 1969, started primarily by **Ken Thompson**, with **Dennis Ritchie** as co-creator. The **DEC PDP-7** was the *computer they wrote it on*, not a thing they wrote. The original Unix was written in **assembly**.

Unix became popular because of its philosophy, especially **"everything is a file"** — devices, pipes, hardware, and kernel data are all reached through the same file interface. (`/proc`, which this project reads constantly, is the kernel exposing its own internals as virtual files.)

They wanted Unix to run on different hardware, not just one machine. That portability need is why **Dennis Ritchie invented the C language** (~1972) and they rewrote the Unix kernel in C — moving *away* from assembly. **This is why kernels are still written in C today.**

Unix spread through companies and universities for two decades. Then in 1991 **Linus Torvalds**, wanting something he could run affordably on his own PC, wrote his own kernel: **Linux**.

> ⚠️ **Correction:** Torvalds is the *creator of Linux*, not usually called "the godfather" — that title fits Thompson/Ritchie (fathers of Unix) or Richard Stallman (free software). Torvalds combined his kernel with the **GNU** user-space tools (Stallman's project), which is why the full system is sometimes called GNU/Linux. Its open license is why it spread everywhere — today it runs most servers, all Android phones, the cloud, and every Kubernetes node, container, and microVM in this project.

## The main jobs of the kernel

### Process scheduling
The **scheduler** decides which process runs on which core and for how long. Good intuition: it's like a load balancer, relieving and assigning work.

> ⚠️ **Correction:** it manages **all cores at once**, and modern machines run truly in parallel — one process per core *simultaneously*. The trick is rapid time-slicing: it switches between many processes on each core thousands of times a second, so it *looks* like everything runs at once. (This is where PID, process state, and the kernel's `task_struct` record — read via `/proc` — live.)

### Memory management
Memory is handled through **maps**: when a process needs memory, the kernel allocates it and maps the process's **virtual** addresses to real physical RAM. Each process gets its own private address space, so one process **cannot read another's memory** — clean segregation enforced by the kernel and the hardware MMU.

> ⚠️ **Correction (my one real mistake):** failed isolation would **not** be "a memory leak." Isolation and leaks are unrelated. Broken isolation = a **security breach** (one process reading another's secrets) or a crash. A **memory leak** = memory allocated and never freed. The leak point belongs to *kernel code specifically*: a leak inside the kernel is unrecoverable, because nothing above the kernel cleans up after it — which is part of why kernel programming is so unforgiving.

### Filesystem (VFS)
The **Virtual File System** is a translator: it lets `open`/`read`/`write` work the same way over any storage — hard disk, SSD, RAM, network share. All of it appears in one uniform tree, from devices to kernel data. (`/proc` is a *virtual* filesystem the kernel generates on the fly, not real files on disk.)

### Networking
The kernel implements the **entire network stack** — routing, TCP, IP, the sockets API. It talks to the network card (through its driver): building packets, handling flow and ordering, tracking which ports are listening and which connections exist. (`/proc/net/tcp`, which the base project's port scanner reads, is the kernel exposing its own connection table.)

### Device drivers
**Drivers** let the kernel communicate with **devices** (the hardware) — each device speaks its own low-level language, and the driver translates between it and the kernel's uniform interfaces. Drivers are the majority of kernel code by volume and the most bug-prone, because real hardware is messy.

> ⚠️ **Correction:** drivers let the kernel talk to *devices*, not "to other drivers," and they are written overwhelmingly in **C** — only tiny, hardware-forced fragments are assembly.

## Why the kernel is hard, and why few work there

- **No safety net.** A bad pointer in user space kills just your program (a segfault). In the kernel there's no one above to catch the fall — it's a **kernel panic**, the whole machine halts. You can't crash a little.
- **No normal tools.** No standard C library, manual memory (a leak is forever), hard-to-attach debuggers, tiny stacks, code paths that can't sleep or allocate.
- **Brutal concurrency.** Many cores enter the kernel at once; your code can be interrupted almost anywhere. Protecting shared data is one of the hardest problems in programming, and getting it wrong gives rare, unreproducible crashes.
- **Maximal stakes.** A kernel bug isn't just a crash, it's a hole in the most privileged code on the machine — total compromise. So the bar is extreme and the pace conservative.

This is why the learning curve is years, the feedback loop is slow and painful, and the people who do it well are rare — which is exactly why these skills are valuable.

## Why eBPF matters

Historically, running your own code in the kernel meant writing a **kernel module** — full lethality: a bug crashes the machine, a flaw is a root exploit. **eBPF** changed this: you load small programs that a **verifier inside the kernel proves safe before they run** (no infinite loops, no illegal memory access, no crashing the system). So you get to observe and act *inside* the kernel with much of user space's safety. That's why Tetragon, Falco, and Cilium are built on eBPF rather than kernel modules, and why this project's observation layer stands on it.

## How kernel-level logging works

- **The kernel's own log:** an internal ring buffer (`printk` → read with `dmesg` → the journal) where the kernel reports hardware events, driver init, warnings, errors — the kernel talking about itself.
- **Event logging (what matters here):** because every program must cross into the kernel via syscalls, the kernel is the one place that sees all behavior truthfully. Mechanisms, oldest to newest: the **audit subsystem** (rule-based syscall records, consumed by `auditd`), **tracepoints/kprobes** (stable and dynamic instrumentation points inside the kernel), and **eBPF on top of them** (a verified program runs in-kernel the instant an event fires, captures full context, and streams it out efficiently — what Tetragon does).

**Why it's trustworthy — the whole basis of the project's security model:** the hardware wall between user and kernel space means a program **cannot observe itself from outside, cannot avoid the syscall boundary, and cannot reach into the kernel to tamper with the log.** Application logging is a program describing its own behavior (which a compromised program will lie about). Kernel logging is an independent, more-privileged observer watching from the other side of a silicon wall, recording what the program *actually asked the hardware to do*. Observer more privileged than the observed, separated by hardware — that asymmetry is why "observe from the kernel, never trust the workload to report on itself" is sound.
