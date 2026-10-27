# 🗺️ Architecture

> How the system fits together: the components you build versus the tools you integrate, and the production flow by owning component. Companion to the [roadmap](roadmap.md), the [modes spec](modes.md), and the [Sylvy overview](../README.md).

Everything below is **light theme first**; the SVGs also carry dark-mode fills so they render on either GitHub theme.

## Components: what you build vs what you integrate

You ship five components. Everything else is mature software you wrap and never rebuild. Of the five, the **correlation layer** is the actual product — binding each action to an attested identity, tamper-resistantly. The rest are a DaemonSet, stream adapters, a storage/query service, and a Helm chart.

<svg width="100%" viewBox="0 0 680 250" role="img" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">
  <style>
    .t{fill:#2c2c2a;font-size:14px;font-weight:500}
    .ts{fill:#5f5e5a;font-size:12px}
    .hd{fill:#26215c;font-size:14px;font-weight:500}
    .hg{fill:#0f6e56;font-size:14px;font-weight:500}
    @media (prefers-color-scheme: dark){
      .t{fill:#e9e8e3}.ts{fill:#b4b2a9}.hd{fill:#cecbf6}.hg{fill:#9fe1cb}
    }
  </style>
  <rect x="20" y="20" width="315" height="210" rx="12" fill="#eeedfe" stroke="#534ab7" stroke-width="0.5"/>
  <text class="hd" x="36" y="44">You build &amp; ship</text>
  <text class="t" x="36" y="74">Node daemon (DaemonSet)</text>
  <text class="ts" x="36" y="92">observes; in Enforce, the spawn gate</text>
  <text class="t" x="36" y="118">Observation-source adapter</text>
  <text class="ts" x="36" y="136">normalizes Tetragon / Falco / Tracee</text>
  <text class="t" x="36" y="162">Correlation layer — the core</text>
  <text class="ts" x="36" y="180">binds action to identity, tamper-safe</text>
  <text class="t" x="36" y="206">Control plane · Agent template</text>
  <text class="ts" x="36" y="224">store, query, audit, policy · front door</text>

  <rect x="345" y="20" width="315" height="210" rx="12" fill="#e1f5ee" stroke="#0f6e56" stroke-width="0.5"/>
  <text class="hg" x="361" y="44">You integrate (never rebuild)</text>
  <text class="t" x="361" y="74">Observation sensor</text>
  <text class="ts" x="361" y="92">Tetragon / Falco / Tracee (eBPF)</text>
  <text class="t" x="361" y="118">Identity — SPIRE</text>
  <text class="ts" x="361" y="136">server + per-node agent</text>
  <text class="t" x="361" y="162">Isolation — Firecracker / gVisor</text>
  <text class="ts" x="361" y="180">the agent boundary (Enforce)</text>
  <text class="t" x="361" y="206">OPA/OpenFGA · admission · net policy</text>
  <text class="ts" x="361" y="224">the enforcers (Enforce)</text>
</svg>

## Production flow, by owning component

The same ten steps that take an agent from deploy to audit, grouped into three lanes: the tools you integrate, your components, and the agent workload. Read it by lane: your components own five steps, integrated tools own four, and the agent owns exactly one — it acts. The flow keeps crossing between the tool lane and your lane; those hand-offs (especially 6 → 7 → 8, raw event → normalized event → action bound to identity) are the architecture. Identity flows **down**, events flow **up**; nothing the agent does reaches back to forge its identity or rewrite its record.

<svg width="100%" viewBox="0 0 680 600" role="img" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">
  <style>
    .t{fill:#2c2c2a;font-size:14px;font-weight:500}
    .ts{fill:#5f5e5a;font-size:12px}
    .ln{stroke:#888780;stroke-width:1.5;fill:none}
    .lng{stroke:#1d9e75;stroke-width:1.5;fill:none}
    .lna{stroke:#ba7517;stroke-width:1.5;fill:none}
    .lnp{stroke:#534ab7;stroke-width:1.5;fill:none}
    .lane{fill:none;stroke-width:0.5}
    .gb{fill:#e1f5ee;stroke:#0f6e56}
    .pb{fill:#eeedfe;stroke:#534ab7}
    .cb{fill:#faece7;stroke:#d85a30}
    .laneG{fill:#e1f5ee;stroke:#0f6e56}
    .laneP{fill:#eeedfe;stroke:#534ab7}
    .laneC{fill:#faece7;stroke:#d85a30}
    .lt{fill:#5f5e5a;font-size:12px}
    .nt{fill:#2c2c2a;font-size:14px;font-weight:500}
    .ns{fill:#5f5e5a;font-size:12px}
    @media (prefers-color-scheme: dark){
      .t,.nt{fill:#e9e8e3}.ts,.ns,.lt{fill:#b4b2a9}
      .laneG,.gb{fill:#04342c}.laneP,.pb{fill:#26215c}.laneC,.cb{fill:#4a1b0c}
      .gb{stroke:#9fe1cb}.pb{stroke:#cecbf6}.cb{stroke:#f5c4b3}
      .laneG{stroke:#9fe1cb}.laneP{stroke:#cecbf6}.laneC{stroke:#f5c4b3}
    }
  </style>
  <defs><marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M2 1L8 5L2 9" fill="none" stroke="context-stroke" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></marker></defs>

  <rect class="laneG" x="20" y="20" width="210" height="560" rx="12" fill-opacity="0.35"/>
  <rect class="laneP" x="238" y="20" width="210" height="560" rx="12" fill-opacity="0.35"/>
  <rect class="laneC" x="456" y="20" width="204" height="560" rx="12" fill-opacity="0.35"/>
  <text class="lt" x="125" y="40" text-anchor="middle">Integrated tools (wrapped)</text>
  <text class="lt" x="343" y="40" text-anchor="middle">Your components</text>
  <text class="lt" x="558" y="40" text-anchor="middle">Agent workload</text>

  <g><rect class="pb" x="250" y="56" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="343" y="76" text-anchor="middle">1 · Operator deploys</text>
  <text class="ns" x="343" y="92" text-anchor="middle">agent template</text></g>

  <g><rect class="gb" x="32" y="116" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="125" y="136" text-anchor="middle">2 · Admission check</text>
  <text class="ns" x="125" y="152" text-anchor="middle">label+sandbox or reject</text></g>
  <path class="ln" d="M343 100 L343 112 L125 112 L125 114" marker-end="url(#ah)"/>

  <g><rect class="pb" x="250" y="176" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="343" y="196" text-anchor="middle">3 · Gate spawns</text>
  <text class="ns" x="343" y="212" text-anchor="middle">no identity, no run</text></g>
  <path class="ln" d="M125 160 L125 198 L248 198" marker-end="url(#ah)"/>

  <g><rect class="gb" x="32" y="236" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="125" y="256" text-anchor="middle">4 · SPIRE issues SVID</text>
  <text class="ns" x="125" y="272" text-anchor="middle">attested</text></g>
  <path class="lng" d="M343 220 L343 258 L220 258" marker-end="url(#ah)"/>

  <g><rect class="cb" x="464" y="236" width="188" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="558" y="256" text-anchor="middle">5 · Agent acts</text>
  <text class="ns" x="558" y="272" text-anchor="middle">microVM / gVisor</text></g>
  <path class="lng" d="M125 280 L125 300 L558 300 L558 282" marker-end="url(#ah)"/>

  <g><rect class="gb" x="32" y="316" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="125" y="336" text-anchor="middle">6 · Sensor captures</text>
  <text class="ns" x="125" y="352" text-anchor="middle">Tetragon/Falco/Tracee</text></g>
  <path class="lng" d="M558 280 L558 338 L220 338" marker-end="url(#ah)"/>

  <g><rect class="pb" x="250" y="376" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="343" y="396" text-anchor="middle">7 · Adapter normalizes</text>
  <text class="ns" x="343" y="412" text-anchor="middle">one event model</text></g>
  <path class="ln" d="M125 360 L125 398 L248 398" marker-end="url(#ah)"/>

  <g><rect class="pb" x="250" y="436" width="186" height="48" rx="8" stroke-width="0.5"/>
  <text class="nt" x="343" y="456" text-anchor="middle">8 · Bind to identity</text>
  <text class="ns" x="343" y="472" text-anchor="middle">the core</text></g>
  <path class="ln" d="M343 420 L343 436" marker-end="url(#ah)"/>

  <g><rect class="gb" x="32" y="440" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="125" y="460" text-anchor="middle">9 · Policy decides</text>
  <text class="ns" x="125" y="476" text-anchor="middle">OPA · allow / block</text></g>
  <path class="lna" d="M248 460 L222 460" marker-end="url(#ah)"/>

  <g><rect class="pb" x="250" y="516" width="186" height="44" rx="8" stroke-width="0.5"/>
  <text class="nt" x="343" y="536" text-anchor="middle">10 · Store &amp; audit</text>
  <text class="ns" x="343" y="552" text-anchor="middle">control plane</text></g>
  <path class="lnp" d="M343 484 L343 516" marker-end="url(#ah)"/>
</svg>

## Observe vs Enforce along the flow

The two [modes](modes.md) fall cleanly along the same steps. **Observe mode** removes the gate (3), the isolation requirement (5), and the policy decision (9): the agent runs as an ordinary workload, the sensor still captures it, the adapter normalizes, the correlation layer binds it to whatever identity exists, and it is stored and auditable. Steps 5–8 and 10 are the same code in both modes — which is why Observe ships first and Enforce is built on top.

| Step | Observe (read-only) | Enforce (opt-in) |
|------|---------------------|------------------|
| 1 Operator deploys | yes | yes |
| 2 Admission check | optional | yes (mandatory template) |
| 3 Gate spawns | — | yes (no identity, no run) |
| 4 Identity | per-pod (existing) | per-agent-instance at spawn |
| 5 Agent acts | ordinary workload | in microVM / gVisor |
| 6 Sensor captures | yes | yes |
| 7 Adapter normalizes | yes | yes |
| 8 Bind to identity | yes | yes |
| 9 Policy decides | — (observe only) | allow / block |
| 10 Store &amp; audit | yes | yes |

## Where it runs

The node daemon is a DaemonSet (one pod per node, every node); the control plane is a Deployment in a platform namespace. Components are separated by trust level: `spire-system` (identity root, tightest), the platform namespace (your control plane, OPA, admission), a system namespace for the per-node DaemonSets, and one agent namespace per tenant (least privilege, where agents run in their isolation boundary). Identity flows down into the tenant namespaces; events flow up to the control plane; nothing flows the other way. See the [deployment-and-test checklist](roadmap.md#deploying-and-testing-in-a-real-cluster) for what must be installed and in what order.
