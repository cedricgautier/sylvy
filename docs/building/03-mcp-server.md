# Roadmap Lesson 3 — The MCP server

> Supports **Phase 3**. Go. The keystone that lets an LLM or a script query the host through well-defined tools. Guidance and resources only.

## What you are building and why

A **Model Context Protocol (MCP)** server exposes capabilities as named *tools* with typed inputs and outputs, over a standard protocol. Wrapping Sylvy in one turns "what is happening on this host" into something a Python program or an AI assistant can call safely. It also forces good service design: the server decides exactly what is exposed and never runs arbitrary input.

## Mission 1 — A first tool over stdio

Stand up a minimal server with one tool, running over standard input/output.

- Use the **official Go SDK**: `github.com/modelcontextprotocol/go-sdk/mcp` (maintained in collaboration with Google). It is **pre-1.0**, so pin an exact version in `go.mod` and read the release notes before upgrading — the API still changes.
- The pattern: create a server, register a tool with a typed input struct and a handler, then run it over a transport (`mcp.StdioTransport`).
- **Resources:** the SDK's `docs/` directory and `README`, and `modelcontextprotocol.io` for the protocol concepts (tools, resources, transports).
- **Checkpoint:** a test client (the SDK ships examples) can list your tool and call it.

## Mission 2 — Expose Sylvy's data as tools

Design a small, safe tool surface over the agent and the Phase 2 triage tool, for example:

- `list_recent_events` — the latest alerts the agent emitted.
- `get_process(pid)` — current `/proc` details for a PID.
- `list_listening_ports` — the current port table with owners.
- `triage_binary(path)` — invoke your Python triage tool and return its JSON.

Think about the boundary: validate every input (a PID is a number, a path must be absolute and must exist), never pass untrusted strings to a shell, and expose only what a caller needs. This is the security-engineering lesson of the phase.

**Checkpoint:** from a client you can call `triage_binary` on a dropped payload and get structured results back over MCP.

## Mission 3 — Add an HTTP transport

Add a streamable HTTP transport alongside stdio so the Python layer (Phase 5) and desktop AI clients can connect over the network. Keep it bound to localhost on the VM.

**Resources:** the SDK's transport documentation.

**Checkpoint:** the same tools work whether a client connects over stdio or HTTP.

## How to know Phase 3 is done

A client — a script or an AI assistant — can discover your tools and use them to answer "is anything suspicious running right now?" entirely through the MCP interface, with all input validated at the boundary.
