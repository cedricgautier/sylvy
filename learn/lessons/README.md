# 📚 Lessons

Everything you need to know for Sylvy, taught from scratch and in order. Read each one as you reach the matching requirement — they are short (one page each). They **guide you to write the code yourself**: the concept, a hands-on part, the exact APIs and man pages, and checkpoints. No solutions.

1. [Processes and `/proc`](01-processes-and-proc.md) — what a process is, PID/PPID/UID, the `/proc` filesystem *(F1)*
2. [fork, exec and the exec race](02-fork-exec-exit.md) — how a program starts, and the race condition at the core of the project *(F1)*
3. [Netlink and the proc connector](03-netlink-proc-connector.md) — how the kernel pushes events to you *(F1)*
4. [Attack techniques on the binary path](04-path-attacks.md) — `/tmp`, deleted binaries, memfd, masquerading *(F2)*
5. [Sockets, ports and `/proc/net`](05-sockets-and-ports.md) — listening ports and matching a socket to its process *(F3)*
6. [Privilege, root and capabilities](06-privilege-and-capabilities.md) — why the agent needs root, and how to keep it honest *(oral)*

Back to the [internals course](../README.md) · [quick start](../quickstart.md) · [test plan](../test-plan.md).
