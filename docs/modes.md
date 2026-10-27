# 🔭🛡️ The two modes: Observe and Enforce

> How the product is deployed and adopted. Companion to the [roadmap](roadmap.md) and the [Sylvy overview](../README.md).

The system ships in two modes. **Observe** is the default and the entry point: read-only, no privileges, see and prove what agents did. **Enforce** is opt-in and built on top: contain, gate, and block. This mirrors how mature security tooling is adopted (Kyverno, OPA Gatekeeper, most admission control): customers run in audit first, build confidence, then switch on enforcement. It also keeps your own component's privileges minimal until the customer explicitly asks for more.

## Observe mode (default)

**Promise:** "See everything your agents do, attributed to a cryptographic identity, and prove it — without touching the kernel or granting privileges."

- **What it does:** consumes the node's existing event stream, joins each action to an identity, rebuilds lineage, stores a queryable, auditable provenance trail.
- **Strengthens detection (downstream benefit):** because each action carries an attested identity, the trail is an identity-enriched signal for the detection stack teams already run — an anomaly becomes "*this agent instance* did X, outside its baseline," and after a hijack the trail answers "what did the compromised workload do, and as whom." Observe does not *replace* threat detection; it makes it attributable.
- **Privileges:** read-only. No `CAP_BPF`, no privileged pod, read-only root filesystem, all capabilities dropped. It can run as an unprivileged workload.
- **What it reads (only reads):**
  - Tetragon's event stream (local gRPC socket or exported log), mounted read-only.
  - The Kubernetes API, watch-only (to map container → pod → workload).
  - SPIRE registration / SPIFFE IDs already present, to attach identity.
- **Identity source:** whatever already exists. With SPIRE's Kubernetes attestor that is **per-pod** granularity (namespace, service account, pod). Finer per-agent-instance identity in this mode depends on the agent framework registering each task — weaker, because it relies on the application cooperating.
- **What it does NOT do:** it does not gate spawns, contain anything, or block actions. It detects and proves **after the fact**; it does not prevent.
- **Why lead with it:** installs in minutes, nothing privileged to vet, immediate value ("what did agent X do, provably"). It is the easy adoption wedge and the low-attack-surface default.

## Enforce mode (opt-in)

**Promise:** "Now stop it. No identity, no run; contained in a boundary it can't escape; disallowed actions blocked in real time."

- **What it adds:**
  - the **spawn gate** — every agent launches through the host daemon; no identity, no run;
  - **containment** — agents launched in a microVM or gVisor with capabilities withheld (no `/dev/kvm`, nested virt off; see [containment lesson](building/08-agent-containment.md));
  - **per-agent-instance identity** issued at spawn, with lineage (not just per-pod);
  - **fail-closed** — a VM whose in-guest sensor goes silent, or whose boundary traffic doesn't match its reported events, is killed;
  - **real-time blocking** of disallowed actions.
- **Privileges:** higher, by necessity — the gate and launch path need host-level control on the nodes where it runs.

### Enforcement is delegated, not reimplemented

Your component stays the **brain**, not the muscle. It generates policy for enforcers that already exist, so you add as little privileged code of your own as possible:

- **Tetragon** tracing policies — kill a process or block a syscall.
- **Network policy** (the cluster's existing CNI via Kubernetes NetworkPolicy, or Cilium if present) — block or constrain connections.
- **An admission controller** (Kyverno / Gatekeeper) — force agent pods onto a sandboxed RuntimeClass, or refuse pods with no identity.
- **Your host daemon** — the spawn gate and the microVM launch path, the one piece that must act directly.

This matters for two reasons: **security** (a privileged daemon is itself a target; the less power yours holds, the less damage if it's compromised) and **adoption** (security teams resist installing yet another privileged daemon on every node — delegating to tools they already trust lowers that barrier).

## Moving from Observe to Enforce

The path is deliberate and reversible, which is the point:

1. Run **Observe** for a while. Watch the provenance trail; see what agents actually do.
2. Write policy against what you've observed. The system can **suggest** rules from observed behaviour (what each agent normally does → a candidate allow-list).
3. Turn on Enforce in **dry-run / audit**: the enforcers log what they *would* block, nothing is stopped. Compare against reality; tune out false positives.
4. Flip specific policies to **active**, starting with the safest, default-deny on the rest.

A customer can stay in Observe forever (an audit/compliance tool), or progress to Enforce (a containment platform). Same product, same identity and provenance core — Enforce just adds the acting layers on top of the observing ones.

## One honest trade-off to state plainly

Observe mode's identity is only as fine-grained as what already exists (per-pod with SPIRE's K8s attestor). **True per-agent-instance identity, lineage from the moment of spawn, and containment require Enforce mode**, because they require owning the spawn. So Observe answers "what did this *pod's* agents do," and Enforce sharpens it to "what did *this agent instance and its children* do, and it couldn't have done otherwise." Don't let Observe's ease imply Enforce's guarantees — they're different promises, and the roadmap builds them in that order.
