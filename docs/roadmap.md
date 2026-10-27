# 🧭 Two-track roadmap: build to learn, integrate to ship

> How to grow deep systems understanding *and* ship the product without confusing the two. Companion to the [Sylvy overview](../README.md) and the broader [skill roadmap](../learn/skill-roadmap.md).

Two tracks run in parallel, with different purposes. Do not mix them: code from one is not code for the other.

> The product ships in **two modes** — Observe (read-only) and Enforce (opt-in). Track B below is organised around them; the full contract is in the [modes spec](modes.md). For the component inventory and the production flow by owning component, see the [architecture](architecture.md).

- **Track A — Build to Learn.** Reimplement small, throwaway versions of each layer from scratch. The point is *understanding* Linux, VMs, the kernel, and identity by building them, not shipping them. You write every line. Nothing here goes into the product.
- **Track B — Integrate to Ship.** The MVP. Wrap mature tools (never rebuild them) and build only the one novel thing that doesn't exist: the correlation layer binding kernel-observed actions to attested agent identity. This is production code.

**The link between the tracks:** each Track-A exercise teaches you the internals of the exact Track-B tool you'll later integrate — so when you wrap SPIRE you already understand attestation, when you consume Tetragon you already understand eBPF, when you drive Firecracker you already understand KVM. Understand it small, then stand on the real thing.

## The map (do the A exercise just before the matching B integration)

| Layer | Track A — build yourself to understand | Track B — integrate for the MVP | What A teaches you about B |
|-------|----------------------------------------|----------------------------------|----------------------------|
| Process/kernel | A1 process monitor from scratch | — (feeds everything) | how `/proc`, exec, syscalls work |
| Observation | A2 one detection in raw eBPF | BO1 adapter: consume Tetragon / Falco / Tracee | what an eBPF sensor does under the hood, and its limits |
| Isolation | A3 boot a microVM by hand | B1 drive Firecracker/gVisor | KVM, boot, what the boundary really is |
| Identity | A4 a toy attestor + credential | B3 integrate SPIRE | attestation, signing, why identity flows *down* |
| **Correlation** | A5 bind one action to one identity by hand | **B4 the correlation layer (your core)** | why the binding is the hard, novel part |

Notice the bottom row: the correlation layer is the only one where Track A and Track B are *the same work at different scale*. Everywhere else A is throwaway and B is integration. That's the signal that B4 is your actual product.

---

# Track A — Build to Learn (throwaway, you write it all)

> Guided, no solutions. Each milestone: what to build, what it teaches, the tool it demystifies, and a checkpoint. These are learning artifacts — small, scrappy, deleted after. Resist polishing them.

## A1 — A process monitor from scratch *(you may already have this)*
This is the base [Sylvy project](../README.md): proc connector, `/proc` enrichment, suspicious paths, ports, JSON — pure Go, no eBPF. It teaches the raw mechanics before any framework hides them.
- **Teaches:** processes, `/proc`, exec/fork/exit, the exec race, sockets. See base [lessons 1–5](../learn/lessons/).
- **Demystifies:** the events Tetragon will later hand you for free.
- **Checkpoint:** `sylvy-test.sh` is green; you can explain an exec's journey end to end.

## A2 — One detection in raw eBPF
Re-implement *one* Sylvy detection (exec capture) as an actual eBPF program, kernel-side, driven from Go. Capture the binary path in-kernel (which kills the exec race).
- **Build with:** `cilium/ebpf` + `bpf2go`, or libbpf + CO-RE. See [roadmap lesson 1](building/01-deepen-the-agent.md).
- **Teaches:** the verifier, kprobes/tracepoints/LSM hooks, why in-kernel capture beats user-space polling — and why eBPF is hard.
- **Demystifies:** Tetragon. After this you will *consume* it understanding exactly what it does.
- **Checkpoint:** your eBPF program reports execs with the in-kernel path; you can state two things the verifier refused and why.

## A3 — Boot a microVM by hand
Spawn a single Firecracker microVM through its REST API with a minimal Go wrapper: a kernel, a rootfs, start it, get a shell, kill it. Then apply the capability withholding (no `/dev/kvm`, nested virt off) and run [`containment-test.sh`](../tests/containment-test.sh) inside it.
- **Teaches:** KVM, the boot path, what a VM boundary physically is, why the hypervisor (not the guest) is the enforcement point. See [roadmap lesson 8](building/08-agent-containment.md).
- **Demystifies:** the isolation layer you'll run in B1.
- **Checkpoint:** you boot and kill a microVM from your own code, and the containment test passes from inside it.

## A4 — A toy attestor and credential (one machine)
Build the smallest honest version of attested identity: a tiny "authority" that, at spawn, records what it launched, issues a short-lived signed credential, injects it into the workload, and a verifier that accepts it only if the signature checks and it hasn't expired. Keep the signing key out of the workload.
- **Teaches:** attestation, signing/verification, short-lived credentials, and — by building it — *why identity must flow down from the launcher and can't be claimed upward*. See [roadmap lesson 9](building/09-workload-identity.md).
- **Demystifies:** SPIRE. You'll integrate the real thing in B3 understanding what it does and why not to hand-roll the production version.
- **Checkpoint:** a workload comes up holding a credential it didn't mint; tampering with it makes your verifier reject it.

## A5 — Bind one action to one identity (by hand)
The crux, in miniature: take one event from A1/A2 and one identity from A4, and bind them — "this exec belongs to this identity" — then try to break the binding (forge it, detach it, swap it).
- **Teaches:** the actual hard problem of the whole product — making the action-to-identity link tamper-resistant. This is the one Track-A exercise that is the seed of the real product.
- **Demystifies:** nothing external — this is the part no tool provides, which is exactly why it's yours.
- **Checkpoint:** you can state how an attacker would try to forge or desynchronize the binding, and what would stop it.

**Track A is done when** you can stand in front of each mature tool you're about to integrate and explain what it does internally, because you built a small one. That understanding is the whole point — it's what lets you reason about the seams in Track B instead of trusting them blindly.

---

# Track B — Integrate to Ship (the MVP, production code)

> You integrate four mature tools and build one novel layer. Never rebuild Firecracker, Tetragon, SPIRE, or OPA. Build in **two modes**, in order: **Observe** first (read-only, no privileges, the easy adoption wedge), then **Enforce** on top (gate, contain, block). See the [modes spec](modes.md) for the full contract of each.

## Phase B-Observe — read-only, no privileges (ship this first)

The goal: "see everything agents do, attributed and provable," installable in minutes with nothing privileged to vet. Everything here only *reads*.

### BO1 — The observation-source adapter — *consume Tetragon / Falco / Tracee*
Your product depends on a **kernel-level observation source**, not on one specific tool. The sources don't share an output location or a schema — Tetragon, Falco and Tracee each emit their own event shape over their own channels — so you unify them behind one adapter. You read events; you never write eBPF in the product (A2 was so you'd understand this).

**Define one normalized event** — only the fields the correlation layer needs: identity anchor (PID, TGID, container ID, cgroup, start time), action (type: exec/file-open/connect/exit, binary path, args, file path, remote addr+port), lineage (parent PID / parent exec id), timestamp, and `source` (which tool produced it). Design the core around the **intersection you can rely on everywhere**; put source-specific extras in optional fields. The correlation layer (BO3) only ever sees this normalized event.

**Write one thin adapter per source**, each mapping that tool's native output into the normalized event. **Prefer the streaming API over tailing a log file** — it's the intended integration, structured, real-time, no log-rotation races; file-tailing is the fallback when a customer already ships events to a pipeline.
- **Tetragon** → subscribe to its gRPC `GetEvents` stream (preferred) or its JSON export; standalone on any CNI, no Cilium.
- **Tracee** → consume its gRPC / JSON event stream (firehose model, like Tetragon).
- **Falco** → consume its gRPC output / JSON output channel. Note it is **rule-gated** (alerts on matches, not a raw firehose), so ship a ruleset that emits the event types you need.
- **proc-connector fallback** (no eBPF) → the base-Sylvy source for kernels too old or locked-down for eBPF; lower fidelity (misses fast processes — the exec race), tagged as such.

- **Build:** the normalized event model + one streaming adapter per source. **Wrap:** the eBPF engines. **Checkpoint:** the same correlation layer runs unchanged when you switch the source from Tetragon to Falco or Tracee — only the adapter changes.
- **Honest tiering:** tag every event with its `source` and document which backend yields which completeness (eBPF firehose > broad-ruleset Falco > proc-connector fallback). "Prove everything the agent did" holds on the eBPF sources; on the fallback it weakens to "prove most of it, gaps noted."

### BO2 — Attach existing identity — *read SPIRE + K8s*
Map each event's container to its pod/workload (K8s API, watch-only) and attach whatever identity already exists (SPIRE SVID / SPIFFE ID — per-pod granularity in this mode).
- **Build:** the mapping. **Wrap:** SPIRE. **Checkpoint:** each event carries a workload identity.

### BO3 — The correlation layer — *yours, the actual product*
Bind every event to the identity of the workload that caused it, tamper-resistantly, and keep the records. This is the one thing no tool ships, the seed of A5, and where your hardest effort belongs — and it works the same in both modes.
- **Build:** the join, designed so actions can't be forged onto another identity or detached from their own. **Checkpoint:** "show me everything workload X did, provably" returns a correct, attributable trail.

### BO4 — Provenance, lineage, query, audit — *yours*
Store the bound records; rebuild lineage through `exec_id`/`parent_exec_id`; answer queries; emit a compliance audit trail.
- **Checkpoint:** a child process traces to its parent; an auditor query returns a provable per-workload history.

### BO5 — Deployment (read-only) — *yours, thin*
Ship as an unprivileged **DaemonSet** (or even a central Deployment consuming exported events) plus a **control-plane Deployment** (join, store, query). Drops all capabilities, read-only filesystem, installs alongside existing Tetragon and SPIRE without touching the cluster's networking.
- **Checkpoint:** on a cluster running Tetragon + SPIRE (any CNI, no Cilium required), it deploys unprivileged and produces agent provenance.

**Observe mode is done when** a team installs it in minutes, grants no privileges, and can prove what their agents did. That alone is a sellable audit/compliance product.

## Phase B-Enforce — opt-in, acts (build on top of Observe)

The goal: "now stop it." Adds the acting layers. Higher privilege, so it's opt-in and enforcement is **delegated** to tools the customer already trusts (see the [modes spec](modes.md)).

### BE1 — The spawn gate (host daemon) — *yours*
The daemon becomes the only path to launch an agent: no identity, no run. This is the one piece that must act directly on the host.
- **Checkpoint:** the only way to start an agent is through the daemon.

### BE2 — Containment — *wrap Firecracker/gVisor*
The daemon launches each agent in a microVM (Firecracker) or gVisor (K8s RuntimeClass), applying the launch invariants from A3. Reuse `../tests/containment-test.sh` as continuous proof, and add fail-closed (kill a VM whose in-guest sensor goes silent or whose boundary traffic doesn't match its events).
- **Build:** the adapter + invariant enforcement + fail-closed. **Wrap:** the VMM. **Checkpoint:** agents run in a boundary, containment proven from inside.

### BE3 — Per-agent-instance identity at spawn — *wrap SPIRE*
Now that you own the spawn, issue identity per agent instance and per task (not just per pod), with lineage, injected at launch via the Workload API.
- **Build:** spawn-time issuance wiring. **Wrap:** the crypto. **Checkpoint:** each agent instance holds its own attested SVID it didn't mint.

### BE4 — Delegated enforcement — *wrap a policy engine + Tetragon + network policy + admission*
Decisions keyed on agent identity ("may agent X do Y?"), default-deny, evaluated by a policy engine; blocking delegated to Tetragon tracing policies (process/syscall), the cluster's network-policy enforcer (standard Kubernetes NetworkPolicy via its existing CNI, or Cilium if present), and an admission controller that forces agent pods onto the sandboxed runtime. Your component generates the policy; the existing enforcers act.

**Policy engine (pluggable):** **OPA** for attribute/context policy-as-code ("deny if the binary is unpackaged and the namespace is prod"), or **OpenFGA** (CNCF, Zanzibar-style ReBAC) for *relationship* policy. OpenFGA is the stronger fit for the **agent-delegation** question — "this agent, spawned by that service, acting on behalf of this user, may touch this resource" — because delegation chains are exactly the nested relationships ReBAC models. Keep this behind the same seam as identity: a simple allow-list needs neither; reach for ReBAC only when delegation relationships are the thing you're authorizing.
- **Build:** the policy generation + query integration. **Wrap:** the enforcers. **Checkpoint:** a disallowed action is blocked by a delegated enforcer, not by luck.

### BE5 — Operator experience & the Observe→Enforce ramp — *yours*
One git-versioned allow-list keyed on agent identities, edited in a few readable lines; suggest candidate rules from observed behaviour; run enforcement in dry-run before flipping policies active.
- **Checkpoint:** a DevSecOps engineer authorizes a new interaction in a few readable lines, after previewing it in dry-run.

### BE6 — The agent template (the operator's front door) — *yours, thin*
Ship the one thing an operator uses to run an agent: a template that *is* the "this is an agent" declaration. Not a new Kubernetes object — an ordinary pod/Deployment spec with the markers baked in: the `workload-type: agent` label, the sandboxed `runtimeClassName` (gVisor/Firecracker), a scoped service account SPIRE attests, and placement in an agent namespace.
- **MVP form:** a Helm chart (or a well-documented manifest) where the operator sets image + resources and it renders the correct agent-pod spec every time. A CRD + operator (`kind: Agent`) is a *Later* item, not MVP.
- **Back it with enforcement:** an admission policy so the template is the *only* way to run an agent — any pod labeled `agent` without the sandboxed runtime and agent namespace is rejected. Declaration (template) + enforcement (admission) is the pair; neither alone suffices.
- **Keep it thin:** the template only gets the agent *launched correctly* — labeled, sandboxed, attestable. The correlation, provenance and enforcement are your DaemonSet and control plane, which pick the agent up *because* it launched through the template. Using the template must be *easier* than writing a plain Deployment, or adoption dies.
- **Checkpoint:** an operator runs an agent by filling in a couple of values; a plain Deployment that tries to skip the template (no sandbox, wrong namespace) is rejected by admission.

**Enforce mode is done when** a customer who ran Observe can turn on containment and blocking incrementally, in dry-run first, with your component holding minimal privilege and delegating the acting to tools they already run.

## Later (not MVP)
Cross-cluster **federation**; the **agent-above-workload identity / delegation** layer (unsettled research — keep swappable); dashboards; multi-backend isolation adapters.

---

## Deploying and testing in a real cluster

Before any of this works end to end on a cluster, these are the concrete steps — the prerequisites you don't build, the two things you deploy, the agent template you ship, and what to actually test. Do them in order.

**0. Confirm the host prerequisites (not installable — must be true)**
- You control the node kernel (self-hosted or managed-*standard* K8s — not serverless / Autopilot / Fargate).
- Linux kernel ≥ 5.x with BTF (for eBPF).
- KVM available if you want Firecracker microVMs; otherwise use gVisor (no KVM needed).

**1. Install the dependencies you consume (or confirm they're present)**
- A kernel-level observation source as a DaemonSet — **Tetragon, Falco, or Tracee** (whichever the customer runs; all plug into the BO1 adapter via their streaming API). Tetragon is the recommended default; it's standalone on any CNI, no Cilium needed. The proc-connector fallback covers no-eBPF kernels at lower fidelity.
- SPIRE server (in `spire-system`) + SPIRE agent DaemonSet — identity. Protect the server's signing key (KMS/HSM), one trust domain per cluster.
- For Enforce only: an isolation RuntimeClass (gVisor/Firecracker), a policy engine (OPA, or OpenFGA for relationship/delegation policy), an admission controller (Kyverno/Gatekeeper), and a network-policy enforcer (the cluster's existing CNI via Kubernetes NetworkPolicy is enough).
- **Optional:** Cilium, only if the customer wants rich network-flow analytics / eBPF network policy. Not required for Observe or for basic Enforce.

**2. Set up the namespaces (by trust level)**
- `spire-system` (identity root, tightest RBAC), your platform namespace (control plane, OPA, admission), a system namespace for the DaemonSets, and one agent namespace per tenant/app.

**3. Deploy your two components**
- The control-plane Deployment (platform namespace).
- Your DaemonSet (read-only for Observe; privileged spawn gate added for Enforce).

**4. Ship and install the agent template (BE6)**
- Package the agent template as a Helm chart/manifest and install the admission policy that makes it mandatory.
- **Test it both ways:** (a) run an agent *through* the template and confirm it launches labeled, sandboxed, attested, and that your system issues it an identity and tracks it; (b) try to run a **plain Deployment that skips the template** (no sandbox / wrong namespace) and confirm admission **rejects** it. Both outcomes must hold — the happy path works *and* the bypass is blocked.

**5. Run the containment proof**
- Exec [`../tests/containment-test.sh`](../tests/containment-test.sh) inside a spawned agent and confirm it cannot create a nested VM (device door, capability door, live open attempt). Wire it into CI so every build re-proves it.

**6. Verify the end-to-end promise**
- Observe: "show me everything agent X did, provably" returns a correct attributed trail, with no privilege granted.
- Enforce (dry-run first, then active): a disallowed agent action is blocked by a delegated enforcer; an undeclared workload that behaves like an agent is flagged.

**7. Test the failure and bypass paths, not just the happy path**
- A workload the operator *forgot* to declare → behavioral anomaly raised, not silently ignored.
- Something started *outside* the daemon → flagged as un-attested.
- In-guest sensor killed (microVM) → fail-closed terminates the VM.
- SPIRE agent unreachable at spawn → agent doesn't get an identity → no-identity-no-run holds.

## How to interleave the two tracks

Do the Track-A exercise immediately before the Track-B integration it demystifies, then throw the A code away and integrate the real tool:

1. A1 → you have the base agent.
2. A2 (write eBPF) → BO1 (the observation-source adapter: Tetragon / Falco / Tracee).
3. A5 (bind by hand) → **BO3 (the correlation layer)** → BO4 → ship **Observe mode**.
4. A3 (boot a VM) → BE1 (the gate) + BE2 (containment).
5. A4 (toy attestor) → BE3 (per-instance identity at spawn).
6. BE4, BE5, BE6 (delegated enforcement, operator ramp, agent template) — no A needed.

Observe mode (BO1–BO5) is a complete, shippable product on its own; Enforce (BE1–BE5) is built on top only when a customer wants it.

## The honest split, in one view

- **What you build to *understand* (Track A):** small from-scratch versions of process monitoring, eBPF, a microVM boot, attested identity, and the binding. Throwaway. This is where your deep Linux/VM/kernel mastery comes from.
- **What you build to *ship* (Track B):** the correlation layer, provenance/lineage/audit, the read-only deployment (Observe); then the spawn gate, containment glue, per-instance issuance, policy generation and the operator ramp (Enforce). Everything else is integration of Firecracker, Tetragon, SPIRE, and OPA (plus the cluster's own CNI for network policy; Cilium optional). Ship **Observe first** — it's a product by itself.
- **The one piece that is both your hardest learning and your actual product:** binding action to identity, tamper-resistantly (A5 → B4). If you get that trustworthy, you have a product; if it's forgeable, you have a logger. Spend accordingly.

Two cautions. Don't skip Track A to go faster — you'll integrate the Track-B tools without understanding their seams, and the seams are where security lives. And don't let Track A leak into the product — its value is the understanding in your head, not the throwaway code; the MVP stands on the mature tools, not your learning reimplementations.
