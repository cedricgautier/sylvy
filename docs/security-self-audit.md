# 🔎 Prove it's simple and secure — the questions to ask yourself

> A self-audit for the containment + identity work ([Phase 8](building/08-agent-containment.md), [Phase 9](building/09-workload-identity.md)). These are the questions worked through while designing this system — reframed as tests. If you can answer each one *concretely* (a mechanism, not a hope), the design holds. If an answer is "the agent is trusted not to…", you have attribution, not security — go fix it before building more.

The split matters: some questions test whether the thing is **secure** (can it be bypassed?), others whether it's **simple** (will anyone actually operate it?). Both have to pass.

## Scope and honesty (before you build)

- **Does this teach / cover something real, or am I reimplementing a solved product?** Name the mature tools you wrap (microVM, SPIRE, OPA/OpenFGA) and the thin layer you actually own. If you can't name what's *yours*, you're rebuilding incumbents.
- **Who feels this pain — and is it the laptop user or the fleet operator?** If the honest answer is "an org running agents on infrastructure," lead with the server/Kubernetes tier and treat the laptop as the demo. Don't size the market by the niche that feels nearest.
- **What does a big incumbent (e.g. an EDR vendor) already do here, and at which layer?** If they own the governance/gateway layer and you own the kernel/hypervisor containment layer, say so — different layers are a position, not a loss.

## Containment — is the boundary real? (secure)

- **Is every enforcement control in a place the agent cannot execute code against?** Hypervisor (outside the guest) or kernel (beneath the process). If any control lives *inside* the guest and judges the guest, it's removable — rewrite it.
- **Is the spawning daemon on the host, not inside the VM?** A guard the guarded party can delete is not a guard. The host decides "shut down if not legitimate" *about* the guest, from outside.
- **Can I prove, from inside a spawned guest, that it cannot create a nested VM?** `ls /dev/kvm` is absent, `grep -E 'vmx|svm' /proc/cpuinfo` is empty, and an actual nested launch fails at KVM acquisition. Is this a continuous test, or a flag I set once and hope held?
- **Have I separated "can't make a VM" from "can't make a process"?** Nested-virt withholding closes the VM door only; process spawning is governed by the identity + eBPF layer. Which door am I actually trying to close, and with which lock?
- **Does anything that runs without going through the daemon get caught?** The host daemon is the gate; eBPF is the alarm when someone climbs the fence. Is the alarm wired?

## Identity — is it unforgeable and un-escalatable? (secure)

- **Does identity flow *down* from the launcher, or *up* from the workload?** If the workload can claim its own identity, it can lie. The host attests what it launched; the agent presents, never mints.
- **If a guest tampers with its own credential, does it gain anything?** It must not — the forged credential fails verification because the signing key was never in the guest. Confirm the key is host-side (ideally hardware-backed).
- **Can a guest acquire the power to *issue* identity?** This is the catastrophic one. The attestor and signing key live outside every guest; a guest that spawns children *requests* issuance upward and never holds the key. Can I point to exactly where that power lives and why guest code can't reach it?
- **Is my spawn graph a finite tree rooted in a trust anchor, or an unanchored loop?** Verification must walk up to a root and stop. Peers verify against shared/federated roots, not each other.
- **Across clusters, am I federating separate trust domains, or running one flat domain?** One flat domain = one compromise is a fleet-wide skeleton key. Federate; keep attestation independent per domain.
- **Does a sub-guest talk only to its immediate parent, over a parent-controlled channel?** If the deepest guest needs a direct line to the root host, the hierarchy is modelled wrong.
- **Do I actually need nested *isolation* here, or just nested *identity*?** The identity tree can be deeper than the isolation tree. Don't pay the nested-virt tax to attribute a sub-agent that a process-with-its-own-identity would cover.

## Simplicity — will a DevSecOps engineer actually run it? (simple)

- **Can someone authorize a new agent-to-service interaction in a few readable lines — no certs, no IPs, no redeploy?** If authorizing requires touching certificates, identity and policy are tangled. Separate them (mTLS proves *who*; policy decides *may you*).
- **Are identities issued automatically from attestation, or provisioned by hand?** Hand-provisioning doesn't scale and invites long-lived secrets.
- **Is the default deny, with a short allow-list?** Default-allow is theater.
- **Does the same policy artifact read the same on a laptop and on a federated fleet?** One mental model, compiled down — or three different systems to learn?

## The one question under all the others

- **For every "the agent can't do X" in my design, is X *impossible to reach* or merely *forbidden by a rule the agent runs*?** Impossible-to-reach (capability withheld at the hypervisor, key absent from the guest) is security. Forbidden-by-a-rule-the-agent-runs is a comment in a config file. If you can't tell which one a given control is, that control is the next thing to fix.

---

If the honest answer to a *secure* question is "the agent is trusted not to," you've built attribution, not containment — still useful, but don't trust or market it as a guardrail. If the honest answer to a *simple* question is "well, you also have to edit a cert," no one will operate it. Pass both columns before adding scope.
