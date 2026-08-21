# AGENTS.md

Conventions for any AI agent or contributor working in this repository.

## Creating GitHub Issues

Issues in this repo follow a parent/child hierarchy. Follow these rules exactly.

### Before creating any issue

1. **Draft the title and body first and get explicit confirmation.** Never create an issue without showing the draft.
2. **Ask whether it is a parent task or a child task.** Never assume.
3. **If it is a child task, ask which parent issue number it belongs to.**

### Titles

- Parent issues: a plain descriptive title.
- Child issues: prefix the title with the parent issue number in brackets.
  ```
  [#22] Add local LLM option for text post-processing to eliminate API latency
  ```

### Labels

Every issue gets `parent` or `child`, plus any topical labels that apply. Topical labels are not mutually exclusive with the hierarchy labels.

| Label | Purpose |
| --- | --- |
| `parent` | Parent/epic issue |
| `child` | Sub-issue of a parent task |
| `ux` | User experience improvements |
| `payments` | Payment gateway / monetization work |
| `performance` | Performance improvements — latency, speed, resource usage |

Create a new topical label only when the repository owner asks for one.

### Linking a child to its parent

Creating the issue with a `[#N]` prefix and a `child` label is not enough — also register it as a GitHub sub-issue so the parent shows the nested checklist:

```bash
gh api repos/prithvi-bommu/uttr/issues/<PARENT>/sub_issues --method POST -F sub_issue_id="$(gh api repos/prithvi-bommu/uttr/issues/<CHILD> --jq '.id')"
```

The endpoint requires the numeric `.id`, not the GraphQL `node_id`. Passing `node_id` returns a 422.

Note that GitHub's issue list is flat — sub-issues still appear alongside their parents. The `[#N]` title prefix and the `parent`/`child` labels are what make the hierarchy readable in that list, which is why both are required.

### Body structure

Create issues with `gh issue create --repo prithvi-bommu/uttr`, using a heredoc for the body. Typical sections:

- `## Summary` — what and why, in a couple of sentences.
- `## Current Behavior` / `## Problem` — for bugs and improvements.
- `## Requirements` or `## Areas to Investigate` — a `- [ ]` checklist so items can be added and reordered as priorities shift.
- `## Success Criteria` — how we know it is done, where measurable.
- `## Open Questions` — unresolved decisions, rather than guessing at them.

## Payment gateway (Issues #27, #51)

Uttr gates premium features behind a RevenueCat **Web Billing** subscription.
Uttr is distributed as a Developer ID DMG, not through the Mac App Store, so
StoreKit in-app purchase is unavailable — checkout happens in the browser and
entitlements arrive through a redemption link opened on the user's Mac.

Entitlement plumbing lives in the shared
[entitlement-kit-swift](https://github.com/prithvi-bommu/entitlement-kit-swift)
package (pinned to `0.2.0`). Business logic depends on the `PaymentGateway`
protocol, not on RevenueCat or EntitlementKit directly.

### Free vs premium features

| Free (always available) | Premium (Uttr Pro) |
| --- | --- |
| Hold-to-talk dictation | AI Content mode (⌥A hotkey) |
| Local polish (rule-based, offline) | Cloud Text Polish (OpenAI / Anthropic) |

### Subscription plans

Three plans configured in RevenueCat and `PricingConfig.json`, all
auto-renewable with a 3-day free trial:
- **Weekly** (`weekly`)
- **Monthly** (`monthly`)
- **Annual** (`annual`)

Uttr does not sell a lifetime plan — deliberately. `SubscriptionStatus` still
carries a `.lifetime` case with no associated plan, kept as the fallback for
an active entitlement RevenueCat reports with no expiration date (e.g. a
dashboard-granted comp), independent of the sellable plan catalog above.

The entitlement identifier is **`uttr_pro`** and must match the RevenueCat
dashboard exactly.

### Key files

| File | Purpose |
| --- | --- |
| `Uttr/Domain/Subscription.swift` | `SubscriptionStatus`, `SubscriptionPlan`, value types |
| `Uttr/Domain/PaymentGateway.swift` | Provider-agnostic protocol |
| `Uttr/Domain/PricingConfig.swift` | Config model + bundle loader |
| `Uttr/Resources/PricingConfig.json` | API key, product IDs, entitlement ID, web billing config |
| `Uttr/Services/EntitlementKitPaymentGateway.swift` | EntitlementKit adapter (only file importing RevenueCat) |
| `Uttr/Services/SubscriptionStatusMapper.swift` | `EntitlementStatus` → `SubscriptionStatus` |
| `Uttr/App/AppDelegate.swift` | Routes redemption callback URLs |
| `Uttr/Features/Paywall/UttrPaywallView.swift` | Plan picker that hands off to the browser |
| `Uttr/Features/Settings/SubscriptionSettingsView.swift` | Subscription management tab |

### Purchase flow

1. The paywall calls `purchase(_:)`, which builds an anonymous Web Purchase
   Link and opens it with `NSWorkspace`.
2. `purchase(_:)` returns `.pending`. **Opening checkout is never a grant.**
3. The customer pays, then opens the emailed redemption link on their Mac.
4. macOS routes `rc-889e05dd40://…` to `AppDelegate.application(_:open:)`, which
   forwards to `handleCallbackURL(_:)`. That scheme is generated by the RevenueCat
   dashboard and must stay identical in `callbackScheme` (`PricingConfig.json`) and
   `CFBundleURLSchemes` (`Uttr/Resources/Info.plist`) — if the two ever disagree,
   every redemption is dropped with no error.
5. RevenueCat confirms the entitlement, `customerInfoStream` updates, and the
   gating layers unlock.

`.onOpenURL` is **not** used: the root scene is a `MenuBarExtra` and the app is
`LSUIElement`, so SwiftUI URL delivery is unreliable. Always route through
`AppDelegate`.

### Feature gating architecture

Premium features are blocked at four independent levels:

1. **Settings UI** — `AIContentSettingsView` and `PolishSettingsView` show a
   locked premium banner instead of the enable toggle.
2. **Hotkey dispatch** — `AppEnvironment.handleHotkeyEvent(.aiHotkeyDown)`
   checks `hasPremiumAccess` before processing.
3. **Provider closures** — `aiProvider` and `cloudPolisherProvider` return `nil`
   without premium access.
4. **Menu bar** — shows "✦ Upgrade to Uttr Pro…" for free-tier users.

The deepest gate (provider closures) is authoritative.

### Building and testing

| API key prefix | Build config | Behavior |
| --- | --- | --- |
| `test_` | **Debug** | Works normally — no force-close |
| `test_` | **Release** | SDK force-closes the app to protect test purchases |

During development, always use a Debug build with the `test_` key.
`Scripts/verify-release-pricing-key.sh` rejects `test_` keys and empty web
billing URLs before a release DMG is built.

### Known limitations

- **No in-app restore.** Web Billing has no receipt. Recovery on a second Mac
  runs through the redemption link emailed to the billing address; the app only
  links out to the customer portal.
- **Prices ship with the build.** Web Billing products do not expose StoreKit
  localized pricing, so `displayPrices` in `PricingConfig.json` is the source.
  A price change requires an app update.
- **Unlimited devices.** EntitlementKit deliberately enforces no device cap.
- **Installation identity is `UserDefaults`-backed** and does not survive
  deleting the app; a reinstalling customer must redeem their email link again.
- **Offline cache trust** — `com.uttr.cachedEntitlementStatus` is plain
  `UserDefaults` and user-editable. It supports offline availability, not
  tamper-proof entitlement storage; RevenueCat is authoritative when reachable.
  The StoreKit-era `com.uttr.cachedSubscriptionStatus` key is abandoned rather
  than reused: it stores a different JSON shape, and decoding it as an
  `EntitlementStatus` would silently downgrade an offline subscriber to `.free`.

## Commits and pull requests

Do not add "Generated with" attribution, co-author trailers, or tool branding to commits, pull requests, or code.
