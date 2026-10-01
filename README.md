# D4N Social

An iPhone app that opens Instagram and X inside its own browser and strips
the parts you did not ask for: Reels, Explore, ads, suggested posts, trends,
Grok, follow suggestions and the rest. Personal tool, shipped through
TestFlight. Not on the App Store.

It is the [TwitterCleanser](https://github.com/danstone24/TwitterCleanser)
model inside a native shell: each site's mobile web version loads in a
WKWebView, a content script marks unwanted elements with `data-tc-*`
attributes, a stylesheet hides them, and every filter is a toggle. The same
idea powers Dull, UNDOOMED, SocialLite and ScrollGuard.

## What it hides

**Instagram, on by default:** Reels (tab, feed and carousels), the Explore
grid (search stays), suggested posts, ads, suggested accounts, open-in-app
nags, Threads and Meta AI entry points, Shopping.
**Off by default:** stories row, like and view counts, notifications tab,
DM-only mode, stop at "You're all caught up", Following feed only.

**X, on by default:** Following-only home, ads and promoted trends, trending,
Who to follow, Premium upsells, Grok, @grok mentions, mention-only replies,
link-only posts, Discover more, and a one-tap block button with undo.
**Beta, off by default:** mute words, low-effort replies, engagement bait,
reposts, hashtag spam, slim nav, timeline nags, view counts, mute button,
AI-made posts, parody accounts, blue-check replies.

Audit mode hides nothing and instead dims, outlines and labels every match
with the filter that caught it. The Filters tab shows how many elements each
filter has caught on the open page, keeps the block log, and imports and
exports settings as JSON (TwitterCleanser exports import as they are).

## What it cannot do

- Push notifications. The web versions cannot deliver them into a WebView.
- Upload video to Instagram posts or stories; the web version does not.
- Log in with Facebook. The Facebook cookie is not shared. The normal
  username and password form works, including 2FA.
- Match labels in languages other than English.

## Layout

- `ios/project.yml` is the XcodeGen spec. The `.xcodeproj` is generated.
- `ios/D4NSocial/App` holds the entry point, the `Platform` enum, the filter
  catalogue (`FilterSpec.swift`) and the settings store.
- `ios/D4NSocial/Web` holds `WebTab` (one per platform: WebView, user agent,
  injected rules, native bridge, Safari sheet), the pure `NavigationPolicy`
  and `RulesStore`.
- `ios/D4NSocial/Views` holds the tab root, the WebView container and the
  Filters screen.
- `ios/D4NSocial/Rules` holds the rule files, one `content.js` and one
  `cleanser.css` per platform, plus `manifest.json`. They are bundled as a
  folder reference and also fetched from this repo's `main` branch.
- `ios/scripts` has the simulator, TestFlight, token and icon scripts.

## How the rules reach the page

`WebTab.installScripts` injects one user script at document start: a
`window.__d4n` prelude with the platform, the current settings and the CSS,
followed by the platform's `content.js`. The script reads the settings, sets
`data-tc-<key>` flags on `<html>`, appends the CSS, and rescans on DOM
changes. Settings changes call `window.__d4nApplySettings()` on the open
page; hidden counts and block-log entries come back through
`window.webkit.messageHandlers.d4n`.

`NavigationPolicy` polices top-level loads natively: the Reels feed and
profile Reels tabs bounce home, `instagram://` and App Store links are
dropped, `l.instagram.com` shims are unwrapped, and anything off-site opens
in a Safari sheet. The content script's click guard mirrors the same paths.

## Rule updates without a build

On launch the app fetches `Rules/manifest.json` from
`https://raw.githubusercontent.com/danstone24/d4n-social/main/ios/D4NSocial/Rules/`.
If its `version` beats the one in use, every listed file is downloaded,
checked for the `d4n-social rules` sentinel and cached; the next page load
uses it. To ship a selector fix: edit the rule files, bump `version` in
`manifest.json`, push to `main`. Filters > Rules shows the version in use and
has a "Check for rule updates" button.

## Build and run in the simulator

```sh
brew install xcodegen
ios/scripts/sim.sh                        # iPhone 17 Pro simulator
SHOT=filters ios/scripts/sim.sh -startTab filters
```

The simulator has no Instagram or X session, so you see the login pages.
Log in there once and the session persists like Safari's. With a Debug build
running, Safari on the Mac > Develop > the simulator lists the pages for
inspecting the DOM.

## Test

```sh
cd ios && xcodegen generate
xcodebuild -project D4NSocial.xcodeproj -scheme D4NSocial \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Ship to TestFlight

```sh
ios/scripts/testflight.sh
```

Reads `ASC_KEY_ID` and `ASC_ISSUER_ID` from the gitignored `.env` in the
repo root, needs the `.p8` at
`~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, and an app record for
`uk.d4n.social` in App Store Connect. Bump
`MARKETING_VERSION` in `project.yml` for a new version; the build number is
stamped from the clock.

## Prior art

[Glance](https://github.com/Fin-Murphy/Glance-sociallite-wrapper) documents
the Instagram selectors, the Mobile Safari user agent suffix and the
universal-link trap for WKWebView wrappers. The rules here are written fresh
in the TwitterCleanser style.
