# Wallpaper Worker integration

Catalog requests now go exclusively to the Wallpaper Cache Worker:
https://wallpaper-cache.wallpaper-cache-worker.workers.dev/wallpapers
The app contains no NexWall API key and never falls back to the direct sandbox.
Image previews and downloads still use the returned hosted image URLs.

## Environment

The existing env/dev.json, env/release.json, env/special_dev.json files and
tracked env.example.json now set WALLPAPER_API_ENV to cloudflare. Existing IDE
profiles already load those files. Builds without an env file must explicitly
supply --dart-define=WALLPAPER_API_ENV=cloudflare.

For local Worker development, use WALLPAPER_API_ENV=sandbox and set
WALLPAPER_SANDBOX_BASE_URL to a reachable local Worker URL. Sandbox builds are
rejected in release mode. Prefer HTTPS for physical-device development. The
Android debug manifest permits HTTP only to 10.0.2.2 and localhost for local
emulator development; production network settings are unchanged. The Worker
fetches each uncached page on demand using its production API key.
Do not put NEXWALL_API_KEY in Flutter configuration.

## Pagination and expiry

Page 1 supplies a snapshot. Every subsequent request sends that same snapshot
and uses pagination.next_page, stopping when it is null. The app uses the actual
returned item count, not an assumed page size. A refresh starts again at page 1.
The Worker returns a curated category list without counts. Each category has
its own browsing generation. Switching categories requests page 1 with
`category_id` and without the previous category's snapshot; subsequent pages
use the new snapshot. An uncached category page triggers a NexWall request.
The app keeps the selected category while loading more or refreshing.
The screen presents Trending followed by the requested category tabs in a
fixed order. It maps display labels to NexWall category names (for example,
Animal & Wildlife to Animals & Wildlife). It loads the Worker's
shared `/categories` catalog for plan-available IDs, then uses verified static
IDs for several categories if discovery is temporarily unavailable. An
unresolved category reports that it is absent from the current API catalog. NexWall can
still deny a known category under the active API plan; the app displays that
upstream access error.
HTTP 410 or a changed snapshot clears the feed and offers Reload wallpapers.
Metadata is held in memory only and cleared at freshness.expires_at, including
when returning from the background. An expired preview hides the image and
prevents new download/apply actions. In-flight feed responses cannot restore an
expired selection or notify a disposed screen. Existing user-applied wallpapers
remain unchanged; feed expiry does not reset the user's device wallpaper.

Page notices and item attribution/rights metadata are retained and displayed.
The app distinguishes connection, unavailable, expired, throttled, invalid
request, and missing configuration failures. Catalog calls time out after 12
seconds and their clients are closed on completion or screen disposal.

## Server mode and verification

The Worker fetches uncached pages from the authenticated NexWall production API
and never switches to its public sandbox. It requests 100 items per upstream
page, then filters restricted and non-static entries. The provider's access
rules still apply: on 2026-09-27, an Anime category request returned upstream
HTTP 403. The Worker's current global forbidden cooldown then rejected other
uncached category requests. The app displays an API-access message for that
case. The Worker must scope a category-specific 403 to that category if other
categories should remain available.
The screen now offers Choose from gallery, which applies the selected image
and saves an app-owned copy for the launcher. The old green preview card,
system picker button, and top refresh action have been removed.
Run targeted Flutter analysis on the modified Dart files. No app build, install,
or device launch was performed. Developer device checks: initial load, all available
pages, refresh, offline/retry, open-preview expiry, resume after expiry, download,
and apply. Expiry, 410/429/503, and physical-device behavior still need device or
controlled server verification; live happy-path requests do not exercise them.
