# Unsplash provider notes

Implementation notes for the `unsplash` provider in `ast`.

**Site:** https://unsplash.com  
**Auth model:** Public browsing and free downloads. HTML routes may be protected by [Anubis / BotStopper](https://anubis.techaro.lol/) (Techaro).

This project is not affiliated with Unsplash. Prefer the [official Unsplash API](https://unsplash.com/developers) for production integrations. Use of Unsplash is subject to their [terms](https://unsplash.com/terms) and [API guidelines](https://unsplash.com/api-terms).

---

## Browser workflow (reference)

Typical logged-out flow:

1. Search → results grid  
2. Open a photo (presentation modal or `/photos/...` route)  
3. Save the image from the page (`<img src>` / free download URL)

### Search autocomplete

```http
GET https://unsplash.com/nautocomplete/dogs
```

Returns suggestion JSON only — **not** the image grid. The CLI does not use this endpoint for asset search.

Search results for the CLI come from the SSR HTML document:

```text
GET https://unsplash.com/s/photos/{query}
  → HTML with embedded photo JSON (urls, links, user, …)
```

### Photo detail (`/napi`)

Opening a photo may request same-origin JSON (after any bot check):

| Request | Role |
|---------|------|
| `GET /napi/photos/{slug-or-id}` | Full photo metadata |
| `GET /napi/photos/{slug}/series?limit=10` | Series carousel |
| `GET /napi/photos/{slug}/related?page=1&per_page=20` | Related images |

**Example request:**

```http
GET https://unsplash.com/napi/photos/a-golden-retriever-sitting-on-a-sandy-beach-FTbC150wV8Q
Accept: */*
Referer: https://unsplash.com/photos/a-golden-retriever-sitting-on-a-sandy-beach-FTbC150wV8Q
sec-fetch-site: same-origin
```

Browser clients typically send no Unsplash developer `Authorization` header on these same-origin routes.

**Photo JSON shape (keys observed):**  
`id`, `slug`, `width`, `height`, `color`, `description`, `alt_description`, `created_at`, `urls` (`raw|full|regular|small|thumb|small_s3`), `links` (`self|html|download|download_location`), `user`, `premium`, `plus`, `tags`, `exif`, `location`, `likes`, `views`, `downloads`, …

Unsplash+ / premium photos use CDN host `plus.unsplash.com` and are not treated as free downloads. Free library photos use `images.unsplash.com` with `premium`/`plus` false.

**`links` for CLI download (from same JSON):**

```json
"links": {
  "html": "https://unsplash.com/photos/...",
  "download": "https://unsplash.com/photos/FTbC150wV8Q/download?ixid=...",
  "download_location": "https://api.unsplash.com/photos/FTbC150wV8Q/download?ixid=..."
}
```

- Site path: **`links.download`** or `/photos/{id}/download?force=true`.  
- `download_location` targets `api.unsplash.com` and expects a developer Access Key.

**Related / series (optional enrichment):**

```http
GET /napi/photos/{slug}/related?page=1&per_page=20
GET /napi/photos/{slug}/series?limit=10
```

### Save image (CLI download path)

Right-click → Save image in the browser usually does **not** issue a new download request; it saves the image URL already on the page (`<img src>` / `srcset`):

- Free: `https://images.unsplash.com/photo-…?…`
- Plus: `https://plus.unsplash.com/premium_photo-…?…`

**What `ast` does for `-d` / interactive Download:**

1. From search HTML (or `/napi` metadata), take a display URL — prefer **`urls.regular`** (~1080px).
2. Fallbacks: `urls.small`, then higher resolutions if needed.
3. `GET` that CDN URL with a normal browser User-Agent and `Referer: https://unsplash.com/`.
4. Save as `{id}.jpg` (or extension from `Content-Type` / URL).

CDN URLs typically return `200 image/jpeg` with open CORS for free library assets.

### Mapping browser flow → CLI

| Browser step | Network | CLI action |
|--------------|---------|------------|
| Search | HTML `/s/photos/{q}` (SSR) | `search()` → list results |
| Open photo | `/napi/photos/{slug}` (optional) | Enrich asset (urls, author) |
| Save image | CDN `urls.regular` / similar | `download()` |

---

## Capability summary

| Capability | Login | Developer API key | Notes |
|------------|-------|-------------------|--------|
| Search (SSR HTML) | No | No | After bot check when required; photo JSON embedded in HTML |
| Official `api.unsplash.com` | N/A | **Yes** (Client-ID) | Preferred for production apps; not used by this provider today |
| Site `/napi/*` | No | No | May require Anubis challenge cookies |
| Image CDN `images.unsplash.com` | No | No | Public free-library CDN |
| Free download `/photos/{id}/download?force=true` | No | No | 302 → JPEG on CDN |
| Unsplash+ / premium | — | — | Skip; Plus CDN on `plus.unsplash.com` |

**Implementation path used by this repo:**

1. **Search:** `GET https://unsplash.com/s/photos/{query}` → parse embedded photo objects from HTML.  
2. **Download:** `GET` `urls.regular` (or similar) from parsed metadata.  
3. **Bot protection:** HTML search may require solving **Anubis**; unauthenticated clients can be redirected to `/.within.website`. See below.

---

## Bot protection

### Behavior

- Unauthenticated **curl** to HTML routes (`/s/photos/...`, even `/napi/...`) gets:

  ```http
  HTTP/2 307
  location: /.within.website?redir=%2Fs%2Fphotos%2Ffox
  ```

- Challenge UI: **“Making sure you're not a bot!”** — [Anubis / BotStopper](https://anubis.techaro.lol/) (Techaro), version observed `v1.25.0`.
- After the real Chrome browser completes the challenge, cookies appear:

  | Cookie | Role |
  |--------|------|
  | `techaro.lol-anubis-auth` | JWT-like challenge proof (required for subsequent HTML) |
  | `techaro.lol-anubis-cookie-verification` | Verification id |
  | `uuid` | Client uuid (also set by site) |
  | others | analytics / consent (`_sp_*`, `_dd_s`, …) — not needed for core download |

- **Once cookies are set in the browser**, same-origin `fetch('/s/photos/fox')` returned **200** HTML (~680KB) with **~48 photo ids** and **no** Anubis body.
- Same session: `fetch('/napi/search/photos?...')` still **307 → Anubis** in our probes (napi may be more strictly protected than document HTML, or needs extra headers).

### Implications for CLI

| Approach | Feasibility |
|----------|-------------|
| Plain HTTP client, no cookies | **Search fails** (Anubis). **Download + CDN still work**. |
| Solve Anubis PoW (open-source challenge) | Possible; complexity medium; may break when Anubis updates |
| Reuse browser cookies (user pastes / Playwright once) | Works; not pure “headless CLI” |
| Parse only Fastly-cached HTML | Unreliable — curl still got 307 even when browser had Fastly HIT |

**Document for implementers:** treat Anubis as the main engineering risk for **search**. Download path is much easier.

---

## Search

### User-facing URL

```
https://unsplash.com/s/photos/{slugified-query}
```

Examples:

- Query `golden retriever` → `/s/photos/golden-retriever`
- Query `cyberpunk` → `/s/photos/cyberpunk`

Spaces → hyphens (site convention). Encoding: path segment style, not only `?q=`.

### How results appear in network (Chrome)

On a successful document navigation to the search page:

| Request | Purpose |
|---------|---------|
| `GET /s/photos/{query}` | **Primary** — HTML with embedded photo JSON |
| `GET /ngetty/v3/search/images/creative?...` | **iStock / Getty affiliate** rail — **not** free Unsplash content |
| `POST /nabc` | Analytics / internal |
| Images | `https://images.unsplash.com/photo-...` and `https://plus.unsplash.com/premium_photo-...` |

**Not observed as the main free-photo search transport after load:** continuous `/napi/search/photos` for infinite scroll in our short session (initial grid is SSR’d). Pagination may load more RSC/flight data; re-check when implementing “load more”.

### Embedded photo JSON (SSR / hydration)

HTML does **not** use classic `__NEXT_DATA__`. Photo records appear as **JSON-escaped** fragments inside large inline scripts (React/RSC-style payload), e.g.:

```text
{\"id\":\"9LkqymZFLrE\",\"slug\":\"golden-retriever-puppy-on-focus-photo-9LkqymZFLrE\",...}
```

Observed fields per photo object (parsed successfully from HTML):

| Field | Example / notes |
|-------|------------------|
| `id` | `9LkqymZFLrE` (11-char Unsplash id) |
| `slug` | `golden-retriever-puppy-on-focus-photo-9LkqymZFLrE` |
| `width` / `height` | e.g. 5394 × 6743 |
| `color` | `#8c7359` |
| `description` | Optional caption (`"Golden Puppy"`) |
| `alt_description` | SEO alt (`"golden retriever puppy on focus photo"`) |
| `created_at` | ISO timestamp |
| `premium` / `plus` | booleans — filter free: both false |
| `urls.raw` | Full-res Imgix base |
| `urls.full` | High quality (`q=85`, `fm=jpg`) |
| `urls.regular` | `w=1080` |
| `urls.small` / `urls.thumb` | Previews |
| `urls.small_s3` | S3 small |
| `links.html` | Canonical page |
| `links.download` | `https://unsplash.com/photos/{id}/download?ixid=...` |
| `links.download_location` | `https://api.unsplash.com/photos/{id}/download?ixid=...` (**needs API key**) |
| `user.id` / `username` / `name` | Author |

Rough counts from one search HTML (`golden-retriever`): ~20 free photos in first paint embeds; ~4.5k total shown in UI chrome.

### Parsing strategy (for later code)

1. `GET` HTML of `/s/photos/{slug}`.
2. Find segments matching `{\"id\":\"XXXXXXXXXXX\"` (escaped).
3. Unescape `\"` → `"` and parse balanced `{...}` JSON objects.
4. Keep objects that have `urls` + `links.download` (real photos, not nested user-only objects).
5. Drop `premium === true` or `plus === true` (and hosts `plus.unsplash.com`) for free-download CLI.
6. Map to normalized Asset (see below).

### Official API (not for this CLI)

```http
GET https://api.unsplash.com/search/photos?query=fox
→ 401 Unauthorized without Authorization: Client-ID ...
```

Reject this path for the browser-alternative design.

---

## Photo page (detail)

### URL shapes

```
https://unsplash.com/photos/{slug}-{id}
https://unsplash.com/photos/{id}          # often redirects / works
```

Example:

- https://unsplash.com/photos/golden-retriever-puppy-on-focus-photo-9LkqymZFLrE  
- Id: `9LkqymZFLrE`  
- Author: Bill Stephan (`@billstephan`)  
- UI: **“Download free”** link (logged-out)  
- License text: Free under Unsplash License  

### Download button (from a11y tree)

```html
<a href="https://unsplash.com/photos/9LkqymZFLrE/download?force=true">Download free</a>
```

Optional: “Choose download size” menu (not fully captured; default free download is enough for CLI).

---

## Download

### Site free-download redirect

```http
GET https://unsplash.com/photos/{id}/download?force=true
User-Agent: Mozilla/5.0 ...
Referer: https://unsplash.com/
```

**Observed response:**

```http
HTTP/2 302
Location: https://images.unsplash.com/photo-1591160690555-5debfba289f0?ixlib=rb-4.1.0&q=85&fm=jpg&crop=entropy&cs=srgb&dl=bill-stephan-9LkqymZFLrE-unsplash.jpg
```

Follow redirect:

```http
HTTP/2 200
content-type: image/jpeg
content-disposition: attachment; filename="bill-stephan-9LkqymZFLrE-unsplash.jpg"
```

Notes:

- Use **`{id}`** form. Slug-only path  
  `/photos/{slug}-{id}/download?force=true` returned **404** in tests.  
- Without `force=true`, still 302 to CDN (slightly different query params; no `dl=` filename).  
- Prefer `force=true` to match UI “Download free”.

### Secondary (CDN URLs from search metadata)

Also public, no key:

| Variant | Use |
|---------|-----|
| `urls.full` | High quality (~srgb, q=85) |
| `urls.raw` | Base Imgix; can append `&w=2400&q=85&fm=jpg` |
| `urls.regular` | ~1080px — good default preview/download |

Verified:

```bash
curl -sI -A 'Mozilla/5.0 ...' -H 'Referer: https://unsplash.com/' \
  'https://images.unsplash.com/photo-1591160690555-5debfba289f0?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080'
# → 200 image/jpeg, access-control-allow-origin: *
```

Sample file: ~159 KB JPEG, 1080×1350.

### Does not work without key

```http
GET https://api.unsplash.com/photos/{id}/download
→ 401
```

`links.download_location` points here — **ignore** for no-key client; use `links.download` or construct `/photos/{id}/download?force=true`.

---

## Image hosts

| Host | Content |
|------|---------|
| `images.unsplash.com` | Free library photos (`photo-{timestamp}-{hash}`) |
| `plus.unsplash.com` | Unsplash+ / premium (`premium_photo-...`) |
| `s3.us-west-2.amazonaws.com/images.unsplash.com` | Small derivatives |
| `media.istockphoto.com` | Partner rail only (ngetty) — **do not** treat as Unsplash free assets |

---

## Normalized Asset mapping (for `ast`)

| Asset field | Unsplash source |
|-------------|-----------------|
| `id` | `id` (e.g. `9LkqymZFLrE`) |
| `description` | `alt_description` \|\| `description` \|\| slug |
| `prompt` | **None** (stock photo). Use `description` / `alt_description` as stand-in, or null + CLI message |
| `imageUrl` | Prefer resolved download Location, else `urls.full`, else `urls.raw` |
| `thumbnailUrl` | `urls.small` or `urls.thumb` |
| `provider` | `unsplash` |
| `author` | `user.name` |
| `width` / `height` | `width` / `height` |
| `metadata` | `slug`, `color`, `links.html`, `user.username`, `premium`, `plus`, `created_at` |

Filename default: `{id}.jpg` (same pattern as Aura numeric ids).

---

## Pagination / limit

- First page of search HTML embeds a finite set (~20–30) of photo objects.  
- UI claims thousands of matches; infinite scroll was **not** clearly backed by open `/napi` in our short capture.  
- For CLI `--limit N`: take first N free photos from parsed SSR set; if N > embedded count, either stop or reverse-engineer scroll/RSC requests in a follow-up session.

---

## Headers that matter

### Search HTML (browser after Anubis)

```
Accept: text/html,...
User-Agent: Chrome/...
Cookie: techaro.lol-anubis-auth=...; techaro.lol-anubis-cookie-verification=...
```

### Download + CDN (worked without special cookies)

```
User-Agent: Mozilla/5.0 (reasonable desktop Chrome)
Referer: https://unsplash.com/
Accept: image/*,*/*  (or */*)
```

Do **not** require `Authorization: Client-ID`.

---

## Rate limiting / abuse

- Anubis is the primary throttle for HTML.  
- CDN is heavily cached (long `max-age`).  
- Be polite: small concurrency, reuse connections, cache search HTML briefly.  
- Unsplash License still requires attribution norms for public use — store `author` + `links.html` in metadata for CLI consumers.

---

## Implementation sketch (later)

```
providers/unsplash:
  search(query, limit):
    slug = slugify(query)  # spaces → hyphens
    html = http.get("https://unsplash.com/s/photos/" + slug)  # + Anubis strategy
    photos = parse_embedded_photos(html)
    photos = filter(not premium and not plus)
    return normalize(photos[:limit])

  download(asset, dir):
    # Option A — matches "Download free"
    url = "https://unsplash.com/photos/" + asset.id + "/download?force=true"
    follow redirects → save body
    # Option B — direct CDN
    get(asset.imageUrl)

  getPrompt: description/alt or null
  getUrl: imageUrl / full
```

### Anubis strategies (pick one when coding)

1. **Minimal v1:** Document that search needs cookies / browser assist; download-by-id works if user has id.  
2. **v1.1:** Embed Anubis “fast” solver (challenge JSON in `/.within.website` page).  
3. **v1.2:** Optional Playwright one-shot to mint cookies into a local jar.

---

## Test matrix used (2026-07-19)

| Test | Result |
|------|--------|
| Chrome open `/s/photos/golden-retriever` | Pass after Anubis; free + Plus grid |
| Parse photo `9LkqymZFLrE` from HTML | Full urls/links/user |
| curl CDN regular image | 200 JPEG |
| curl `/photos/{id}/download?force=true` | 302 → CDN attachment JPEG |
| curl `/photos/{slug-id}/download?force=true` | 404 |
| curl `api.unsplash.com/...` without key | 401 |
| curl `/s/photos/...` without Anubis cookie | 307 → Anubis |
| Browser fetch search HTML with Anubis cookies | 200 + many photo ids |
| Browser fetch `/napi/search/photos` | 307/401 Anubis in session |

---

## Open questions for implementer

1. Exact infinite-scroll request after first HTML page (RSC flight URL shape).  
2. Stable Anubis solve without full browser (difficulty was 1–4 depending on path).  
3. Whether non-English locales change HTML embedding format.  
4. “Choose download size” menu network payloads (small/medium/original).

---

## Sources

- Chrome DevTools MCP: live session on unsplash.com (search + photo page).  
- curl: CDN + download redirect verification from this machine.  
- Not used: Unsplash developer dashboard / registered Access Keys.
