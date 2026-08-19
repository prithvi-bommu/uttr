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

## Payment gateway (Issue #27)

Uttr gates premium features behind a RevenueCat-managed subscription. The architecture is intentionally provider-agnostic: business logic depends on the `PaymentGateway` protocol, not on RevenueCat directly.

### Free vs premium features

| Free (always available) | Premium (Uttr Pro) |
| --- | --- |
| Hold-to-talk dictation | AI Content mode (⌥A hotkey) |
| Local polish (rule-based, offline) | Cloud Text Polish (OpenAI / Anthropic) |

### Subscription plans

Three plans configured in RevenueCat and `PricingConfig.json`:
- **Lifetime** — one-time purchase (`lifetime`)
- **Yearly** — auto-renewable with 3-day free trial (`yearly`)
- **Monthly** — auto-renewable with 3-day free trial (`monthly`)

The entitlement identifier is **`uttr_pro`**. It must match the RevenueCat dashboard exactly; the previous wizard-generated entitlement has been deleted.

### Key files

| File | Purpose |
| --- | --- |
| `Uttr/Domain/Subscription.swift` | `SubscriptionStatus`, `SubscriptionPlan`, value types |
| `Uttr/Domain/PaymentGateway.swift` | Provider-agnostic protocol |
| `Uttr/Domain/PricingConfig.swift` | Config model + bundle loader |
| `Uttr/Resources/PricingConfig.json` | API key, product IDs, entitlement ID |
| `Uttr/Services/RevenueCatGateway.swift` | RevenueCat implementation (only file that imports RevenueCat) |
| `Uttr/Supporting/UttrProducts.storekit` | StoreKit sandbox config for local testing |
| `Uttr/Features/Paywall/UttrPaywallView.swift` | Wraps RevenueCatUI's built-in PaywallView |
| `Uttr/Features/Settings/SubscriptionSettingsView.swift` | Subscription management tab |

### Feature gating architecture

Premium features are blocked at four independent levels:

1. **Settings UI** — `AIContentSettingsView` and `PolishSettingsView` show a locked premium banner with an upgrade button instead of the enable toggle and configuration fields when the user is not subscribed.
2. **Hotkey dispatch** — `AppEnvironment.handleHotkeyEvent(.aiHotkeyDown)` checks `hasPremiumAccess` before processing.
3. **Provider closures** — `aiProvider` and `cloudPolisherProvider` in `AppEnvironment` return `nil` without premium access, so even if settings state drifts, the feature cannot execute.
4. **Menu bar** — Shows "✦ Upgrade to Uttr Pro…" for free-tier users.

The deepest gate (provider closures) is authoritative. The others are UX improvements.

### Switching to full-app gating

The current model gates specific features. To gate the entire app behind a trial-then-subscribe flow:

1. Add a `hasPremiumAccess` check at the top of `handleHotkeyEvent(.hotkeyDown)` — this blocks all dictation.
2. Present the paywall as a blocking overlay on app launch instead of a settings sheet.
3. Configure the trial duration in RevenueCat's dashboard — the domain types already support `.trial(expiresAt:)` and `.free`, so no code changes are needed for the trial flow itself.

### Building and testing

RevenueCat's SDK behaves differently depending on the build configuration and API key prefix.

| API key prefix | Build config | Behavior |
| --- | --- | --- |
| `test_` | **Debug** | Works normally — sandbox purchases, no force-close |
| `test_` | **Release** | SDK force-closes the app to protect test purchases |
| `appl_` | Either | Works normally — required for production / App Store |

**During development**, always use a Debug build with the `test_` key:

```bash
# Debug build → DMG (use this during development)
xcodebuild -project Uttr.xcodeproj -scheme Uttr -configuration Debug build -derivedDataPath build/debug
hdiutil create -volname "Uttr" -srcfolder build/debug/Build/Products/Debug/Uttr.app -ov -format UDZO build/Uttr-Debug.dmg

# Release build → DMG (only when you have a production appl_ key)
xcodebuild -project Uttr.xcodeproj -scheme Uttr -configuration Release archive -archivePath build/Uttr.xcarchive -derivedDataPath build
hdiutil create -volname "Uttr" -srcfolder build/Uttr.xcarchive/Products/Applications/Uttr.app -ov -format UDZO build/Uttr.dmg
```

**Before shipping to production**, you need to:
1. Create an App Store app in RevenueCat (requires Bundle ID, in-app purchase key configuration)
2. Replace the `test_` key with the generated `appl_` key in `PricingConfig.json`
3. Build as Release — the release workflow rejects `test_` SDK keys before it builds a DMG.

### Known limitations

- **RevenueCat CustomerCenterView** is `@available(macOS, unavailable)` — subscription management links to Apple's subscription page instead.
- **BYOK model** — subscribers currently provide their own API keys. A backend proxy to eliminate this is tracked as a separate issue.
- **⌥A hotkey pass-through** — when AI Content is disabled (which it always is for free users), ⌥A types "a" instead of being silently consumed. This is tracked separately.

## Commits and pull requests

Do not add "Generated with" attribution, co-author trailers, or tool branding to commits, pull requests, or code.
