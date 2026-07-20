<div align="center">

[![ast](assets/banner.svg)](#readme)

[![Version](https://img.shields.io/badge/version-1.0.0-brightgreen?style=for-the-badge)](#installation)
[![Zig](https://img.shields.io/badge/Zig-0.16+-f7a41d?style=for-the-badge&logo=zig&logoColor=white)](https://ziglang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey?style=for-the-badge)](#installation)

</div>

**ast** (Asset Downloader) is a feature-focused command-line tool for searching and downloading public image assets from multiple providers. It is written in [Zig](https://ziglang.org) 0.16, ships as a single native binary, and is designed for both interactive use and scripting.

* [INSTALLATION](#installation)
    * [Build from source](#build-from-source)
    * [Install to a prefix](#install-to-a-prefix)
    * [Dependencies](#dependencies)
* [USAGE AND OPTIONS](#usage-and-options)
    * [Synopsis](#synopsis)
    * [Examples](#examples)
    * [Options](#options)
    * [Exit status](#exit-status)
* [PROVIDERS](#providers)
    * [Supported providers](#supported-providers)
    * [Adding a provider](#adding-a-provider)
* [INTERACTIVE MODE](#interactive-mode)
* [PROJECT LAYOUT](#project-layout)
* [CONTRIBUTING](#contributing)
* [DISCLAIMER](#disclaimer)
* [LICENSE](#license)

# INSTALLATION

There are no pre-built release binaries yet. Build from source with Zig.

## Build from source

**Requirements:** [Zig](https://ziglang.org/download/) **0.16.0** or newer.

```bash
git clone https://github.com/gitadityakumar/assets-downloader.git
cd assets-downloader
zig build                        # debug → zig-out/bin/ast
zig build -Doptimize=ReleaseFast # optimized release build
zig build test                   # unit tests
```

Run without installing:

```bash
zig build run -- s aura "cyberpunk fox"
# or
./zig-out/bin/ast s aura "cyberpunk fox"
```

## Install to a prefix

```bash
zig build -Doptimize=ReleaseFast --prefix ~/.local
# → ~/.local/bin/ast
```

Ensure `~/.local/bin` is on your `PATH`.

## Dependencies

**ast** has no runtime package dependencies. Networking and TLS use the Zig standard library (`std.http.Client`).

| Dependency | Required | Notes |
|------------|----------|--------|
| Zig ≥ 0.16.0 | Yes (build time) | Compiler and standard library |
| Network access | Yes (runtime) | Provider search and downloads |

# USAGE AND OPTIONS

## Synopsis

```text
ast                              # interactive mode
ast s <provider> <query> [OPTIONS]
ast -s <provider> <query> [OPTIONS]
ast help
ast version
```

Tip: use `CTRL`+`F` (or `Command`+`F`) to search this page.

## Examples

```bash
# Interactive keyboard UI
ast

# Search Aura.build
ast s aura "cyberpunk fox"
ast -s aura "cyberpunk fox"

# Search Unsplash
ast s unsplash "golden retriever"

# Limit results, machine-readable JSON
ast s aura "cyberpunk fox" -l 5
ast s aura "cyberpunk fox" -j
ast -sjl 3 aura "cat"

# First result only: URL, prompt, or download
ast s aura "cyberpunk fox" -f -u
ast s aura "cyberpunk fox" -f -p
ast s aura "cyberpunk fox" -f -d -o ./downloads
ast -sfu unsplash "mountains"
```

Combined short options are supported (POSIX-style), e.g. `-sjl 3` ≡ `--search --json --limit 3`.

## Options

```text
-h, --help              Print this help text and exit
-v, --version           Print program version and exit

-s, --search            Run search (alternative to subcommand s)
-P, --provider <id>     Provider id (or pass as first positional after s)
-l, --limit <n>         Number of results (default: 10)
-f, --first             Only the highest-ranked result

-j, --json              Machine-readable JSON output
-u, --url               Print image URL only
-p, --prompt            Print generation prompt only (when available)
-d, --download          Download result image(s) to the output directory
-o, --output <dir>      Download directory (default: downloads)

-q, --quiet             Suppress non-essential messages
```

| Mode | Behavior |
|------|----------|
| Default search | Human-readable list on stdout; progress on stderr |
| `--json` | JSON objects (one asset per result) |
| `--url` | Image URL only (one line per result) |
| `--prompt` | Prompt text only when the provider supplies one |
| `--download` | Saves files under `--output` (default `downloads/`) |
| `--first` | Restricts to a single top result (useful with `-u` / `-p` / `-d`) |

Provider and query may be given as positionals after `s` / `-s`, or with `-P` / `--provider` plus the query as remaining positionals.

## Exit status

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Usage / validation error |
| `2` | Network error |
| `3` | Not found |
| `4` | Rate limited |

# PROVIDERS

**ast** uses a small pluggable provider layer. Each provider implements search (and optional download / field accessors) against a public asset source.

## Supported providers

| Id | Name | Description | Notes |
|----|------|-------------|--------|
| `aura` | [Aura.build](https://www.aura.build) | Public design assets via Supabase PostgREST | Tokenized match on title, description, keywords. See [docs/AURA_API.md](docs/AURA_API.md). |
| `unsplash` | [Unsplash](https://unsplash.com) | Public photo search and free library downloads | See [docs/unsplash.md](docs/unsplash.md). Prefer the [official Unsplash API](https://unsplash.com/developers) for production apps. |

List providers at runtime via `ast help` (printed under **PROVIDERS**).

Providers may rate-limit or block automated clients. Respect each service’s terms of use, attribution rules, and rate limits.

## Adding a provider

1. Implement search / download / field accessors in `src/providers/<id>.zig`
2. Register the provider in `src/providers/registry.zig`
3. Wire dispatch in `src/commands/search.zig` and `src/interactive.zig`
4. Document behavior under `docs/` when the integration is non-trivial

Keep the normalized [`Asset`](src/asset.zig) model stable so JSON and download paths stay consistent across providers.

# INTERACTIVE MODE

Launch with no arguments:

```bash
ast
```

Flow:

1. Select a provider from the menu
2. Enter a search query
3. Pick a result by number
4. Download, print prompt, print URL, search again, or quit

Keyboard: number + Enter · **S** search again · **Q** quit.

# PROJECT LAYOUT

```text
src/
  main.zig                 Entry point and command routing
  args.zig                 Flag parsing (combined short options)
  asset.zig                Normalized Asset / SearchResult model
  config.zig               Version, defaults, user-agent
  download.zig             Save response bodies to disk
  http_client.zig          HTTP helpers (cookies, redirects)
  http_util.zig            Shared HTTPS utilities
  interactive.zig          Interactive menus
  stdio.zig                stdout / stderr / line input
  commands/
    help.zig
    search.zig
  providers/
    registry.zig
    aura.zig
    unsplash.zig
assets/                    README banner and static assets
docs/                      Provider implementation notes
```

# CONTRIBUTING

Bug reports, provider ideas, and pull requests are welcome.

1. Fork and clone the repository
2. Create a focused branch
3. Run `zig build` and `zig build test`
4. Open a pull request with a clear description of the change

Prefer small patches that match the existing style in `src/`. For provider work, include a short note in `docs/` when endpoints or auth models are non-obvious.

# DISCLAIMER

**ast** is not affiliated with, endorsed by, or sponsored by Aura.build, Unsplash, or any other third-party service it can reach.

You are responsible for complying with each provider’s terms of service, license, and attribution requirements when searching or downloading assets. Do not use this tool to abuse rate limits, bypass access controls you are not authorized to use, or redistribute content in ways the original license forbids.

# LICENSE

This project is licensed under the [MIT License](LICENSE).
