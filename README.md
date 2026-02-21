# Remnant

**Know what remains.**

Remnant is a privacy-first personal finance tracker for iOS. It digitizes the manual bill-paying workflow — enter income, pay bills, track what's left — without connecting to banks or sharing data with third parties.

Built with SwiftUI for iOS 26+ with a dark-first design.

## Features

**Free**
- Manual balance tracking — enter paychecks, record payments, see what remains
- Bill management — monthly, annual, weekly, biweekly, quarterly, and one-time
- Dashboard with balance summary and upcoming bills
- iCloud sync via CloudKit (encrypted, private container)

**Remnant+ (Premium)**
- Unlimited accounts and bills
- Planning mode — simulate payments before committing
- Year view — 12-month spreadsheet grid of all bills
- Analytics — category breakdown and monthly spending trends
- Bill reminders with configurable lead time
- CSV export by year
- Custom categories with icons and colors

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (iOS 26+) |
| Data | SwiftData + CloudKit |
| State | `@Observable` pattern |
| Subscriptions | StoreKit 2 |
| Charts | Swift Charts |
| Notifications | UserNotifications (local) |
| Language | Swift 6 |
| Build | XcodeGen |

## Project Structure

```
Remnant/
├── App/                  # Entry point, environment, root view
├── Models/               # SwiftData @Model classes
├── Services/             # Business logic layer
│   ├── AccountService
│   ├── BillService
│   ├── PaymentService
│   ├── IncomeService
│   ├── CategoryService
│   ├── ReminderService
│   ├── SubscriptionService
│   └── ExportService
├── Views/
│   ├── Dashboard/        # Balance summary, record payments
│   ├── Bills/            # List, detail, form
│   ├── Planning/         # Payment simulation
│   ├── Analytics/        # Monthly view, year view, charts
│   ├── Income/           # Sources and entries
│   ├── Settings/         # Accounts, categories, subscription
│   ├── Onboarding/       # First-launch flow
│   └── Components/       # BillRow, CurrencyField, PremiumGate
├── Resources/            # Colors, design tokens
├── Extensions/           # Date + Decimal helpers
└── Utilities/            # Logging
```

## Architecture

Remnant uses a service-based architecture with `AppEnvironment` as the central dependency container. All services are `@Observable` classes injected through the SwiftUI environment.

Data flows through SwiftData models synced automatically via CloudKit to a private iCloud container — no server, no third-party backend.

## Pricing

| Tier | Price | Includes |
|------|-------|----------|
| Free | $0 | 1 account, 15 bills, dashboard, current month |
| Remnant+ Monthly | $3.99/mo | Unlimited everything, all premium features |
| Remnant+ Annual | $29.99/yr | Same as monthly, save 37% |

## Requirements

- iOS 26.0+
- Xcode 26+
- Swift 6

## Setup

1. Clone the repository
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed: `brew install xcodegen`
3. Run `xcodegen generate` (or open the existing `.xcodeproj`)
4. Set your development team in Signing & Capabilities
5. Configure the CloudKit container: `iCloud.com.borrowedfire.remnant`
6. Build and run

## Privacy

Remnant collects no user data. All financial information stays on-device and in your private iCloud container. No analytics, no tracking, no bank connections.

See [Privacy Policy](https://borrowedfire.com/privacy-policy/) and [Terms of Service](https://borrowedfire.com/terms-of-service/).

## License

Copyright 2025-2026 Borrowed Fire LLC. All rights reserved.
