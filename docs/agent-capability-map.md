# Agent Capability Map

Every important Remnant UI action should either have a local CLI/MCP equivalent or be intentionally user-only.

| UI Action | UI Location | Agent Capability | Status |
| --- | --- | --- | --- |
| View dashboard totals | Dashboard | `snapshot`, `reports:summary` | Done |
| Drill into monthly spend bars | Dashboard | `reports:summary`, `expenses:list` filtered by agent | Done |
| Drill into category spend | Dashboard | `reports:summary`, `expenses:list` filtered by agent | Done |
| List review issues | Review Inbox | `review:list` | Done |
| Review agent proposals | Review Inbox | `proposals:list`, `proposals:read` | Done |
| Apply proposal | Review Inbox | User-only in app | User-only |
| Reject proposal | Review Inbox | User-only in app | User-only |
| Edit expense fields | Expenses / Review Inbox | `proposals:create` | Proposal-only |
| Mark reviewed / ignored | Expenses / Review Inbox | `proposals:create` | Proposal-only |
| Attach receipt | Expense Form / Imports | `proposals:create` receipt-match payload | Proposal-only |
| Preview receipt visually | Expense Form / Imports | User-only in app | User-only |
| Import CSV / receipts / `.eml` | Imports | User-only file selection | User-only |
| Create draft expense from receipt | Imports | `proposals:create` draft-expense payload | Proposal-only |
| Create vendor rule | Settings | `proposals:create` vendor-rule payload | Proposal-only |
| Archive vendor rule or dimension | Settings | User-only in app | User-only |
| Create backup | Settings | `backup:propose` | Proposal-only |
| Restore backup | Settings | User-only in app | User-only |
| Export audit package | Reports | `audit:propose` | Proposal-only |
| Read raw receipt files or OCR text | Receipt Vault | Not exposed by default | Deferred |
| Start local MCP server | Terminal | `remnantctl mcp serve` | Done |

Agent proposal payloads must include enough `beforeJSON` state for stale-change validation before the app applies them.
