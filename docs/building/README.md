# 📚 Build guides

Guided lessons for the [learning roadmap](../../learn/skill-roadmap.md) — the phases that extend Sylvy into a full Linux security-engineering skill set. Like the [internals lessons](../../learn/lessons/), these give you the concept, the missions, the exact tools and resources, and checkpoints. **No solutions**: you design and build each feature.

1. [Deepen the Linux agent](01-deepen-the-agent.md) — fanotify, `/proc/<pid>/maps`, namespaces/cgroups, ELF *(Phase 1, Go)*
2. [Binary triage and reverse engineering](02-binary-triage.md) — ELF, static analysis, Ghidra, GDB *(Phase 2, Python)*
3. [The MCP server](03-mcp-server.md) — expose the host as tools over the official Go MCP SDK *(Phase 3, Go)*
4. [Network protocols](04-network-protocols.md) — packet, DNS and TLS parsing *(Phase 4, Go)*
5. [AI/ML triage layer](05-ai-ml-triage.md) — local-model triage, retrieval, evaluation, classical ML *(Phase 5, Python)*
6. [Vulnerability research bridge](06-vulnerability-research.md) — patch analysis, exploit primitives, detection duality *(Phase 6, study track)*
7. [Agent containment and the capability model](08-agent-containment.md) — microVM isolation, the host-daemon gate, withholding `/dev/kvm`, binding actions to identity *(Phase 8, Go + hypervisor + eBPF)*
8. [Workload identity and agent provenance](09-workload-identity.md) — attested identity on SPIRE, federation, the guest-can't-become-host invariant, simple policy *(Phase 9)*

**Before you trust any of the containment/identity work:** 🔎 [Prove it's simple and secure](../security-self-audit.md) — a self-audit built from the design questions, split into *secure* (can it be bypassed?) and *simple* (will anyone operate it?).

Back to the [roadmap](../roadmap.md) · [Sylvy overview](../../README.md) · [internals lessons](../../learn/lessons/).
