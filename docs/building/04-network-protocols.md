# Roadmap Lesson 4 — Network protocols

> Supports **Phase 4**. Go. Give the agent eyes on the network and learn protocols at the byte level. Guidance and resources only.

## What you are building and why

Backdoors and data exfiltration happen over the network. To see them you need to read traffic structure, not just the connection table you already parse for F3. Doing the parsing yourself is how you actually learn TCP/IP, DNS and TLS — concepts interviewers probe directly.

## Mission 1 — Capture connection metadata

Start from what you know: the connection states in `/proc/net/tcp`. Then step up to live capture with an `AF_PACKET` socket, which hands you raw frames.

- **Resources:** `man 7 packet`; the `gopacket` library (you may hand-roll simple parsers first for the learning, then use `gopacket` for robustness).
- **Checkpoint:** you can list outbound connections with their remote address and owning process.

## Mission 2 — Decode the layers by hand

Parse one captured packet from the bottom up: Ethernet → IPv4/IPv6 → TCP/UDP. Learn where the addresses, ports and flags live.

- **Resources:** the relevant RFCs are dense; a good TCP/IP reference or a "packet structure" diagram is faster to start. Validate your parsing against **Wireshark** viewing the same traffic.
- **Checkpoint:** for a captured packet, your code prints source/destination IP and port and the TCP flags, and they match Wireshark.

## Mission 3 — Two application protocols that reveal intent

- **DNS:** parse a query to catch exfiltration-by-DNS (data smuggled in hostnames). Learn the DNS message format (header, question, answer).
- **TLS ClientHello:** the **SNI** field reveals the destination hostname even though the rest is encrypted. Parse enough of the handshake to extract it.
- **Resources:** RFC 1035 (DNS) and RFC 8446 (TLS 1.3) for reference; Wireshark to see the fields laid out.
- **Checkpoint:** your agent logs outbound connections with a resolved domain (from DNS or SNI), and you can read a captured handshake field by field in Wireshark.

## Mission 4 — Expose it

Add a `recent_connections` tool to your Phase 3 MCP server so the AI layer can reason about network activity too.

## How to know Phase 4 is done

The agent reports outbound connections with destination domains, you can parse a packet by hand and confirm each field in Wireshark, and you can explain the difference between what you can and cannot see inside a TLS session.
