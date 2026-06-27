# Contributing to Remnant

Remnant is an MIT-licensed, local-first macOS app for solo-business expense review, receipt handling, and accountant-ready export.

Borrowed Fire LLC maintains the official app, but the project is intended to be useful outside Borrowed Fire. Contributions are welcome when they preserve the local-first privacy model and the current 1.0 scope.

## Privacy Rules for Issues and Pull Requests

Do not post real financial data in public issues, pull requests, screenshots, logs, or fixtures.

Before sharing reproduction material, redact or replace:

- Receipt images and PDFs
- Account, routing, card, tax, invoice, or customer numbers
- Business addresses, emails, phone numbers, and legal names
- Real merchant transaction rows when the merchant/date/amount combination is sensitive
- Tax documents, bank statements, and payment processor exports

Use small synthetic CSV rows, fake receipts, and fake merchant names whenever possible. If a bug requires private data to diagnose, open a minimal public issue first and ask where to send a sanitized private sample.

## Scope

Good 1.0 contributions:

- Local CSV import and review improvements
- Receipt/document vault safety
- Local OCR parsing improvements
- Category, tax-bucket, account, vendor, client, or project reporting improvements
- Backup/restore integrity
- Accountant export quality
- macOS utility UI improvements
- Tests and privacy/scope checks

Out of scope for 1.0:

- Bank feeds or Plaid-style integrations
- Gmail, Wave, or hosted API connectors
- Cloud sync or hosted backends
- Invoices, time tracking, payroll, or full reconciliation
- Analytics, tracking SDKs, or subscription gates

Large accounting features need an accepted issue or RFC before implementation.

## Pull Request Expectations

- Keep changes narrowly scoped.
- Add or update tests for behavior changes.
- Preserve local-only behavior: no network calls, sync, analytics, bank linking, CloudKit, StoreKit, or backend dependencies.
- Do not weaken redaction, import, export, backup, or document-link safety.
- Run the relevant verification commands before requesting review.

Useful commands:

```sh
xcodebuild -project Remnant.xcodeproj -scheme Remnant -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
./script/build_and_run.sh --verify
```

## Contributor License

Remnant uses MIT inbound=outbound contribution terms. By submitting a pull request, you agree that your contribution is provided under the MIT License.
