# Aura.build provider notes

Implementation notes for the `aura` provider in `ast`.

**Source:** https://www.aura.build/assets  
**Auth:** Public Supabase anon key (no user login required for public assets)

This project is not affiliated with Aura.build. Use of their service is subject to their terms.

## Architecture

Aura Assets is a SPA (Vite + React) backed by **Supabase PostgREST**, not a custom GraphQL API.

| Piece | Value |
|-------|--------|
| Supabase project | `hoirqrkdgbmvpwutwuwj` |
| REST base | `https://hoirqrkdgbmvpwutwuwj.supabase.co/rest/v1` |
| Storage CDN | `*.supabase.co/storage/v1/object/public/assets/...` |
| Table | `public.assets` |
| Authors | `public.public_author_profiles` |
| Client | `supabase-js-web/2.56.0` |

## Authentication

Public reads use the **anon** JWT as both `apikey` and `Authorization: Bearer …` headers.

No session is required for:

- listing / searching public assets (`private=eq.false`)
- loading author profiles
- downloading public storage objects

Private (“Mine”) assets require a signed-in user and are out of scope for this CLI.

## Search API

### Endpoint

```
GET /rest/v1/assets
```

### Default explore (no query)

From network capture on `/assets` (Popular / explore mode):

```
private=eq.false
views=gte.10
order=views.desc
offset=0
limit=1000
Prefer: count=exact
```

### Natural-language search

Aura does **not** use embeddings or vector search for the public assets page.  
“Natural language” queries are split on whitespace and matched with **PostgREST filters**:

For each token `T` (after escaping `%` and `_`):

```
or=(title.ilike.%T%,description.ilike.%T%,keywords.cs.{T})
```

- Multi-token queries AND those groups together:

```
and=(
  or(title.ilike.%cyberpunk%,description.ilike.%cyberpunk%,keywords.cs.{cyberpunk}),
  or(title.ilike.%fox%,description.ilike.%fox%,keywords.cs.{fox})
)
```

- `keywords.cs.{T}` = contains the array element `T` (case-sensitive keyword membership).
- `title` / `description` use case-insensitive substring match (`ilike`).

Sort for search results defaults to `views` descending (website “Popular” when searching).

### Select columns

```
id,title,description,keywords,resolution,colors,
image_original,original_file_size,original_file_hash,
image_320w,image_800w,image_1600w,image_3840w,
featured,active,created_at,updated_at,created_by,
views,forks,premium,private,slug,transparent,
media_type,image_url,video_url,video_poster_url,video_duration
```

### Pagination

`offset` + `limit` (PostgREST `Range`).  
`Prefer: count=exact` → `Content-Range: 0-9/123` for totals.

### Author hydration

```
GET /rest/v1/public_author_profiles?select=id,full_name,avatar_url,slug&id=in.(uuid1,uuid2)
```

Joined client-side via `created_by`.

## Response schema (per asset)

| Field | Type | Notes |
|-------|------|--------|
| `id` | number | Stable numeric id — used for filenames |
| `slug` | string | Public path segment (`/assets/{slug}`) |
| `title` | string | Short title (list description) |
| `description` | string | Long descriptive text (treated as “prompt”) |
| `keywords` | string[] | Tag array |
| `resolution` | string | Aspect ratio label: `16:9`, `1:1`, `3:4`, … |
| `colors` | string[] | Color tags |
| `image_320w` / `800w` / `1600w` / `3840w` | url \| null | Resized variants |
| `image_original` | url \| null | Highest fidelity source |
| `image_url` | url \| null | Fallback |
| `media_type` | `"image"` \| `"video"` | |
| `views`, `forks` | number | |
| `premium`, `private`, `featured`, `active` | boolean | |
| `created_by` | uuid | Author profile id |

There is **no separate generation-prompt column**. The CLI maps:

- `description` (list) ← `title`
- `prompt` ← `description` (long text; fallback: title + keywords)
- `imageUrl` ← first of `image_3840w`, `image_original`, `image_1600w`, …
- `thumbnailUrl` ← `image_800w` or `image_320w`

## Image URLs

Storage objects are publicly readable, e.g.:

```
https://hoirqrkdgbmvpwutwuwj.supabase.co/storage/v1/object/public/assets/assets/{uuid}_1600w.jpg
https://hoirqrkdgbmvpwutwuwj-all.supabase.co/storage/v1/object/public/assets/assets/{uuid}_original.png
```

Some rows return the `-all` Supabase host. The Aura SPA rewrites  
`*-all.supabase.co` → `*.supabase.co` before display/download (`ve()` in the bundle).  
The CLI applies the same rewrite — the `-all` host often returns HTTP 400 for direct clients.

## Rate limiting

No explicit client-side rate limit observed. Supabase / Cloudflare may return HTTP 429 under abuse; the CLI surfaces that as a rate-limit error.

## Website JS entry points

- Main bundle: `/assets/index-*.js`
- Page chunk: `Assets-*.js` imports `getPublicAssets` (`N$`) from the main bundle
- Detail: `AssetView-*.js` → `getPublicAsset` by `slug` or numeric `id`

## CLI mapping (`ast` — Zig)

The Asset Downloader CLI command is **`ast`** (Zig rewrite on branch `rewrite/zig`).

```bash
ast s aura "cyberpunk fox"
ast -s aura "cyberpunk fox"
ast -sjl 5 aura "cyberpunk fox"
```

| CLI concept | Aura implementation |
|-------------|---------------------|
| Command | `ast` |
| Search subcommand | `s` (or flag `-s` / `--search`) |
| Provider id | `aura` |
| Provider `search(query)` | PostgREST filter search above |
| Query encoding | Filter values percent-encoded for `std.Uri` |
| Storage hosts | Rewrite `*-all.supabase.co` → `*.supabase.co` |
| `getPrompt` | asset `description` |
| `getUrl` | best image URL |
| `download` | HTTP GET of image URL → `downloads/{id}.{ext}` |
