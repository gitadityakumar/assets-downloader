#!/usr/bin/env bash
# install.sh — install pre-built `ast` binaries from GitHub Releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/gitadityakumar/assets-downloader/main/install.sh | bash
#
# Options (environment variables):
#   VERSION   Release version without leading "v" (default: latest)
#   PREFIX    Install directory for the binary (default: ~/.local/bin)
#   BINDIR    Alias for PREFIX
#   REPO      GitHub repo (default: gitadityakumar/assets-downloader)
#   TARGET    Force Zig-style target triple, e.g. x86_64-linux-musl
#   VERIFY    Set to 0 to skip SHA-256 verification (default: 1)
#   SUDO      Set to 0 to never use sudo (default: auto when PREFIX not writable)

set -euo pipefail

REPO="${REPO:-gitadityakumar/assets-downloader}"
APP_NAME="ast"
VERIFY="${VERIFY:-1}"
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR=""

cleanup() {
  if [ -n "${WORKDIR}" ] && [ -d "${WORKDIR}" ]; then
    rm -rf "${WORKDIR}"
  fi
}
trap cleanup EXIT

info()  { printf '==> %s\n' "$*" >&2; }
warn()  { printf 'warning: %s\n' "$*" >&2; }
die()   { printf 'error: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

http_get() {
  # $1 = url, $2 = output path (optional; stdout if omitted)
  local url="$1"
  local out="${2:-}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$out" ]; then
      curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$out"
    else
      curl -fsSL --proto '=https' --tlsv1.2 "$url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$out" ]; then
      wget -qO "$out" "$url"
    else
      wget -qO- "$url"
    fi
  else
    die "need curl or wget to download releases"
  fi
}

detect_os() {
  local os
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux) echo linux ;;
    *)
      die "unsupported OS '${os}'. Pre-built binaries are published for Linux only. Build from source: https://github.com/${REPO}"
      ;;
  esac
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo x86_64 ;;
    aarch64|arm64) echo aarch64 ;;
    armv7l|armv6l|armhf) echo arm ;;
    riscv64) echo riscv64 ;;
    *) die "unsupported architecture '${arch}'" ;;
  esac
}

# Prefer static musl when available (portable across distros).
resolve_target() {
  if [ -n "${TARGET:-}" ]; then
    echo "$TARGET"
    return
  fi
  local os arch
  os="$(detect_os)"
  arch="$(detect_arch)"
  case "${arch}-${os}" in
    x86_64-linux)  echo x86_64-linux-musl ;;
    aarch64-linux) echo aarch64-linux-musl ;;
    arm-linux)     echo arm-linux-musleabihf ;;
    riscv64-linux) echo riscv64-linux-musl ;;
    *) die "no pre-built binary for ${arch}-${os}" ;;
  esac
}

resolve_version() {
  if [ -n "${VERSION:-}" ]; then
    echo "${VERSION#v}"
    return
  fi
  local tag
  tag="$(http_get "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1)"
  [ -n "$tag" ] || die "could not resolve latest release for ${REPO} (has a release been published?)"
  echo "${tag#v}"
}

download_base_url() {
  local version="$1"
  echo "https://github.com/${REPO}/releases/download/v${version}"
}

sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    return 1
  fi
}

# Verify file against SHA256SUMS (or a single-line .sha256 file).
# $1 = path to file, $2 = path to sums, $3 = name to look up in the sums file
verify_sha256() {
  local file="$1"
  local sums_file="$2"
  local name="$3"
  local expected actual

  expected="$(awk -v n="$name" '$2 == n { print $1; exit }' "$sums_file")"
  if [ -z "$expected" ]; then
    # Some sum files use "./name" or only one field pair per line with path components
    expected="$(awk -v n="$name" '
      {
        base = $2
        sub(/.*\//, "", base)
        if (base == n || $2 == n) { print $1; exit }
      }' "$sums_file")"
  fi
  if [ -z "$expected" ]; then
    warn "no checksum entry for ${name}; skipping verification"
    return 0
  fi

  actual="$(sha256_of "$file")" || {
    warn "sha256sum/shasum not found; skipping verification"
    return 0
  }

  if [ "$actual" != "$expected" ]; then
    die "checksum mismatch for ${name} (expected ${expected}, got ${actual})"
  fi
  info "checksum OK (${name})"
}

fetch_checksums() {
  local base_url="$1"
  local asset="$2"
  local out="$3"
  if http_get "${base_url}/SHA256SUMS" "$out" 2>/dev/null; then
    return 0
  fi
  if http_get "${base_url}/${asset}.sha256" "$out" 2>/dev/null; then
    return 0
  fi
  return 1
}

install_binary() {
  local src="$1"
  local dest_dir="$2"
  local dest="${dest_dir}/${APP_NAME}"

  if [ ! -d "$dest_dir" ]; then
    if mkdir -p "$dest_dir" 2>/dev/null; then
      :
    elif [ "${SUDO:-1}" != "0" ] && command -v sudo >/dev/null 2>&1; then
      info "elevating privileges to create ${dest_dir}"
      sudo mkdir -p "$dest_dir"
    else
      die "cannot create ${dest_dir} (set PREFIX to a writable directory, e.g. PREFIX=\$HOME/.local/bin)"
    fi
  fi

  if [ -w "$dest_dir" ]; then
    install -m 755 "$src" "$dest"
  elif [ "${SUDO:-1}" != "0" ] && command -v sudo >/dev/null 2>&1; then
    info "elevating privileges to install into ${dest_dir}"
    sudo install -m 755 "$src" "$dest"
  else
    die "cannot write to ${dest_dir} (set PREFIX to a writable directory, e.g. PREFIX=\$HOME/.local/bin)"
  fi

  printf '%s\n' "$dest"
}

find_extracted_binary() {
  local root="$1"
  local asset="$2"
  if [ -x "${root}/${asset}/${APP_NAME}" ]; then
    echo "${root}/${asset}/${APP_NAME}"
    return
  fi
  if [ -x "${root}/${APP_NAME}" ]; then
    echo "${root}/${APP_NAME}"
    return
  fi
  # Portable fallback without relying on GNU find predicates
  local candidate
  for candidate in "${root}"/*/"${APP_NAME}" "${root}"/"${APP_NAME}"; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  return 1
}

main() {
  need_cmd uname
  need_cmd tar
  need_cmd install
  need_cmd mktemp
  need_cmd sed
  need_cmd head
  need_cmd awk
  need_cmd basename
  need_cmd tr

  local prefix target version base_url asset archive dest extracted

  prefix="${BINDIR:-${PREFIX:-${HOME}/.local/bin}}"
  target="$(resolve_target)"
  version="$(resolve_version)"
  base_url="$(download_base_url "$version")"
  asset="${APP_NAME}-${target}-${version}"
  archive="${asset}.tar.gz"

  WORKDIR="$(mktemp -d "${TMPDIR%/}/ast-install.XXXXXX")"
  info "installing ${APP_NAME} v${version} (${target}) → ${prefix}"

  if http_get "${base_url}/${archive}" "${WORKDIR}/${archive}" 2>/dev/null; then
    if [ "$VERIFY" != "0" ]; then
      if fetch_checksums "$base_url" "$asset" "${WORKDIR}/SHA256SUMS"; then
        verify_sha256 "${WORKDIR}/${archive}" "${WORKDIR}/SHA256SUMS" "$archive"
      else
        warn "could not download checksums; continuing without verification"
      fi
    fi

    tar -xzf "${WORKDIR}/${archive}" -C "${WORKDIR}"
    extracted="$(find_extracted_binary "$WORKDIR" "$asset")" \
      || die "archive did not contain ${APP_NAME}"
    dest="$(install_binary "$extracted" "$prefix")"
  else
    info "tarball not found; trying bare binary ${asset}"
    http_get "${base_url}/${asset}" "${WORKDIR}/${asset}" \
      || die "download failed for ${base_url}/${archive} (and bare binary). Is v${version} published for ${target}?"
    chmod +x "${WORKDIR}/${asset}"

    if [ "$VERIFY" != "0" ]; then
      if fetch_checksums "$base_url" "$asset" "${WORKDIR}/SHA256SUMS"; then
        verify_sha256 "${WORKDIR}/${asset}" "${WORKDIR}/SHA256SUMS" "$asset"
      else
        warn "could not download checksums; continuing without verification"
      fi
    fi
    dest="$(install_binary "${WORKDIR}/${asset}" "$prefix")"
  fi

  info "installed: ${dest}"

  case ":${PATH}:" in
    *":${prefix}:"*) ;;
    *)
      warn "${prefix} is not on your PATH. Add it, for example:"
      printf '    export PATH="%s:$PATH"\n' "$prefix" >&2
      ;;
  esac

  if [ -x "$dest" ]; then
    info "version: $("$dest" --version 2>/dev/null || true)"
  fi
  info "done. Try: ${APP_NAME} --help"
}

main "$@"
