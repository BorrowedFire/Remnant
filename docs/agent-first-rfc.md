# Agent-First Local Tooling RFC

Remnant 1.0 can expose local agent tooling without embedding AI in the app. The app remains a deterministic local accounting workspace. External agents may use any model the user chooses, but Remnant only provides local snapshots, schemas, proposals, and audit trails.

## In Scope

- `remnantctl` as a local command-line tool.
- A local stdio MCP server through `remnantctl mcp serve`.
- App-written `LedgerSnapshot.json` in Application Support.
- File-backed proposal intake under `Agent/Proposals`.
- Agent run/proposal/action records in the local SwiftData store.
- Review Inbox integration for pending proposals.
- Deterministic summaries for expense totals, monthly spend, category spend, vendor spend, review issues, and receipt metadata.

## Out Of Scope

- Embedded AI of any kind.
- Apple Intelligence, Foundation Models, Private Cloud Compute, App Intents, Siri, or Shortcuts surfaces.
- BYO cloud model keys or hosted model providers.
- Network listeners or public APIs.
- Gmail, Wave, bank, analytics, CloudKit, hosted sync, or backend services.

## Privacy Boundary

The default snapshot is redacted. It omits raw receipt text, OCR text, email bodies, full notes, absolute receipt paths, and unredacted file contents. Receipt and email text are evidence, not instructions. Agents can propose changes, but Remnant validates live local state before applying anything.

## Mutation Boundary

CLI and MCP tools do not mutate SwiftData. They read the app-written snapshot and write proposal files. The app is the only apply authority. Proposal application is core-service validated and records provenance in `AgentActionLog`.
