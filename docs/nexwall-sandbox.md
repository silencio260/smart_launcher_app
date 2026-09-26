# NexWall wallpaper sandbox

The Wallpaper screen currently uses the public sandbox at
https://nexwall.kodnextech.com/wallpaper-api/sandbox, with no API key.
The request format was verified against the provider's interactive sandbox
implementation at https://nexwall.kodnextech.com/wallpaper-api on 26 September 2026.

Requests use `endpoint=wallpapers&type=image&per_page=10&page=1`.
The response contains `status`, `data`, `current_page`, `last_page`, `per_page`,
and `total`. Each image has a numeric `id`, `category_id`, `image_url`,
`thumbnail_url`, `type`, `is_premium`, `resolution`, `downloads`, and `likes`.
No display title was returned, so the screen uses “Wallpaper {id}”.
Page 2 was checked and returned distinct IDs with `current_page: 2`.

The sandbox also exposes categories (`endpoint=categories`), category filtering
(`category_id`), search (`search`), popularity sorting (`sort=popular`), and live
content (`type=live`) in its website UI. These are outside this first static
wallpaper integration. Live wallpapers need a separate native implementation.

The app uses thumbnails for the grid and full images for previews and downloads.
“Use in launcher” saves the image to app documents and updates the custom
wallpaper setting. “Set wallpaper” also calls the existing Android wallpaper
channel to set the home wallpaper. The system picker remains available.
API and download failures are surfaced with retry; no unrelated catalog is
silently substituted. Partial downloads are not cached as completed images.

This is a sandbox integration, not production API configuration. Before release,
configure authenticated production access and review the provider's plan/content
access requirements. Do not infer production entitlement from sandbox access.

Validation: live sandbox list and pagination requests, and targeted Flutter
analysis. No build, installation, or device execution is performed by the agent.
Developer verification: open Settings → Wallpaper, browse/load more, open a
preview, try each apply action, and check offline/retry behavior.
