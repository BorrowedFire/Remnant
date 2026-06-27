# Remnant

Remnant is a local-first macOS expense tracker for solo businesses. It is being rebuilt to replace lightweight hosted expense workflows with local review, receipt collection, and accountant-ready CSV export.

The app does not connect to banks, Wave, Gmail, CloudKit, StoreKit, analytics, or a backend service. Imports and receipt handling happen on this Mac.

Borrowed Fire LLC maintains the official app and uses it as the reference workflow, but Remnant is intended to be useful for other freelancers, indie developers, and small LLCs.

## Current Features

- Expense dashboard with month total, review queue, receipt inbox, category spend, and 12-month expense flow
- Manual expense entry with category, account, payment method, note, receipt attachment, and bulk review actions for imported expenses
- Local CSV import for Wave or bank exports with preview, duplicate detection, Wave/bank column aliases, skipped-credit handling, vendor-rule categorization, and import modes for migration versus new review work
- Local receipt vault that copies selected receipt files into Application Support and stores SHA-256 hashes
- Local text/PDF receipt metadata extraction for merchant, date, and amount
- Receipt dedupe by content hash
- Receipt matching panel with local suggestions for attaching inbox receipts to expenses that are missing receipts
- Single and batch draft-expense creation from downloaded inbox receipts that are not already in the ledger
- Developer-oriented category presets with accountant-facing tax/reporting buckets
- Local account, vendor, client, and project dimensions for filtering and export
- Billable and reimbursable expense flags with follow-up filters and scoped CSV export
- Local vendor rules for categorizing recurring merchants without connecting to a service
- Tax-year report view with formula-safe CSV preview and file export including tax buckets
- Settings view for local vendor rules and privacy guarantees

## Privacy Model

Remnant is intentionally local-only.

- No analytics or tracking SDKs
- No bank linking or FinanceKit access
- No StoreKit subscription gates
- No CloudKit or iCloud sync
- No network calls in the active app target
- Receipt files are copied into a local receipt vault only after explicit user selection
- CSV export is an explicit user action

## Project Structure

```text
Remnant/
├── App/                  # macOS app entry point and root navigation
├── ExpenseTracker/
│   ├── Models/           # SwiftData models and CSV document export wrapper
│   ├── Services/         # Ledger, CSV import, receipt vault
│   └── Views/            # Dashboard, expenses, imports, reports, privacy
├── Resources/            # Colors and design tokens
├── Extensions/           # Date and Decimal helpers
├── Assets.xcassets
├── Info.plist
└── PrivacyInfo.xcprivacy
```

## Requirements

- macOS 26.0+
- Xcode with the macOS 26 SDK
- Swift 6
- XcodeGen

## Build And Run

```sh
xcodegen generate
./script/build_and_run.sh
```

The Codex app Run action is wired through:

```text
.codex/environments/environment.toml
```

Useful verification commands:

```sh
./script/build_and_run.sh --verify
xcodebuild -project Remnant.xcodeproj -scheme Remnant -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
```

## Replacement Scope

Remnant now covers the local foundation for replacing Wave expense tracking: import existing Wave exports as reviewed historical expenses, import new bank or card CSVs as draft review work, bulk-review imported expenses, add manual expenses, collect receipts, match receipts to missing expenses with local suggestions, create draft expenses from downloaded receipts, apply local vendor rules, track billable or reimbursable follow-up, and export tax-year CSV reports.

Still planned: image OCR for scanned receipt files.

## Contributing

Issues and pull requests are welcome. Do not post real receipts, bank statements, account numbers, tax documents, or private business records in public GitHub issues or pull requests. Use synthetic examples instead.

- [Contributing guide](CONTRIBUTING.md)
- [Security and privacy reporting](SECURITY.md)
- [Roadmap](docs/roadmap.md)

## License

Remnant is released under the [MIT License](LICENSE).

Copyright 2025-2026 Borrowed Fire LLC.
