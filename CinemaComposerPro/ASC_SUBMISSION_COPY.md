# Cinema Composer — ASC Submission Copy

Ready-to-paste content for the App Store Connect listing and review notes.
All claims verified against the repo at `c454c74` (plus the 3-blocker fix
commit).

## App Information

| Field | Value |
|---|---|
| Name | Cinema Composer |
| Bundle ID | com.steroidos.cinemacomposer (registered FU5974ZVJ6) |
| SKU | CINEMACOMPOSER-IOS-2026 |
| Primary language | en-US |
| Platform | iOS (iPhone + iPad) |
| Primary category | Productivity |
| Secondary category | Graphics & Design |
| Price | Free (auto-renewable subs + non-consumable IAP) |
| Copyright | © 2026 Mike Valasek |

## Subtitle (30 char max)

```
Plan, budget and cut your film
```
(29 chars — no vendor names, no price words, no trademark risk.)

## Promotional Text (170 max)

```
Break down a script, budget it, schedule it, and cut it — one app. Planning, the Advisor and the Conductor are free.
```
(115 chars)

## Description

```
Cinema Composer is a complete pre-production and editing suite for film — from first script breakdown to final export.

WHAT'S FREE
- Script breakdown: every scene, element and cost, auto-tallied
- Budget: above-the-line and below-the-line planning with categories
- Schedule: day-out-of-days and stripboard planning
- The Advisor: a production coach that reviews your plan before you spend
- The Conductor: run a full simulated production — calls, setups, takes —
  with nothing billed and nothing sent
- Every export: EDL, FCPXML and OTIO carry your cut into Resolve, Premiere
  or Final Cut

CINEMA COMPOSER PRO (subscription or one-time unlock)
- The Cutting Room: a full NLE-style timeline — blade, ripple, slip, take
  stacks — where every clip carries its cost
- Live runs: call your own AI vendors for video, voice and score, under a
  hard spend cap
- Cost-honest takes: swap takes and see exactly what the cut costs

NO ACCOUNT. NO ANALYTICS. NO TRACKING.
Everything is stored on your device. API keys you add for live runs live in
your Keychain and are never exported.

Cinema Composer ships with no live endpoints. Every cost you see is an
editable default, not a vendor quote.
```

## Keywords (100 max)

```
film,screenwriter,producer,budget,schedule,editing,timeline,video,movie,production
```
(81 chars — no vendor names.)

## Support URL

```
https://mvalasek77-droid.github.io/cinema-composer-privacy.html
```
(privacy doubles as support contact page for launch; swap in a dedicated
support page later if wanted)

## Privacy Policy URL

```
https://mvalasek77-droid.github.io/cinema-composer-privacy.html
```

## Review Notes (App Review Information → Notes)

```
Cinema Composer works fully with NO API keys and NO account. Every
planning and budgeting feature is free and works offline.

To evaluate the paid tier without a purchase: tap the locked "Cutting
Room" tab → "Or try the demo cut" → the full editor opens on a showcase
sequence, nothing is charged, and exiting restores your real project.

The Conductor's "dry run" simulates a full production and bills nothing —
no built-in tool ships with an endpoint, so even a live run cannot spend
until the user imports a tool pack with their own vendor endpoints and
their own API key. Spend figures shown are editable defaults, not quotes.

The Report Bug tab keeps an on-device tracker only and sends nothing
anywhere — the app makes no network requests except the user's own live
runs and the App Store.

Sandbox tester account (if required): see App Review attachment. Demo mode
covers the full paid tier, so a purchase is not needed to review.
```

## Age Rating answers

- Unrestricted web access: NO (vendor endpoints come only from user-imported
  tool packs; the app never opens arbitrary web content itself)

## IAPs (create in ASC, attach to first submission)

Group: ccp_pro_group (display name: "Cinema Composer Pro")

| Product ID | Type | Price |
|---|---|---|
| com.steroidos.cinemacomposer.pro.monthly | Auto-renewable | $9.99/mo |
| com.steroidos.cinemacomposer.pro.annual | Auto-renewable | $59.99/yr |
| com.steroidos.cinemacomposer.pro.lifetime | Non-consumable | $99.99 |

Localizations (en-US):
- Monthly: "Pro Monthly" — "Full Cutting Room editor, live runs and cost
  tracking. Renews monthly."
- Annual: "Pro Annual" — "Full Cutting Room editor, live runs and cost
  tracking. Renews yearly."
- Lifetime: "Pro Lifetime" — "Unlock the Cutting Room forever. One
  purchase, no subscription."

## App Privacy

Data Not Collected. Keys in Keychain, no analytics SDK, no server.
Prompts to vendors travel user-device → vendor under the user's own key
(documented in the privacy policy even though nothing is collected).

## Encryption

ITSAppUsesNonExemptEncryption = false (HTTPS + Keychain only) — already in
Info.plist.

## EULA

Apple standard EULA (default) — the in-app Terms link points at our own
terms page for the subscription disclosure requirement.