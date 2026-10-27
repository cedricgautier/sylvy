<div align="center">

# Sylvy

**Runtime identity &amp; provenance for AI agents — bound to what the kernel actually sees.**

Sylvy observes every agent from below the workload, binds each action to a cryptographically attested identity, and—when you turn it on—contains the agent in a boundary it cannot escape. It runs where you own the host: your Kubernetes nodes, your servers, your EC2.

[Architecture](docs/architecture.md) · [Roadmap](docs/roadmap.md) · [Modes](docs/modes.md) · [Security model](docs/security-self-audit.md) · [Learn the internals](learn/)

![status](https://img.shields.io/badge/status-early%20development-f5a623) ![language](https://img.shields.io/badge/core-Go-00ADD8) ![platform](https://img.shields.io/badge/platform-Linux%20%C2%B7%20eBPF-333) ![license](https://img.shields.io/badge/license-TBD-lightgrey)

</div>

---

## Why Sylvy

Teams are running AI agents — coding agents, autonomous workers, code-execution services — on their own infrastructure. These workloads decide what to do at runtime, run untrusted or generated code, and hold real permissions. Two layers already exist to deal with them, and they each stop at their own edge:

- **Runtime security** (eBPF sensors like Tetragon/Falco/Tracee) sees *what a process did*, but attributes it to a PID or a pod — not to a verifiable agent identity.
- **Agent identity** (SPIFFE/SPIRE, and the IAM platforms built on it) proves *which agent was authorized to call a service*, but only for calls that pass through the auth layer — it is blind to what the agent does on the machine without authenticating.

**Sylvy is the layer between them.** It binds a kernel-observed action to an attested agent identity — tamper-resistantly, and including the actions an agent never authenticated for — then adds agent-level lineage, a provable audit trail, and an optional spawn gate that enforces *no identity, no run*.

> Existing tools answer *"which agent was allowed to call this service?"*
> Sylvy answers *"what did this agent instance and its children actually do on this host — provably, even below the auth layer?"*

Because every action is bound to an identity, Sylvy also **strengthens threat detection**: an anomaly is no longer just "a process did X" but "this agent instance did X, outside its normal behavior." Sylvy is not a detection engine and does not replace the runtime threat detection teams already run — it feeds them an identity-enriched signal and the post-incident trail to answer *"a workload was hijacked — what exactly did it do, and as whom?"*

## How it works

Sylvy integrates mature, battle-tested components and never rebuilds them. Its contribution is the correlation layer that joins them.

| Layer | Sylvy uses | Sylvy builds |
|-------|-----------|-------------|
| Isolation | Firecracker · gVisor | the spawn gate &amp; launch invariants |
| Observation | Tetragon · Falco · Tracee (eBPF) | a source-agnostic streaming adapter |
| Identity | SPIFFE · SPIRE | per-agent-instance issuance &amp; lineage |
| Policy | OPA · OpenFGA | identity-keyed authorization (ReBAC for delegation) |
| **Correlation** | — | **binding action → identity, tamper-resistant** |

The agent is only ever *observed*; it is never trusted to report on itself. Identity flows **down** from the host into each agent; events flow **up** to the control plane. Nothing the agent does reaches back to forge its identity or rewrite its record — a property guaranteed by the hardware boundary between user space and the kernel. See the [architecture](docs/architecture.md) for the full component diagram and production flow.

## Two modes

Sylvy is adopted the way mature security tooling is: observe first, enforce when ready.

- **Observe** — read-only, no privileges, installs in minutes. See and prove what your agents did, attributed to identity. A complete audit/compliance capability on its own.
- **Enforce** — opt-in. Adds the spawn gate, containment in a microVM/gVisor, per-instance identity at spawn, and real-time blocking — with enforcement delegated to tools you already run (OPA, admission control, network policy).

Details and the Observe→Enforce ramp: [docs/modes.md](docs/modes.md).

## Where it runs

Sylvy's full stack runs wherever **you control the node kernel**: self-hosted or managed-standard Kubernetes (EKS/GKE/AKS), plain servers, EC2. It deploys as an unprivileged DaemonSet (Observe) plus a control-plane Deployment, alongside your existing observation sensor and SPIRE — on any CNI, no Cilium required. It does **not** run on serverless (Lambda, Cloud Run, Fargate), where you don't own the kernel.

## What Sylvy is not

- **Not a sandbox provider.** It doesn't compete with E2B/Firecracker on provisioning; it secures agents wherever they run.
- **Not an access-layer agent-IAM platform.** It consumes an identity provider (SPIRE) rather than replacing Okta/Entra/Aembit.
- **Not a prompt or gateway guardrail.** It works below the application, at the kernel, not in the model's reasoning loop.

## Documentation

**Using &amp; building Sylvy**
- [Architecture](docs/architecture.md) — components, deployment, and the production flow
- [Roadmap](docs/roadmap.md) — what to build vs integrate, in testable order (Observe-first)
- [Modes](docs/modes.md) — Observe and Enforce, and how to move between them
- [Security self-audit](docs/security-self-audit.md) — the test every design decision must pass
- [Build guides](docs/building/) — one guided, no-solutions guide per phase

**Learning the internals** → [`learn/`](learn/)
Sylvy is built on deep Linux and kernel foundations. The `learn/` directory is a self-contained, build-it-yourself course in those foundations — processes, `/proc`, Netlink, eBPF, isolation, identity — anchored by a runnable first project. Start at [learn/README.md](learn/README.md). You don't need it to deploy Sylvy; you need it to build and extend Sylvy with confidence.

## Status

Sylvy is in active design and early build. The internals course and its first runnable project are complete today; the platform is specified in the [roadmap](docs/roadmap.md) and built in the Observe-first order described there. No containment or identity claim should be trusted until it passes the [security self-audit](docs/security-self-audit.md).

## Repository layout

```
sylvy/
├── README.md                 # this file
├── docs/                     # the platform
│   ├── architecture.md
│   ├── modes.md
│   ├── roadmap.md
│   ├── security-self-audit.md
│   └── building/             # guided build guides, one per phase
├── tests/
│   └── containment-test.sh   # proves a guest cannot create a nested VM
└── learn/                    # the internals course (study the ground Sylvy stands on)
    ├── README.md
    ├── quickstart.md
    ├── build-it.md           # the first runnable project
    ├── kernel-study.md
    ├── skill-roadmap.md
    ├── lessons/
    └── tests/
```

---

<div align="center">
<sub>Observe from the kernel. Never trust the workload to report on itself.</sub>
</div>
