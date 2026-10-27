# 🧗 Sylvy learning roadmap (Linux track)

> A staged path that grows your Linux security-engineering skill set. For the **product** direction specifically — what to build yourself to learn versus what to integrate to ship — see the [build-to-ship roadmap](../docs/roadmap.md). Each phase has a **guided lesson** (linked under its heading) with missions, tools, resources and checkpoints — no solutions. Each phase is self-contained: finish it, feel confident, then climb to the next. **Go** for the agent and the MCP server; **Python** for everything AI/ML; a **local Llama via Ollama** so nothing leaves your machine.

## The shape of the system

```
  ┌────────────────────┐   JSON events        ┌─────────────────────────┐
  │  Sylvy agent     │ ───────────────────▶ │  Sylvy MCP server    │
  │  (Go, pure)         │   triage on demand   │  (Go, official MCP SDK) │
  └────────────────────┘                       └───────────┬─────────────┘
         watches the kernel                      exposes tools │ (MCP)
                                                               ▼
                                                 ┌─────────────────────────┐
                                                 │  AI/ML layer (Python)    │
                                                 │  local Llama via Ollama  │
                                                 │  triage · ML · eval      │
                                                 └─────────────────────────┘
```

The agent knows the kernel. The MCP server turns "what is happening on this host" into tools an LLM or a script can call. The Python layer does the reasoning and the machine learning. This mirrors how real security tooling is built: a fast systems collector, a stable interface, and a research layer on top.

## Skill coverage at a glance

| Job requirement | Where you build it |
|-----------------|--------------------|
| Linux OS internals | Phases 0–1, 3 |
| Network protocols | Phase 4 |
| Reverse engineering tools & techniques | Phase 2 |
| Vulnerability research (patch analysis, exploit primitives) | Phase 6 (+ outside study) |
| Python software development | Phases 2, 5 |
| GenAI/LLM workflows | Phase 5 |
| Information security breadth | Phase 7, woven throughout |
| Isolation / sandboxing / hypervisor | Phase 8 |
| Workload identity, attestation, distributed trust | Phase 9 |

---

## Phase 0 — The base agent *(done)*

The project as it stands: process events via the proc connector, suspicious paths, listening ports, JSON output, pure Go. Finish this first and pass the [test suite](test-plan.md). Everything below assumes it works.

**Ready when:** `sylvy-test.sh` is green and you can explain an `exec`'s journey end to end.

## Phase 1 — Deepen the Linux agent *(Go · internals)*

> 📖 Guided lesson: [Deepen the Linux agent](../docs/building/01-deepen-the-agent.md)

Push the agent from "watches execs" to "understands the system," the way an EDR does.

- **File activity** with fanotify (`FAN_OPEN_EXEC`, `FAN_OPEN_PERM`): see who reads `/etc/shadow` or SSH keys. Teaches the VFS and permission events.
- **Memory layout**: read `/proc/<pid>/maps` and flag writable-and-executable regions (a classic injection signal). Teaches process memory and ELF loading.
- **Container awareness**: resolve a process's namespaces and cgroup so you know which container it belongs to. Teaches namespaces and cgroups, the backbone of modern Linux isolation.
- **ELF basics in Go**: parse the header of each flagged binary with `debug/elf` (standard library) — entry point, sections, dynamic symbols. This is the on-ramp to Phase 2.

**Learn:** VFS, process memory, namespaces/cgroups, ELF structure.
**Resources:** *The Linux Programming Interface* (Kerrisk), `man 7 fanotify`, `man 5 proc`, `man 5 elf`.
**Ready when:** the agent reports file access to a sensitive path and labels each event with its container, with no new false positives.

## Phase 2 — Binary triage *(Python · reverse engineering)*

> 📖 Guided lesson: [Binary triage and reverse engineering](../docs/building/02-binary-triage.md)

When the agent flags an unpackaged or suspicious binary, analyse it. This is your reverse-engineering foundation and your first serious Python.

- A Python tool that ingests a binary path and emits a structured report: ELF headers and sections (`pyelftools`), imported/exported symbols, printable strings, section entropy (packed/encrypted binaries have high entropy), and a disassembly of the entry point (`capstone`).
- Then go manual: open the same samples your test harness drops into Ghidra (free, static) and GDB/`pwndbg` (dynamic). Compare what your tool found against what the disassembler shows.

**Learn:** ELF in depth, static vs dynamic analysis, disassembly, packing/obfuscation signals.
**Tools:** `pyelftools`, `capstone`, `python-magic`, Ghidra, GDB + `pwndbg`.
**Ready when:** given an unknown binary, your tool produces a report you can defend, and you can confirm its findings by hand in Ghidra.

## Phase 3 — The MCP server *(Go · internals + service design)*

> 📖 Guided lesson: [The MCP server](../docs/building/03-mcp-server.md)

Wrap the agent and the triage data in a Model Context Protocol server, so an LLM or a script can *ask* the host questions. This is the keystone that connects the systems half to the AI half.

- Use the **official Go SDK**: `github.com/modelcontextprotocol/go-sdk/mcp` (maintained with Google; pre-1.0, so pin an exact version and read the release notes before upgrading).
- Expose tools such as: `list_recent_events`, `get_process(pid)`, `list_listening_ports`, `triage_binary(path)` (shelling out to the Phase 2 tool), `baseline_diff`.
- Start over stdio (`mcp.StdioTransport`), then add an HTTP transport so the Python layer and Claude Desktop can both connect.

**Learn:** MCP (tools, resources, transports), Go service and API design, safe boundaries (the server decides what is exposed, never runs arbitrary input).
**Resources:** the SDK `docs/` directory and `modelcontextprotocol.io`.
**Ready when:** you can connect a client, call `triage_binary` on a dropped payload, and get a structured result back over MCP.

## Phase 4 — Network protocols *(Go · protocols)*

> 📖 Guided lesson: [Network protocols](../docs/building/04-network-protocols.md)

Give the agent eyes on the network and learn protocols at the byte level.

- Capture connection metadata with an `AF_PACKET` socket (or start by parsing `/proc/net/tcp` connection states you already read) and decode packet headers in Go: Ethernet → IP → TCP/UDP.
- Parse two application protocols by hand: a DNS query (to catch exfiltration-by-DNS) and a TLS `ClientHello` (the SNI reveals the destination even when the payload is encrypted).
- Expose a `recent_connections` tool on the MCP server.

**Learn:** TCP/IP structure, DNS, the TLS handshake, packet parsing.
**Tools:** Go `gopacket` (or hand-rolled parsers for the learning), Wireshark to check your work.
**Ready when:** your agent logs outbound connections with resolved domains, and you can read a captured handshake in Wireshark and explain each field.

## Phase 5 — AI/ML triage layer *(Python · GenAI + data analysis)*

> 📖 Guided lesson: [AI/ML triage layer](../docs/building/05-ai-ml-triage.md)

Now the differentiator. A Python service that consumes your MCP server and reasons about what it finds, entirely offline.

- **LLM-assisted triage**: for each alert, call `triage_binary` via MCP, feed the report to a **local Llama through Ollama**, and get back a plain-language risk summary plus a suggested MITRE ATT&CK technique ID, as **structured JSON** (constrained decoding or a strict schema prompt).
- **Retrieval**: build a small corpus of known-indicator notes and ATT&CK descriptions; retrieve the relevant ones before asking the model, so answers are grounded rather than guessed.
- **An eval harness**: run the pipeline over your test harness's labelled scenarios (benign vs malicious) and measure precision/false-positive rate. This is the part that turns "I used an LLM" into "I evaluated an LLM workflow," which is what the job asks for.
- **A pinch of classical ML**: train a simple anomaly model (e.g. isolation forest with `scikit-learn`) on the baseline of normal process behaviour, as a non-LLM second opinion. Teaches the data-analysis side.

**Learn:** LLM tool-use workflows, structured output, retrieval, evaluation, basic ML, Python packaging.
**Tools:** `mcp` (Python SDK) as the MCP client, Ollama + Llama, `scikit-learn`, `pydantic` for schemas.
**Ready when:** an alert flows end to end — agent → MCP → Python → local model → graded risk report — and you have a measured false-positive number you can quote.

## Phase 6 — Vulnerability research bridge *(mixed · the hardest bullet)*

> 📖 Guided lesson: [Vulnerability research bridge](../docs/building/06-vulnerability-research.md)

This is the most specialised area and the one you mostly earn *outside* the project, but Sylvy gives you realistic targets and a defender's intuition.

- **Patch analysis**: pick a Linux CVE, diff the vulnerable and patched source, and write up what the fix closed and how the bug was reachable.
- **Exploit primitives**: work a structured course (pwn.college, or *Nightmare* for heap) on a throwaway VM. Build the muscle on deliberately vulnerable binaries, not production.
- **Tie back**: write detections in Sylvy for the *runtime* symptoms of the exploits you study (a service spawning a shell, an unexpected `memfd` payload, a new listening port). Defender and attacker views reinforcing each other is exactly the maturity interviewers probe.

**Learn:** patch diffing, memory-corruption primitives, exploit/detection duality.
**Ready when:** you can take one CVE from patch diff to a working proof-of-concept on a lab VM, and name how your agent would (or would not) have seen it.

## Phase 7 — Make it a portfolio *(security breadth)*

Experience is years, not a weekend — but presentation turns work into evidence.

- A **threat model** of the agent itself (extend [lesson 6](lessons/06-privilege-and-capabilities.md)): what attacks the monitor, and your defences.
- **ATT&CK mapping**: tag every detection with its technique ID.
- An **evasion write-up**: honest blind spots and how an attacker would slip past, with proposed fixes.
- A clean repo, a short architecture doc, and a recorded demo.

**Ready when:** a stranger can read the repo and understand both what it detects and what it deliberately doesn't.

## Phase 8 — Agent containment and the capability model *(Go + hypervisor + eBPF)*

> 📖 Guided lesson: [Agent containment and the capability model](../docs/building/08-agent-containment.md) · 🔎 [Prove it's simple and secure](../docs/security-self-audit.md)

The leap from watching agents to *containing* them. Each agent runs inside a real isolation boundary (microVM or gVisor) it cannot escape or widen; a **host-side** daemon is the only path to spawn one and attaches identity at launch; every action is bound to that identity by eBPF, and anything that ran without going through the daemon is flagged. Central security property: **enforcement lives where the agent cannot execute code against it** — the hypervisor and the kernel, never inside the guest. Includes the capability model (which powers are withheld at the hypervisor vs governed by the identity/eBPF layer) and the hardware-backed control that a guest cannot create a nested VM, proven from inside every guest.

## Phase 9 — Workload identity and agent provenance *(Go + SPIRE, Python optional)*

> 📖 Guided lesson: [Workload identity and agent provenance](../docs/building/09-workload-identity.md) · 🔎 [Prove it's simple and secure](../docs/security-self-audit.md)

The hardest, most valuable layer, and the one that is genuinely distributed systems. A verifiable, short-lived identity for every agent, **issued downward from the launcher and rooted in attestation** so a workload can't forge it. Actions and lineage bind to that identity; identities verify across clusters by **federation** (separate trust domains, not one flat domain); a guest **can never acquire issuing power** (the key and attestor live outside every guest); and authorization stays **simple** for the DevSecOps engineer (identity and policy separated, a few readable lines to authorize an interaction). Build issuance on **SPIFFE/SPIRE** (mature — wrap it); own only the thin agent-identity layer and the policy surface (unsettled research — keep it swappable).

---

## Honest sequencing and effort

Phases 0–5 are the coherent, buildable spine and are realistic over a few focused months; each one leaves you with something that works and something you can talk about. Phase 6 is a longer, separate study track that will take as long as the rest combined — treat it as ongoing, not a sprint. Phase 7 is light but do it continuously, not at the end. Phases 8 and 9 are the frontier — the containment and identity work this project builds toward; they are larger and harder than everything before, genuinely distributed-systems territory, and the place to go only once the base agent and at least the eBPF port (Phase 1) are solid. Before trusting anything you build there, run the [self-audit](../docs/security-self-audit.md).

If you want the fastest jump in hireability for this specific profile: do Phase 3 (MCP server) and Phase 5 (AI/ML triage) right after the base, because the GenAI-for-security bullet is the rarest and you already have the Python and local-model pieces lined up. Internals (Phase 1) and protocols (Phase 4) deepen the backbone next. Reverse engineering (Phase 2) and vuln research (Phase 6) are the long game, and Sylvy's own payloads are your practice range.

**One caution:** keep the agent pure-Go and the AI layer pure-Python with the MCP server as the only bridge between them. The temptation will be to let Python reach into the kernel or to embed ML in the Go agent — resist it. The clean seam *is* the lesson: a fast systems collector, a stable protocol boundary, and a research layer that can evolve independently.
