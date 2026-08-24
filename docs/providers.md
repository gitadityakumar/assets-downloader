# Provider Network & API Reference

This document summarizes the network endpoints, transport models, and image download mechanisms for `ast` CLI providers.

---

## 1. ISO Republic (`isorepublic.com`)

* **Search**: `GET https://isorepublic.com/?s={query}`
* **Format**: WordPress SSR HTML.
* **Extraction**: 
  * Anchor `<a ... class="photo-grid-item">` contains detail page URL and title.
  * Image thumbnail found in `data-src` (or fallback `src`).
* **Download**:
  * Strips resized dimension suffixes (`-WxH.jpg`) to retrieve original master resolution directly from `/wp-content/uploads/`.
* **License**: CC0 / Royalty-Free.

---

## 2. Foodiesfeed (`foodiesfeed.com`)

* **Search**: `GET https://www.foodiesfeed.com/s/{query}`
* **Format**: Next.js Server Components / SSR data stream.
* **Extraction**:
  * Master image URLs stored on Cloudflare R2 storage bucket `https://pub-aaa82e9851064d22b954c3ebbafc9ae6.r2.dev/generated/masters/` and `/legacy/masters/`.
  * Thumbnails in `/generated/thumbnails/` and `/legacy/thumbnails/` as `.webp`.
* **Download**: Direct HTTP GET on the R2 master asset URL.

---

## 3. Picjumbo (`picjumbo.com`)

* **Search**: `GET https://picjumbo.com/?s={query}` (follows 302 redirect to `/search/{slug}/`)
* **Format**: WordPress SSR HTML with masonry grid (`masonry_item photo_item`).
* **Extraction**:
  * Original image path extracted from `wp-content/uploads/` path, removing query parameters (`?w=600&quality=80`).
* **Download**: Direct GET on `https://picjumbo.com/wp-content/uploads/...` with browser headers.
* **Author**: Viktor Hanacek.

---

## 4. Pexels (`pexels.com`)

* **Search**: `GET https://www.pexels.com/search/{query}/`
* **Format**: SSR JSON embedded in `<script id="__NEXT_DATA__">`.
* **Extraction**:
  * `props.pageProps.initialData.data[]` contains photo attributes, author/user info, and CDN image variations (`small`, `medium`, `large`, `download_link`).
* **Download**: Images served from `images.pexels.com`.

---

## 5. Kaboompics (`kaboompics.com`)

* **Search**: `GET https://kaboompics.com/?search_keywords={query}`
* **Format**: SSR HTML containing Base64 encoded JSON in `data-modal="..."` attributes.
* **Extraction**:
  * Base64 decoded payload provides `photo.id`, `photo.name` (hash), dimensions, color palette, and tags.
* **Download**: Direct GET on `https://kaboompics.com/download/{name_hash}/original`.
* **Photographer**: Karolina Grabowska.

---

## 6. Aura (`aura.build`)

* **Search**: Supabase PostgREST search API (`/rest/v1/assets`).
* **Format**: JSON with tokenized keyword matching.
* **Download**: Supabase Storage public CDN URLs.
* **Documentation**: See [docs/AURA_API.md](AURA_API.md).

---

## 7. Unsplash (`unsplash.com`)

* **Search**: Server-rendered search markup and public JSON endpoints.
* **Download**: `images.unsplash.com` CDN transforms.
* **Documentation**: See [docs/unsplash.md](unsplash.md).
