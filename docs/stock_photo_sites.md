# Stock Photo Sites Implementation Tracker

This document tracks all 24 stock photo websites listed in the [GrayGrids 21+ Best Websites to Download Free Stock Photos](https://graygrids.com/blog/best-websites-to-download-free-stock-photos) article, indicating their current implementation status in `ast`.

---

## Summary Status

- **Total Sites Listed**: 24
- **Implemented & Working**: 10 (`unsplash`, `isorepublic`, `picjumbo`, `foodiesfeed`, `picography`, `gratisography`, `startupstockphotos`, `burst`, `jaymantri`, `publicdomainarchive`)
- *(Additional Provider Implemented in `ast`)*: `aura` ([Aura.build](https://www.aura.build))
- **Unimplemented / Blocked / Pending**: 14

---

## Sites Checklist

- [x] **Unsplash** ([unsplash.com](https://unsplash.com/))
  - **CLI Provider**: `unsplash`
  - **Status**: Implemented & verified.
  - **Notes**: Full search and image downloading supported.

- [ ] **Pixabay** ([pixabay.com](https://pixabay.com/))
  - **Status**: Unimplemented.
  - **Notes**: High-resolution downloads require session tokens/API key; Cloudflare protection on direct scraping.

- [ ] **Pexels** ([pexels.com](https://www.pexels.com/))
  - **Status**: Unimplemented (Blocked by Cloudflare).
  - **Notes**: Automated requests trigger Cloudflare 403 challenge without official API key.

- [x] **Burst by Shopify** ([shopify.com/stock-photos](https://www.shopify.com/stock-photos))
  - **CLI Provider**: `burst`
  - **Status**: Implemented & verified.
  - **Notes**: Search and direct full-resolution image downloads supported.

- [x] **Picography** ([picography.co](https://picography.co/))
  - **CLI Provider**: `picography`
  - **Status**: Implemented & verified.
  - **Notes**: Search and full master-resolution CC0 photo downloading supported.

- [ ] **Vecteezy** ([vecteezy.com](https://www.vecteezy.com/))
  - **Status**: Unimplemented.
  - **Notes**: Mixed free/pro licensing with attribution and auth requirements.

- [ ] **Freepik** ([freepik.com](https://www.freepik.com/))
  - **Status**: Unimplemented.
  - **Notes**: Freemium model requiring authentication and rate limiting.

- [x] **Picjumbo** ([picjumbo.com](https://picjumbo.com/))
  - **CLI Provider**: `picjumbo`
  - **Status**: Implemented & verified.
  - **Notes**: Search and full master-resolution photo downloading supported.

- [ ] **SplitShire** ([splitshire.com](https://www.splitshire.com/))
  - **Status**: Unimplemented.
  - **Notes**: Free stock photos by Daniel Nanescu (DigitalOcean Spaces CDN).

- [ ] **Rawpixel** ([rawpixel.com](https://www.rawpixel.com/))
  - **Status**: Unimplemented.
  - **Notes**: Freemium asset library with daily download limits and auth.

- [ ] **Kaboompics** ([kaboompics.com](https://kaboompics.com/))
  - **Status**: Unimplemented (Blocked by Cloudflare).
  - **Notes**: Free lifestyle stock photos; CLI access blocked by Cloudflare anti-bot mitigation.

- [x] **ISO Republic** ([isorepublic.com](https://isorepublic.com/))
  - **CLI Provider**: `isorepublic`
  - **Status**: Implemented & verified.
  - **Notes**: Search and full-resolution CC0 image downloading supported.

- [ ] **StockSnap.io** ([stocksnap.io](https://stocksnap.io/))
  - **Status**: Unimplemented (Blocked by Cloudflare).
  - **Notes**: Public domain CC0 images; Cloudflare challenge blocks direct CLI requests.

- [x] **Startup Stock Photos** ([startupstockphotos.com](http://startupstockphotos.com/))
  - **CLI Provider**: `startupstockphotos`
  - **Status**: Implemented & verified.
  - **Notes**: Search and full master-resolution CC0 photo downloading supported.

- [x] **Gratisography** ([gratisography.com](http://www.gratisography.com/))
  - **CLI Provider**: `gratisography`
  - **Status**: Implemented & verified.
  - **Notes**: Search and full master-resolution CC0 photo downloading supported.

- [x] **Public Domain Archive** ([publicdomainarchive.com](http://publicdomainarchive.com/))
  - **CLI Provider**: `publicdomainarchive`
  - **Status**: Implemented & verified.
  - **Notes**: Search and high-resolution CC0 photo downloading supported.

- [x] **Foodiesfeed** ([foodiesfeed.com](https://foodiesfeed.com/))
  - **CLI Provider**: `foodiesfeed`
  - **Status**: Implemented & verified.
  - **Notes**: Search and direct master resolution downloading from Cloudflare R2 supported.

- [ ] **Magdeleine** ([magdeleine.co](http://magdeleine.co/))
  - **Status**: Unimplemented.
  - **Notes**: Hand-picked high-res photos with vintage and nature aesthetics.

- [x] **Jay Mantri** ([jaymantri.com](http://jaymantri.com/))
  - **CLI Provider**: `jaymantri`
  - **Status**: Implemented & verified.
  - **Notes**: Search and full master-resolution CC0 photo downloading supported.

- [ ] **Death to Stock Photos** ([deathtothestockphoto.com](http://deathtothestockphoto.com/))
  - **Status**: Unimplemented.
  - **Notes**: Subscription and email-pack driven photo library.

- [ ] **Morguefile** ([morguefile.com](https://www.morguefile.com/))
  - **Status**: Unimplemented.
  - **Notes**: Community archive for creative reference and stock images.

- [ ] **Freeimages** ([freeimages.com](http://www.freeimages.com/))
  - **Status**: Unimplemented.
  - **Notes**: Large repository of free stock photography.

- [ ] **DeviantArt** ([deviantart.com](http://www.deviantart.com/))
  - **Status**: Unimplemented.
  - **Notes**: Community art platform; requires auth/API for asset retrieval.

- [ ] **Reshot** ([reshot.com](https://www.reshot.com/))
  - **Status**: Unimplemented.
  - **Notes**: Curated non-stock style photos, icons, and vector illustrations.
