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

## 4. Aura (`aura.build`)

* **Search**: Supabase PostgREST search API (`/rest/v1/assets`).
* **Format**: JSON with tokenized keyword matching.
* **Download**: Supabase Storage public CDN URLs.
* **Documentation**: See [docs/AURA_API.md](AURA_API.md).

---

## 5. Unsplash (`unsplash.com`)

* **Search**: Server-rendered search markup and public JSON endpoints.
* **Download**: `images.unsplash.com` CDN transforms.
* **Documentation**: See [docs/unsplash.md](unsplash.md).

---

## 6. Picography (`picography.co`)

* **Search**: `GET https://picography.co/?s={query}`
* **Format**: WordPress SSR HTML with single-photo articles (`class="single-photo hentry"`).
* **Extraction**:
  * Title extracted from `<span class="hidden" itemprop="name">` or image title attribute.
  * Author extracted from `rel="author"`.
  * Original image path extracted from `wp-content/uploads/` path, removing dimensions suffix (`-600x400.jpg`).
* **Download**: Direct GET on `https://picography.co/wp-content/uploads/...` with browser headers.
* **License**: CC0 / Royalty-Free.

---

## 7. Gratisography (`gratisography.com`)

* **Search**: `GET https://gratisography.com/?s={query}`
* **Format**: WordPress SSR HTML with photo cards (`class="single-photo hentry"`).
* **Extraction**:
  * Title extracted from image `alt` or anchor `title` attribute.
  * Author credited as Ryan McGuire.
  * Master image path extracted from `wp-content/uploads/` path, removing dimension suffixes (`-800x525.jpg`).
* **Download**: Direct GET on `https://gratisography.com/wp-content/uploads/...` with browser headers.
* **License**: CC0 / Royalty-Free.

---

## 8. Startup Stock Photos (`startupstockphotos.com`)

* **Search**: `GET https://startupstockphotos.com/?s={query}`
* **Format**: WordPress SSR HTML with photo links (`href="https://startupstockphotos.com/photos/..."`).
* **Extraction**:
  * Title extracted from `<span class="hidden" itemprop="name">` or image alt attribute.
  * Author credited as Startup Stock Photos.
  * Master image path extracted from `wp-content/uploads/` path, removing dimension suffixes (`-500x330.jpg`).
* **Download**: Direct GET on `https://startupstockphotos.com/wp-content/uploads/...` with browser headers.
* **License**: CC0 / Free Public Domain.

---

## 9. Burst by Shopify (`burst.shopify.com`)

* **Search**: `GET https://burst.shopify.com/photos/search?q={query}`
* **Format**: SSR HTML photo cards with Shopify CDN assets.
* **Extraction**:
  * Title extracted from `data-photo-title` or `alt` attribute.
  * Author credited as Burst by Shopify.
  * Master image path extracted from `burst.shopifycdn.com/photos/` removing query parameters (`?width=1000...`).
* **Download**: Direct GET on `https://burst.shopifycdn.com/photos/...` with browser headers.
* **License**: Free for Commercial and Non-Commercial Use (Shopify Burst License / CC0).

---

## 10. Jay Mantri (`jaymantri.com`)

* **Search**: `GET https://jaymantri.com/api/read/json?num=50&type=photo`
* **Format**: JSON feed of CC0 photography with tags and captions.
* **Extraction**:
  * Title extracted from photo tags or slug.
  * Author credited as Jay Mantri.
  * Master image path extracted from Cloudflare R2 bucket (`pub-b214a7fe3192432da1b696eafd081d17.r2.dev`) or Tumblr 1280px CDN.
* **Download**: Direct GET on master image URL.
* **License**: CC0 / Free Public Domain.

---

## 11. Public Domain Archive (`publicdomainarchive.com`)

* **Search**: `GET https://publicdomainarchive.com/?s={query}`
* **Format**: WordPress SSR HTML with vintage and modern photo entries.
* **Extraction**:
  * Title extracted from image `alt` attribute.
  * Author credited as Public Domain Archive.
  * Image path extracted from `wp-content/uploads/` path.
* **Download**: Direct GET on image URL with redirect following.
* **License**: CC0 / 100% Free Public Domain.

---

## 12. Magdeleine (`magdeleine.co`)

* **Search**: `GET https://magdeleine.co/?s={query}`
* **Format**: Curated photography feed with photo cards and author attribution.
* **Extraction**:
  * Title extracted and formatted from post slug.
  * Author extracted from photographer profile link.
  * Master image path extracted by stripping geometry suffixes (`-500x375`, `-860x683`) from `wp-content/uploads/` image URLs.
* **Download**: Direct GET on original full-resolution master JPEG.
* **License**: CC0 / Free High-Resolution Stock Photos.

---

## 13. SplitShire (`splitshire.com`)

* **Search**: `GET https://www.splitshire.com/?s={query}`
* **Format**: Next.js SSR with embedded `__NEXT_DATA__` image collections.
* **Extraction**:
  * Extracted image collections across photography and design categories.
  * Query token matching across title, prompt, description, and slug.
  * Author credited from user profile or Daniel Nanescu.
* **Download**: Direct GET on high-resolution CDN assets.
* **License**: Free for Personal and Commercial Use (SplitShire License / CC0).

---

## 14. DeviantArt (`deviantart.com`)

* **Search**: `GET https://www.deviantart.com/tag/{tag}`
* **Format**: SSR HTML with artwork cards, titles, author links, and direct Wixmp CDN URLs.
* **Extraction**:
  * Title extracted and HTML unescaped from image `alt` attribute.
  * Author parsed from artwork page link (`/{author}/art/...`).
  * Image path extracted directly from signed Wixmp CDN URLs.
* **Download**: Direct GET on Wixmp CDN URL with browser headers.
* **License**: Free Creative Community Stock / Artwork Reference.

---

## 15. NegativeSpace (`negativespace.co`)

* **Search**: `GET https://negativespace.co/?s={query}`
* **Format**: WordPress photography feed with card images and post links.
* **Extraction**:
  * Title extracted and unescaped from image `alt` attribute.
  * Slug ID parsed from post permalink.
  * Master full-resolution URL extracted by stripping geometry suffixes (`-1062x708`) from `wp-content/uploads/` image URLs.
* **Download**: Direct GET on original full-resolution master photo JPEG/PNG (up to 20+ MB).
* **License**: CC0 / 100% Free High-Resolution Stock Photos.

---

## 16. Skitterphoto (`skitterphoto.com`)

* **Search**: `GET https://skitterphoto.com/photos/tags/{tag}`
* **Format**: Clean SSR photography feed with photo IDs, slugs, and CDN thumbnails.
* **Extraction**:
  * Title formatted and capitalized from URL slug.
  * High-resolution photo asset path extracted directly (`/photos/skitterphoto-{id}-default.jpg`).
* **Download**: Direct GET on high-resolution image URL.
* **License**: CC0 / 100% Free Public Domain.

---

## 17. LibreShot (`libreshot.com`)

* **Search**: `GET https://libreshot.com/?s={query}`
* **Format**: WordPress photography feed by Martin Vorel with lazy-loaded image cards.
* **Extraction**:
  * Title extracted and HTML unescaped from image `alt` attribute.
  * Slug ID parsed from post permalink.
  * Master full-resolution URL extracted by stripping geometry suffixes (`-508x339`, `-508x300`) from `wp-content/uploads/` image URLs.
* **Download**: Direct GET on original full-resolution master photo JPEG/PNG (up to 10+ MB).
* **License**: CC0 / Free Public Domain Stock Photos.

---

## 18. Moveast (`moveast.me`)

* **Search**: `GET https://moveast.me/api/read/json?tagged={tag}&num={limit}` (with fallback to main feed).
* **Format**: Tumblr JSON feed by Portuguese designer/traveler João Pacheco.
* **Extraction**:
  * Clean HTML stripped from photo captions.
  * Tag buffer and slug fallback for descriptive search prompts.
  * 1280px / 500px CDN image endpoints.
* **Download**: Direct GET on high-resolution Tumblr CDN JPEG assets.
* **License**: CC0 / 100% Free Public Domain.
