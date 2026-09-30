# D4N Social — working notes

iPhone app (SwiftUI + WKWebView) that wraps Instagram and X and hides the
junk with injected rules. Architecture and layout are in README.md. The
folder is `~/Projects/SocialApp`; the app, bundle id and repo are
D4N Social / `uk.d4n.social` / `danstone24/d4n-social`.

## Two kinds of change, two release routes

- **Rule files** (`ios/D4NSocial/Rules/*.js|css`): edit, bump `version` in
  `manifest.json`, commit, push to `main`. The app fetches them on launch, so
  no build is needed. Tell Dan the new rules version and that a relaunch (or
  Filters > Check for rule updates) picks it up.
- **Swift changes**: bump `MARKETING_VERSION` in `ios/project.yml` (patch for
  fixes, minor for features), commit, push, and ship through
  `ios/scripts/testflight.sh` (needs `ASC_KEY_ID` and `ASC_ISSUER_ID`, which
  Dan runs in his own terminal). State the version in the summary.

## Keep in sync

- The `DEFAULTS` block in each `content.js` and `Filters.all` in
  `FilterSpec.swift` must list the same keys with the same values; a unit test
  fails otherwise. X keys keep the TwitterCleanser names so exports swap.
- Blocked paths live twice on purpose: `NavigationPolicy.swift` (native, unit
  tested) and `blockedPath()` in `instagram.content.js` (click guard).
- Every rule file starts with `/* d4n-social rules` on line one;
  `RulesStore.validate` refuses a fetched file without it.

## Testing reality

- Claude cannot log in to Instagram or X. Dan tests on his phone through
  TestFlight and reports back with screenshots; audit mode labels the filter
  that fired, so ask for that when a match looks wrong.
- Both sites change their DOM. Prefer hrefs, roles, `data-testid` (X) and
  short label text over class names. Mobile X has no sidebar: trending,
  Who to follow and Premium appear as timeline cells and on the Explore tab.
- `ios/scripts/sim.sh` builds and launches on the iPhone 17 Pro simulator;
  `-startTab filters` opens the Filters tab, `SHOT=name` saves a screenshot.
