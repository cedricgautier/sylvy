# Roadmap Lesson 8 — Agent containment and the capability model

> Supports **Phase 8**. Go + hypervisor + eBPF. The leap from *watching* agents to *containing* them: a non-bypassable boundary around each agent, enforced from outside the agent. Guidance and resources only — you design and build it.

## What you are building and why

The base project observes and reports. This phase makes the host able to **stop** a misbehaving or hijacked agent, not just see it. The core idea, which you reasoned your way to in design, is one sentence: **enforcement must live where the agent cannot execute code against it** — the hypervisor (outside the guest) and the kernel (beneath the process). Anything enforced *by* the agent, *on* the agent, is removable by whoever controls the agent. So the whole phase is about putting the controls in the two places the agent can't reach.

Three things must be true, and each maps to a place:

- **Isolation** — a compromised agent is contained. Lives in the *hypervisor* (microVM / gVisor).
- **Non-bypassable launch** — nothing runs that the host did not start and attest. Lives in a *host daemon* that owns every spawn.
- **Observation bound to identity** — every action is attributable and anomalies are caught. Lives in *eBPF*, beneath the workload.

## Mission 1 — The isolation boundary

Give each agent a real boundary, not just a container namespace. Two mature options, different trade-offs:

- **microVM (Firecracker):** each agent gets its own kernel; hardware-assisted isolation; a kernel exploit is contained. Needs `/dev/kvm` and virtualization support. Heavier.
- **gVisor:** a user-space kernel intercepting the guest's syscalls; lighter, no nested-virt requirement; different trust model.

**Resources:** the Firecracker and gVisor documentation; the KVM API overview (`man` pages and the kernel `Documentation/virt/kvm`).
**Checkpoint:** you can launch an agent inside a microVM (or gVisor), and destroying it leaves nothing behind on the host.

## Mission 2 — The host daemon as the only gate

Make a **host-side** daemon the single path by which any agent workload is spawned. This is the root of trust, and it must sit *outside* every guest (see the common mistake below).

- The daemon owns the launch: it decides what image/config runs, and it is the thing that attaches identity (Phase 9) at spawn.
- The guardrail — **no identity, no run** — is enforced here, at the one moment the workload comes into existence, before it can act.
- **Checkpoint:** the only way to start an agent on the node is through the daemon; a request to run something it won't attest is refused at spawn.

> **The mistake to avoid (you caught this one yourself):** the enforcing daemon must **not** live *inside* the spawned VM judging itself — a guard the guarded party can delete is not a guard. The daemon runs on the **host**; the VM is the *guarded* thing, not the *guard*. "Shut down if not legitimate" is a decision the host makes about the guest, from outside, never the guest about itself.

## Mission 3 — The capability model (what each layer is allowed to do)

This is the security backbone of the phase: be explicit about which powers are **withheld at the hypervisor** (hardware-gated, easy to deny cleanly) versus **governed by the identity/eBPF layer** (execution inside the guest). They are two different doors with two different locks — do not conflate them.

| Power | Where it's controlled | How |
|-------|----------------------|-----|
| Create a nested VM (new isolation boundary) | Hypervisor | Withhold `/dev/kvm` **and** nested virt — see Mission 4 |
| Access the host's devices / memory | Hypervisor | The microVM boundary itself |
| Issue identity / hold a signing key | Host (outside guest) | Never present in the guest (Phase 9) |
| Spawn processes inside its own VM | Guest kernel | Governed by identity + eBPF, not by the VM lock |
| Reach the network | Policy layer | Allow-list keyed on identity (Phase 9) |

The row that trips people: **blocking nested VMs does not block process spawning.** A guest can still `fork`/`exec` inside its own kernel — that needs no virtualization extension. If you also need to govern process spawning, that is the identity + eBPF layer's job, not this lock's.

## Mission 4 — Forbid a guest from creating a new isolation boundary

A concrete, hardware-backed control: a spawned microVM must not be able to spawn microVMs. You withhold the capability at launch rather than asking the guest not to use it — there are two independent doors, close both.

- **The device door — `/dev/kvm`.** A userspace VMM (Firecracker, QEMU) creates a VM by opening `/dev/kvm` and issuing ioctls. If that device node is not present in the guest, the path does not exist. Do not expose it into the guest.
- **The CPU-feature door — nested virtualization.** Whether the guest's vCPU even advertises the virtualization extensions (VMX on Intel, SVM on AMD). Nested virt is **opt-in**: off unless deliberately enabled on the host KVM module and exposed to the guest's vCPU model. Leave it off; do not advertise the feature to the guest.

Close both so they back each other up: no capability (nested virt off) *and* no handle (`/dev/kvm` absent). Back them with the restrictions you'd apply anyway — a seccomp profile and dropped capabilities so the device-open and ioctl paths aren't reachable even if a node appeared. Bake all of this into the host daemon as **non-overridable launch invariants**, with no per-workload switch, so it can never be accidentally flipped on.

**Resources:** the KVM module's nested parameter; your VMM's vCPU/feature configuration; `seccomp(2)` and `capabilities(7)`.

### Acceptance test — prove it from *inside* the guest

A withheld capability is only withheld if you've verified the guest can't reach it; configuration intent and runtime reality drift. Make this a test in your harness, run on every spawned guest:

1. Device absent: `ls /dev/kvm` → "No such file or directory".
2. Capability absent: `grep -E 'vmx|svm' /proc/cpuinfo` → no output.
3. The real test: actually attempt a nested launch from inside the guest and confirm it fails at KVM acquisition, not somewhere incidental.

If 1 and 2 disagree (device gone but `vmx`/`svm` still present), you closed the device door but left the capability — close nested virt too. "The guest cannot create a nested VM" should be an assertion your system continuously proves, not a flag you set once.

A ready-made harness for exactly this ships with the project: [`tests/containment-test.sh`](../../tests/containment-test.sh). Run it **inside** each spawned guest — as a boot-time self-check, or have the host daemon exec it into the guest right after launch. It is portable pure shell (no installs), checks the device door, the capability door and a safe read-only open attempt (it never creates the device), warns on defense-in-depth smells (a visible KVM module, a shipped VMM binary, seccomp off), and exits non-zero if the guest is not contained. Wire it into CI so every build proves the property:

```
# inside the guest image's test stage, or via the daemon after spawn
./containment-test.sh || { echo "guest is not contained — fix the launch config"; exit 1; }
```

Like the base project's `sylvy-test.sh`, this harness is a **verification tool, not a solution** — it tells you whether your launch configuration withheld the capability; configuring the launch correctly (no `/dev/kvm`, nested virt off, seccomp + dropped caps) is still your work.

## Mission 5 — Bind every action to an identity (eBPF)

Re-use your eBPF observation work, but now attribute each event (exec, file, network) to the agent identity the daemon issued at spawn, not just a PID. Then add the backstop: **anything running on the node that the daemon did not launch and did not issue an identity to is an anomaly** — flagged, and blockable. Host daemon = the gate; eBPF = the alarm if someone climbs the fence instead of using it.

**Checkpoint:** you can show, for one agent, every action it took bound to its identity; and a process started *around* the daemon is detected as unidentified.

## How to know Phase 8 is done

An agent runs inside a real isolation boundary it cannot escape or widen (no nested VM — proven from inside), started only through a host daemon that attaches identity at spawn, with every action attributed and un-attested workloads flagged. You can state, for each power in the capability table, exactly which layer denies it and why the agent can't reach that layer.
