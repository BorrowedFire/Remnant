# Remnant

**Know what remains.**

A privacy-first personal finance tracker for iOS. Remnant digitizes the manual bill-paying workflow — enter income, pay bills, track what's left — without connecting to banks or sharing data with third parties.

## Features

- **Manual balance tracking** — enter paychecks, record payments, see what remains
- **Bill management** — track monthly, annual, weekly, and one-time bills with due dates and categories
- **Planning mode** — simulate payments before committing to see projected balance (Premium)
- **Year view** — spreadsheet-style 12-month grid of all bills and payments (Premium)
- **Analytics** — category breakdown donut chart and monthly spending trend (Premium)
- **Bill reminders** — local notifications with configurable lead time (Premium)
- **CSV export** — export payment history by year (Premium)
- **Custom categories** — create categories with icons and colors (Premium)
- **iCloud sync** — encrypted CloudKit sync across devices
- **Dark-first design** — built with iOS 26 Liquid Glass

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (iOS 26+, Liquid Glass) |
| Data | SwiftData with `@Observable` |
| Sync | CloudKit (automatic via SwiftData) |
| Notifications | UserNotifications (local) |
| Subscriptions | StoreKit 2 |
| Charts | Swift Charts |
| Architecture | Services + AppEnvironment |

## Project Structure

```
Remnant/
├── App/                  # App entry point, environment, content view
├── Models/               # SwiftData @Model classes
├── Services/             # Business logic (Account, Bill, Payment, etc.)
├── Views/
│   ├── Dashboard/        # Balance summary, upcoming bills
│   ├── Bills/            # Bill list, detail, form
│   ├── Planning/         # Payment simulation
│   ├── Analytics/        # Monthly view, year view, charts
│   ├── Income/           # Income sources and entries
│   ├── Settings/         # Accounts, categories, subscription, export
│   ├── Onboarding/       # First-launch flow
│   └── Components/       # Reusable views (BillRow, CurrencyField, etc.)
├── Resources/            # Colors, design tokens
├── Extensions/           # Decimal+Currency, Date+Helpers
└── Utilities/            # Logging
```

## Subscription Tiers

### Free
- 1 account, up to 15 bills
- Dashboard, payment recording, current month view

### Remnant+ ($3.99/month or $29.99/year)
- Unlimited accounts and bills
- Planning mode, full history, year view
- Analytics charts, CSV export, custom categories, bill reminders

## Requirements

- iOS 26.0+
- Xcode 26+
- Swift 6

## Setup

1. Clone the repository
2. Open `Remnant.xcodeproj` in Xcode
3. Set your development team in Signing & Capabilities
4. Configure the CloudKit container (`iCloud.com.borrowedfire.remnant`)
5. Build and run

## License

Copyright 2025-2026 Borrowed Fire LLC. All rights reserved.
