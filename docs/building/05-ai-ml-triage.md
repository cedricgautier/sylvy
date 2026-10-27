# Roadmap Lesson 5 — AI/ML triage layer

> Supports **Phase 5**. Python, with a local model. The differentiator: reason about alerts offline. Guidance and resources only.

## What you are building and why

A pipeline that consumes your MCP server, enriches each alert with analysis, asks a **local** language model to assess it, and — crucially — is **evaluated**, not just demoed. "I used an LLM" is common; "I built and measured an LLM workflow for security triage" is what the job asks for. Everything runs on your machine, so no data leaves the VM.

## Set-up — a local model via Ollama

Install Ollama and pull a small Llama model. Small models are enough for structured triage and run on modest hardware; you can swap in a larger one later.

- **Resources:** the Ollama documentation (install, `ollama pull`, the local HTTP API); the official MCP **Python** SDK (`mcp`) to act as a client of your Go server.
- **Checkpoint:** you can send a prompt to the local model from Python and get a response, fully offline.

## Mission 1 — LLM-assisted triage with structured output

For each alert: call `triage_binary` (and other tools) on your MCP server, assemble the facts, and ask the model for a plain-language risk summary plus a suggested **MITRE ATT&CK** technique ID — returned as **strict JSON** you can parse, not prose.

- Enforce the schema: define it with `pydantic` and either use constrained/JSON-mode decoding or validate and re-ask on failure.
- **Resources:** MITRE ATT&CK (the technique matrix); `pydantic` docs; your model's JSON/format-enforcement options.
- **Checkpoint:** feeding one alert yields a valid JSON verdict with a technique ID every time, across many runs.

## Mission 2 — Ground it with retrieval

Build a small corpus (ATT&CK technique descriptions, notes on known indicators). Before asking the model, retrieve the most relevant entries and include them, so answers are grounded rather than guessed.

- **Resources:** any lightweight local embedding model (via Ollama or `sentence-transformers`) and a simple vector store, or even keyword retrieval to start.
- **Checkpoint:** the model's verdicts cite the retrieved technique rather than inventing one, and quality visibly improves versus no retrieval.

## Mission 3 — An evaluation harness

This is the mission that matters most. Run the pipeline over your test harness's labelled scenarios (the benign processes and the A1–A4 attacks) and measure precision and false-positive rate.

- **Resources:** basic classification metrics (precision, recall, F1); keep a fixed labelled set so runs are comparable.
- **Checkpoint:** you can quote a false-positive number and show it change when you alter the prompt, the retrieval, or the model.

## Mission 4 — A non-LLM second opinion (classical ML)

Train a simple anomaly detector (e.g. an isolation forest in `scikit-learn`) on a baseline of normal process behaviour, and compare its flags with the LLM's. This teaches the data-analysis side and gives a cheap, explainable check.

- **Resources:** the `scikit-learn` user guide (IsolationForest, preprocessing).
- **Checkpoint:** the model flags a clearly anomalous process and stays quiet on normal ones, and you can describe the features you used.

## How to know Phase 5 is done

An alert flows end to end — agent → MCP → Python → local model → graded, ATT&CK-tagged verdict — and you have a measured false-positive rate you can defend and improve.
