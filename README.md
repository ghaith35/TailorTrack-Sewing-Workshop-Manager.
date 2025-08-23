# TailorTrack — Sewing Workshop Manager (Flutter)

Orders, measurements, inventory, and billing for tailoring & embroidery shops — built with **Flutter** for **mobile & desktop**. Fast, offline-friendly, and ready for teams.

![Flutter](https://img.shields.io/badge/Flutter-stable-blue) ![Dart](https://img.shields.io/badge/Dart-3.x-informational) ![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-success) ![License](https://img.shields.io/badge/License-MIT-green)

> If you’re a tailor, embroidery shop, or small atelier: TailorTrack centralizes **customers**, **measurements**, **orders**, **materials**, and **invoices** — with analytics and role-based access. This README doubles as **developer docs** so you can ship confidently.

---

## Table of Contents
- [✨ Features](#-features)
- [🏗 Architecture](#-architecture)
- [🗃 Data Model](#-data-model)
- [🌐 Backend API (optional)](#-backend-api-optional)
- [🚀 Quick Start](#-quick-start)
- [⚙️ Configuration](#%EF%B8%8F-configuration)
- [▶️ Run](#%EF%B8%8F-run)
- [📦 Build & Release](#-build--release)
- [🧪 Testing & Quality](#-testing--quality)
- [🌍 i18n & Theming](#-i18n--theming)
- [🔐 Security Notes](#-security-notes)
- [🗺 Roadmap](#-roadmap)
- [🤝 Contributing](#-contributing)
- [📝 License](#-license)
- [👤 Author](#-author)

---

## ✨ Features

**Operations**
- 👥 **Customers & CRM** — profiles, contact info, multi-measurement profiles, order history
- 📏 **Measurements** — body measurements per garment; templates for common styles
- 🧵 **Orders & Jobs** — garments/embroidery jobs, priorities, due dates, notes, attachments
- 📦 **Inventory** — fabrics, threads, accessories; suppliers; stock in/out; low-stock alerts
- 💰 **Pricing & Quotes** — item rules, automatic totals, taxes/discounts, PDFs
- 🧾 **Invoices & Payments** — receipts, statuses (paid/partial/unpaid), export/share
- 🔎 **Search & Filters** — by customer, phone, order no., status, due date
- 📈 **Analytics** — daily/weekly sales, best sellers, outstanding balances

**Team & UX**
- 👤 **Roles & Permissions** — admin / cashier / tailor (optional)
- 🚦 **Status Timeline** — ordered → cutting → sewing → ready → delivered
- 🔁 **Offline-first** — local cache; sync when online (conflict-safe rules)
- 🖥 **Multi-platform** — Android, iOS, Windows, macOS, Linux
- 🧩 **Modular** — clean layers; easy to replace local DB or API client

> Drop screenshots under `assets/screens/` and reference them here:
>
> `![Dashboard](assets/screens/dashboard.png)`  `![Orders](assets/screens/orders.png)`

---

## 🏗 Architecture

A clean, layered architecture that keeps UI simple and business logic testable.

```
presentation/         # Widgets, routing, theming, localization
application/          # State mgmt (e.g., Riverpod/BLoC), use-cases, validators
domain/               # Entities (Customer, Order, Item, Invoice, Measurement)
infrastructure/       # Data sources (local DB, REST API), repositories, mappers
```

**Suggested packages (swap to your favorites):**
- Routing: `go_router`
- State: `riverpod` / `flutter_riverpod` (or `bloc`)
- HTTP: `dio` (or `http`)
- Local DB: `drift` / `isar` / `objectbox` / `sqflite`
- Serialization: `json_serializable`, `freezed`
- PDF: `printing` / `pdf`
- DI: `riverpod` or `get_it`

**Why this matters**
- 🚫 UI not tied to networking or SQL
- ✅ Testable business rules
- 🔁 Easy to swap storage layers later

---

## 🗃 Data Model

Core entities:
- **Customer**(id, name, phone, address, notes)
- **Measurement**(id, customerId, garmentType, values[map], updatedAt)
- **Order**(id, customerId, items[list], status, dueDate, total)
- **OrderItem**(id, orderId, productId, qty, price)
- **Product**(id, name, type[garment/embroidery/material], price, sku)
- **InventoryTxn**(id, productId, type[in/out], qty, cost, ref)
- **Invoice**(id, orderId, subtotal, tax, discount, total, status, issuedAt)
- **Payment**(id, invoiceId, amount, method, paidAt)

**Example SQL seeds (if using a server)**
- `sql/designbase.sql` — tailoring tables
- `sql/embroiderybase.sql` — embroidery specifics
- `sql/sampledata.sql` — demo data

> Keep client models in `/domain`, and mappings in `/infrastructure/mappers`. Avoid SQL or JSON parsing inside widgets.

---

## 🌐 Backend API (optional)

TailorTrack runs **local-only** or with a **remote API** (recommended for teams).

**Base URL**
- Prod: `https://api.yourdomain.com`
- Dev: `http://localhost:8000/api` (Laravel default)

**Sample endpoints (Laravel-style)**
```
GET    /customers?query=ali
POST   /customers
GET    /customers/{id}
PUT    /customers/{id}
DELETE /customers/{id}

GET    /orders?status=pending
POST   /orders
PUT    /orders/{id}/status
GET    /invoices?status=unpaid
POST   /payments
```

**Auth**
- Token-based (Laravel Sanctum/JWT); store tokens securely (do **not** hardcode).

**CORS**
- Allow only your app origins in production.

---

## 🚀 Quick Start

### Prerequisites
- Flutter **stable** (3.x)
- Android Studio/Xcode for mobile, or desktop toolchains
- (Optional) MySQL/PostgreSQL for a remote backend

### Clone & install
```bash
git clone https://github.com/ghaith35/sewing_app.git
cd sewing_app
flutter pub get
```

### Configure data source
Create `lib/core/config.dart` (or use a provided example) and set flags:

```dart
// lib/core/config.dart
const bool kUseRemoteApi = false; // set true to enable server mode
const String kApiBaseUrl = "http://localhost:8000/api"; // change per environment
```

> For secrets, use platform env or secure storage — never commit secrets.

---

## ▶️ Run

**Android/iOS:**
```bash
flutter run -d android     # or -d ios (requires macOS + Xcode)
```

**Windows/macOS/Linux:**
```bash
flutter config --enable-windows-desktop   # or --enable-macos-desktop / --enable-linux-desktop
flutter run -d windows                    # or macos / linux
```

**With runtime config (dart-define):**
```bash
flutter run \
  --dart-define=USE_REMOTE_API=true \
  --dart-define=API_BASE_URL=http://localhost:8000/api
```

---

## 📦 Build & Release

**Android (APK/AAB):**
```bash
flutter build apk --release
flutter build appbundle --release
```

**Windows/macOS/Linux:**
```bash
flutter build windows   # or macos / linux
```

**Versioning**
- Update `pubspec.yaml` → `version: 1.0.0+1`

---

## 🧪 Testing & Quality

**Commands**
```bash
dart analyze
flutter test --coverage
```

**Example widget test**
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots Home screen', (tester) async {
    // TODO: pumpWidget(App()); and expectations
  });
}
```

**Suggested tooling**
- Lints: `flutter_lints`
- Format: `dart format .`
- Golden tests for critical screens
- Integration tests with `integration_test`

**CI (GitHub Actions) — `.github/workflows/flutter-ci.yml`**
```yaml
name: Flutter CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: 'stable' }
      - run: flutter pub get
      - run: dart analyze
      - run: flutter test --coverage
```

---

## ⚙️ Configuration

**Environment via dart-define**
```bash
# Local demo
flutter run --dart-define=USE_REMOTE_API=false

# Server mode
flutter run \
  --dart-define=USE_REMOTE_API=true \
  --dart-define=API_BASE_URL=http://localhost:8000/api
```

**Local DB (option A)**
- Use `drift` or `sqflite`. Keep DAOs in `infrastructure/local`.
- Example migrations: `drift_dev` → `build_runner`.

**Remote API (option B)**
- Use `dio` interceptors for auth & logging.
- Retry with exponential backoff on 5xx.

**Sync Strategy (if both)**
- Queue offline mutations → replay when online.
- Conflict rule: **server-wins** or **last-write-wins** (document your choice).

---

## 🌍 i18n & Theming

**Localization**
- Add AR/EN (or your languages) under `l10n/`
- Use Flutter’s `flutter_localizations` & ARB files

**Theming**
- Material 3; light/dark palettes
- Persist theme choice in local storage

**Accessibility**
- Large fonts, sufficient contrast, talkback/VoiceOver labels
- Tap targets ≥ 44x44px, keyboard navigation on desktop

---

## 🔐 Security Notes

- Never hardcode secrets or tokens in the app
- Use HTTPS in production; secure cookies or token headers
- Apply **least-privilege** DB accounts on the server
- Regular backups (CSV/SQL) and audit logs for admin actions

---

## 🗺 Roadmap

- [ ] Role-based security across all screens
- [ ] Barcode/QR for items & job tickets
- [ ] Supplier POs & GRNs (purchase & receiving)
- [ ] SMS/WhatsApp pickup reminders
- [ ] Multi-branch support with location-aware analytics
- [ ] Full offline sync with conflict resolution (server-wins or CRDT)
- [ ] Comprehensive integration tests + golden tests

---

## 🤝 Contributing

1. Fork and create a feature branch: `git checkout -b feat/your-feature`
2. Keep PRs small and focused; include screenshots for UI changes
3. Run **tests** and **analyzers** before pushing
4. Fill the PR template with **test plan** and **screenshots**

**Issue labels**
- `good first issue` — easy wins
- `help wanted` — community contributions welcome

---

## 📝 License

MIT © 2025 Ghaith Tayem

---

## 👤 Author

**Ghaith Tayem** — Full-stack & AI Engineer  
GitHub: https://github.com/ghaith35  
Open to **remote or onsite**
