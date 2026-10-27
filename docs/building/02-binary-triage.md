# Roadmap Lesson 2 — Binary triage and reverse engineering

> Supports **Phase 2**. Python. Your reverse-engineering foundation: analyse the binaries your agent flags. Guidance and resources only.

## What you are building and why

When the agent flags an unpackaged or suspicious binary, you want a report that says what it is before you open a disassembler. This is both a useful tool and your way into reverse engineering — you learn the ELF format and static-analysis signals by extracting them yourself, then confirm against professional tools.

## Mission 1 — A static triage tool (Python)

Write a command-line tool that takes a path and emits a structured report (JSON) with:

- ELF header facts: class (32/64-bit), machine, type, entry point.
- Sections and segments, their sizes and permissions.
- Imported and exported symbols (what libraries and functions it pulls in).
- Printable strings (URLs, IPs, suspicious command fragments).
- Per-section **entropy**: values near 8.0 bits/byte suggest packing or encryption.

**Libraries to learn:** `pyelftools` (ELF parsing), `capstone` (disassembly), `python-magic` (file typing). Compute entropy yourself with `collections.Counter` and `math.log2` — it is a few lines and teaches the concept.

**Resources:** the `pyelftools` and `capstone` project docs; the ELF-64 specification; "Shannon entropy" for the maths.

**Checkpoint:** run your tool on `/bin/ls` and on one of the payloads your test harness drops; you can explain every field, and the entropy of a `gzip`-compressed blob is visibly higher than that of a normal binary.

## Mission 2 — Disassemble the entry point

Add a disassembly of the bytes at the entry point using `capstone`. You will not understand all of it yet — the goal is to connect "raw bytes in a section" to "instructions a CPU runs".

**Checkpoint:** you can point at the first few instructions of a binary and say roughly what the prologue is doing.

## Mission 3 — Confirm with professional tools

Open the same samples in **Ghidra** (free static analysis and decompiler) and step through one in **GDB with pwndbg** (dynamic). Compare their findings to your tool's report.

**Resources:** Ghidra's built-in help and the official course materials; the pwndbg documentation; any "introduction to Ghidra" walk-through for your first session.

**Checkpoint:** you can take an unknown binary, run your tool, then verify its claims (imports, strings, entropy) inside Ghidra, and describe where your tool is weaker than the disassembler.

## Note on the language boundary

This layer is Python by design (the RE ecosystem lives there). Keep it a separate tool the agent *invokes*, not code inside the Go agent — Phase 3's MCP server is what will let other components call it cleanly.

## How to know Phase 2 is done

Given any binary, your Python tool produces a report you can defend line by line, and you can corroborate it by hand in Ghidra. You understand the ELF layout well enough to explain it at an interview.
