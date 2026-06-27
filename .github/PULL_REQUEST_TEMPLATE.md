## Summary

Describe the focused change.

## Verification

- [ ] `xcodebuild -project Remnant.xcodeproj -scheme Remnant -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test`
- [ ] `./script/build_and_run.sh --verify` when app launch or UI behavior changes
- [ ] Privacy/scope scan when touching imports, documents, networking-adjacent code, or project docs

## Privacy and Scope

- [ ] No real financial data, receipts, account numbers, or tax documents are included.
- [ ] No network calls, hosted sync, analytics, bank linking, CloudKit, StoreKit, or backend dependency was added.
- [ ] This stays within the accepted issue/RFC scope.
