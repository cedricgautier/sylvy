# Roadmap Lesson 9 — Workload identity and agent provenance

> Supports **Phase 9**. Builds on [Phase 8](08-agent-containment.md). The hardest and most valuable layer: a verifiable identity for every agent, rooted in attestation, so every action is provably attributable and every agent-to-agent call is authorized. Guidance and resources only.

## What you are building and why

Phase 8 contains agents and watches them. This phase answers *who* — provably, not by a label a compromised process can forge. The central property, which you reasoned out in design: **identity flows down from the launcher and is attested, never claimed upward by the workload.** The host knows what it launched (image, config, parent, node); it issues the identity against those facts; the agent presents it but cannot have minted it. That one direction — downward from the attestor — is the entire security story.

Three planes, kept separate so each stays swappable:

- **Identity** — issue a cryptographic, short-lived credential per agent, rooted in attestation.
- **Provenance** — bind each observed action (from Phase 8's eBPF) to that identity, and track lineage when an agent spawns children.
- **Authorization** — a *separate* policy layer decides what a proven identity may do. Identity answers "who are you"; policy answers "may you." Never tangle them, or every authz change becomes a certificate change.

## Is SPIFFE/SPIRE the right choice? (interrogate, don't assume)

Mostly yes, with a sharp boundary. **SPIFFE/SPIRE** is a CNCF graduated standard for cryptographic workload identity (used by Istio, SPIFFE-aware policy in Tetragon, production use at large companies). It is the right foundation because it is the mature thing that issues an identity **rooted in attestation**: a host-side agent attests *how a workload launched* (node, namespace, service account selectors) before issuing a short-lived credential (an SVID) — exactly the non-forgeable root you need, and it lines up with the launch facts your Phase 8 daemon already knows.

But know where it stops, because this decides your architecture's seam. SPIFFE answers "which **workload** is this, cryptographically." It does **not** answer "which **agent**, acting on whose behalf, delegated how far." That upper layer — agent identity, delegation, provenance across hops — is an **unsettled research area** in 2026 (competing IETF drafts: WIMSE, Agentic JWT, AIMS; none yet complete, some already expired). So:

> **Design decision:** build the workload-identity plane **on** SPIFFE/SPIRE (mature — wrap it, do not reimplement), and keep the **agent/delegation layer a thin thing you own behind an interface** (unsettled — must stay swappable). The pluggability seam goes exactly at the SPIFFE boundary: stable standard below, your agent model above.

**Resources:** spiffe.io (concepts: trust domains, SVIDs, the Workload API, node vs workload attestation, selectors); the SPIRE docs and Helm charts; a policy engine for the separate authorization plane — **OPA** (attribute/context) or **OpenFGA** (Zanzibar-style ReBAC, a natural fit for agent-delegation relationships).

## Mission 1 — Issue an attested identity at spawn

Wire the Phase 8 host daemon to SPIRE: when it spawns an agent, the workload is attested (by its selectors) and receives its SVID through a channel the host controls — injected at boot, or fetched over the Workload API socket the host mounts in. The agent never "asks for" an identity it could fake.

**Checkpoint:** a spawned agent comes up holding a valid SVID it did not mint; tampering with that credential makes verifiers reject it (the signature breaks — the signing key was never in the guest).

## Mission 2 — Bind actions to identity, and track lineage

Join Phase 8's eBPF events to the issued identity, so "this syscall / this connection belongs to agent X, instance 4192" is provable. When an agent spawns children, record the parent link so the whole action tree is attributable to the originating agent.

**Checkpoint:** you can produce, for one agent instance, its full action tree bound to its identity — and a child's actions trace back to the parent that spawned it.

## Mission 3 — Cross-cluster: federation, not one big trust domain

Agents cross cluster and org boundaries. The settled answer is **SPIFFE federation**: each cluster/cloud runs its *own* SPIRE server with its *own* trust domain, and domains that must talk exchange trust bundles through a federation endpoint — so an identity issued in cluster A is verifiable in cluster B without either holding the other's signing key.

Why not one flat trust domain spanning everything: **a single flat domain turns one compromised server into a skeleton key for the whole fleet.** Federation keeps each domain's attestation independent and limits blast radius. Do not try to run one domain across clouds — node attestation differs per cloud; run one domain per cluster/cloud and federate at the edges that genuinely need it.

**Resources:** SPIRE federation and trust-bundle documentation. **Checkpoint:** an identity minted in one cluster is verified in a federated second cluster, with each running its own server.

## Mission 4 — The security invariant: a guest can never become a host/root

This is the make-or-break. A guest tampering with its own identity is harmless (forged credential, rejected by verifiers). A guest acquiring the power to **issue** identity is catastrophic (a skeleton key for its subtree). The invariant: **the power to issue identity — the signing key and the attestor — lives outside every guest, in the host and its hardware root, and is never delegated downward.**

Hold these, and design so a guest cannot even reach the capability:

- The **signing key never enters a guest** — it stays with the host attestor / SPIRE server, ideally hardware-backed (HSM / host TPM).
- The **attestor runs on the host**, not the guest — the "is this legitimate, what identity does it get" decision executes where guest code can't run.
- **Selectors are host-asserted**, from the launch facts — a guest cannot attest *itself* into a more privileged class; "I am a root" is a claim only the host above it could make, and it won't, because that's not what it launched.
- A workload that spawns children is an **intermediate in the chain, not a holder of the key** — it *requests* issuance upward; the host signs. Nesting in the namespace, yes; key possession, never.

### Chain, not loop

Spawning hosts-of-guests-of-guests is a **finite tree rooted in a trust anchor**, not an infinite loop. Each parent attests its children; verification walks *up* to a root and stops. **Vertical = delegated issuance** (parent attests child). **Horizontal = verification against shared/federated roots** (peers trust the root, not each other — a cycle of peers vouching for peers anchors in nothing and is insecure). Keep chains **shallow**, intermediate scopes **narrow**, credentials **short-lived**, and trust domains **separated by federation** — depth and breadth are attack surface.

### Hop-by-hop communication

A sub-guest talks only to its **immediate parent**, never across levels to the root, over a **parent-controlled** channel through the VM boundary (a host-managed virtual socket such as vsock, a virtual device, or boot-time injection). And note: the **identity tree can be deeper than the isolation tree** — you can attribute many sub-agents as *processes* inside one microVM without nesting VMs. Reach for nested isolation only where a sub-workload is genuinely untrusted relative to its own parent; otherwise you pay the nested-virt tax for nothing.

## Mission 5 — Make authorization simple for the DevSecOps engineer

Everything above is plumbing; adoption depends on this. Keep identity and policy **separate** (SPIFFE/mTLS proves *who*; a policy engine — OPA for attributes, or OpenFGA for delegation relationships — decides *may you*). Then:

- The engineer writes intent in terms of **identities and capabilities, never IPs, ports, or certs** ("the summarizer agent may call the document service").
- Identities are **issued automatically from attestation** (selectors) — nobody provisions a credential by hand.
- The default is **deny**, with a short readable allow-list — default-allow is theater.
- Policy is **one git-versioned artifact** that reads the same on one laptop or a federated fleet; the system compiles it down to SVIDs, mTLS and kernel rules.

**Success test, blunt:** a DevSecOps engineer authorizes a new agent-to-service interaction by adding a few readable lines — no certs, no IPs, no redeploy.

## Honest note on the ephemerality tension

Attesting and issuing at every spawn costs time; very short-lived agents can't wait on slow X.509 issuance. Real mitigations, real work: pre-attested identity pools, snapshot-restore with identity injected at resume, or faster JWT-SVIDs for the shortest-lived workloads. Plan for it; don't assume issuance is free.

## How to know Phase 9 is done

Every agent has an attested, short-lived identity it can't forge; its actions and lineage are provably bound to it; identities verify across federated clusters; a guest demonstrably cannot obtain issuing power; and a DevSecOps engineer can authorize a new interaction in a few readable lines. Build the issuance on SPIRE; own only the thin agent layer and the policy surface.
