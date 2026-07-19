#!/bin/bash

# This catalog is intentionally local and versioned. Do not accept package URLs,
# checksums, executables, or argument lists from the environment.
MACOS_NODE_MINIMUM_VERSION='24.4.0'
MACOS_NODE_VERSION='24.4.0'
MACOS_CLOUDFLARED_VERSION='2025.6.1'
MACOS_DOCKER_DESKTOP_APP_PATH='/Applications/Docker.app'
MACOS_DOCKER_READY_TIMEOUT_SECONDS=120
MACOS_DOCKER_ARM64_FILENAME='Docker-AppleSilicon.dmg'
MACOS_DOCKER_ARM64_URL='https://desktop.docker.com/mac/main/arm64/226246/Docker.dmg'
MACOS_DOCKER_ARM64_SHA256='5f08b5e3e7e33cca7c364a585b15bcea4947159606453095a8a09bcc0fd44005'
MACOS_DOCKER_X86_64_FILENAME='Docker-Intel.dmg'
MACOS_DOCKER_X86_64_URL='https://desktop.docker.com/mac/main/amd64/226246/Docker.dmg'
MACOS_DOCKER_X86_64_SHA256='a88a63b4c74d5e85c9d41ec9b4065472b8812c0e3dfb63e31fdda3d3b1268a8b'

macos_json_state() {
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json
import sys

state = {"tool_id": sys.argv[1], "status": sys.argv[2]}
if sys.argv[3]:
    state["version"] = sys.argv[3]
print(json.dumps(state, separators=(",", ":")))
PY
}

macos_tool_command() {
  case "$1" in
    node_lts) printf '%s\n' 'node' ;;
    cloudflared) printf '%s\n' 'cloudflared' ;;
    *) return 64 ;;
  esac
}

macos_tool_version() {
  case "$1" in
    node_lts)
      if [ -n "${TOOLCHAIN_NODE_VERSION+x}" ]; then
        [ "$TOOLCHAIN_NODE_VERSION" = 'missing' ] && return 1
        printf '%s\n' "$TOOLCHAIN_NODE_VERSION"
        return 0
      fi
      ;;
    cloudflared)
      if [ -n "${TOOLCHAIN_CLOUDFLARED_VERSION+x}" ]; then
        [ "$TOOLCHAIN_CLOUDFLARED_VERSION" = 'missing' ] && return 1
        printf '%s\n' "$TOOLCHAIN_CLOUDFLARED_VERSION"
        return 0
      fi
      ;;
    *) return 64 ;;
  esac

  local command
  command="$(macos_tool_command "$1")" || return 64
  command -v "$command" >/dev/null 2>&1 || return 1
  "$command" --version 2>/dev/null
}

macos_node_version_status() {
  local version="$1" normalized major minor patch min_major min_minor min_patch
  if [[ "$version" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
  else
    printf '%s\n' 'failed'
    return 0
  fi
  IFS=. read -r min_major min_minor min_patch <<EOF
$MACOS_NODE_MINIMUM_VERSION
EOF
  if [ "$major" -ne "$min_major" ] || [ "$minor" -lt "$min_minor" ] || { [ "$minor" -eq "$min_minor" ] && [ "$patch" -lt "$min_patch" ]; }; then
    printf '%s\n' 'outdated'
  else
    printf '%s\n' 'ready'
  fi
}

get_macos_tool_state() {
  local tool_id="$1" version status
  case "$tool_id" in
    node_lts|cloudflared) ;;
    *) macos_json_state "$tool_id" failed; return 64 ;;
  esac
  if ! version="$(macos_tool_version "$tool_id")"; then
    macos_json_state "$tool_id" missing
    return 0
  fi
  [ -n "$version" ] || { macos_json_state "$tool_id" failed; return 0; }
  if [ "$tool_id" = node_lts ]; then
    status="$(macos_node_version_status "$version")"
  else
    status=ready
  fi
  macos_json_state "$tool_id" "$status" "$version"
}

macos_architecture() {
  local architecture="${TOOLCHAIN_ARCH:-$(uname -m)}"
  case "$architecture" in
    arm64|x86_64) printf '%s\n' "$architecture" ;;
    *) return 65 ;;
  esac
}

macos_has_homebrew() {
  case "${TOOLCHAIN_HAS_BREW:-}" in
    true) return 0 ;;
    false) return 1 ;;
    '') command -v brew >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

macos_brew_formula() {
  case "$1" in
    node_lts) printf '%s\n' 'node@24' ;;
    cloudflared) printf '%s\n' 'cloudflared' ;;
    *) return 64 ;;
  esac
}

macos_vendor_filename() {
  local tool_id="$1" architecture="$2"
  case "$tool_id:$architecture" in
    node_lts:arm64|node_lts:x86_64) printf '%s\n' "node-v${MACOS_NODE_VERSION}.pkg" ;;
    cloudflared:arm64) printf '%s\n' 'cloudflared-arm64.pkg' ;;
    cloudflared:x86_64) printf '%s\n' 'cloudflared-amd64.pkg' ;;
    *) return 65 ;;
  esac
}

macos_vendor_url() {
  local filename
  filename="$(macos_vendor_filename "$1" "$2")" || return $?
  case "$1" in
    node_lts) printf '%s\n' "https://nodejs.org/download/release/v${MACOS_NODE_VERSION}/${filename}" ;;
    cloudflared) printf '%s\n' "https://github.com/cloudflare/cloudflared/releases/download/${MACOS_CLOUDFLARED_VERSION}/${filename}" ;;
    *) return 64 ;;
  esac
}

macos_vendor_sha256() {
  case "$1:$2" in
    node_lts:arm64|node_lts:x86_64) printf '%s\n' 'bff7a6239d9c5a809f4fe4e8585144ccc930533d88f8ef2935afa0d5aa86c244' ;;
    cloudflared:arm64) printf '%s\n' 'c42f76d60c2a34df55589cbfb4f68a953610221a9abc2114181dfa15bf008731' ;;
    cloudflared:x86_64) printf '%s\n' '7f12892073506438fabab6f9fc075332f4f57e1ed30ba8c1ddf71f86f743a63f' ;;
    *) return 65 ;;
  esac
}

macos_vendor_checksum_source() {
  case "$1" in
    node_lts) printf '%s\n' "https://nodejs.org/download/release/v${MACOS_NODE_VERSION}/SHASUMS256.txt" ;;
    cloudflared) printf '%s\n' "https://github.com/cloudflare/cloudflared/releases/tag/${MACOS_CLOUDFLARED_VERSION}" ;;
    *) return 64 ;;
  esac
}

macos_vendor_install() (
  local tool_id="$1" architecture="$2" filename url expected_sha256 work_dir package_path
  macos_vendor_cleanup() {
    if [ -n "${work_dir:-}" ] && [ -e "$work_dir" ]; then
      rm -rf "$work_dir"
    fi
  }
  filename="$(macos_vendor_filename "$tool_id" "$architecture")" || return $?
  url="$(macos_vendor_url "$tool_id" "$architecture")" || return $?
  expected_sha256="$(macos_vendor_sha256 "$tool_id" "$architecture")" || return $?
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/course-toolchain.XXXXXX")" || return 1
  trap macos_vendor_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  package_path="$work_dir/$filename"

  curl --fail --location --proto '=https' --tlsv1.2 --output "$package_path" "$url" || return 1
  printf '%s  %s\n' "$expected_sha256" "$package_path" | shasum -a 256 -c - || return 1

  case "$tool_id" in
    node_lts|cloudflared)
      sudo /usr/sbin/installer -pkg "$package_path" -target / || return 1
      ;;
    *) return 64 ;;
  esac
)

install_macos_tool() {
  local tool_id="$1" confirmation="$2" architecture formula state
  case "$tool_id" in
    node_lts|cloudflared) ;;
    *) macos_json_state "$tool_id" failed; return 64 ;;
  esac
  if [ "$confirmation" != yes ]; then
    macos_json_state "$tool_id" skipped
    return 2
  fi
  architecture="$(macos_architecture)" || { macos_json_state "$tool_id" failed; return 65; }
  state="$(get_macos_tool_state "$tool_id")" || return 1
  case "$state" in
    *'"status":"ready"'*) printf '%s\n' "$state"; return 0 ;;
  esac

  if macos_has_homebrew; then
    formula="$(macos_brew_formula "$tool_id")" || return 64
    brew --version >/dev/null 2>&1 || { macos_json_state "$tool_id" failed; return 1; }
    brew install "$formula" || { macos_json_state "$tool_id" failed; return 1; }
    macos_json_state "$tool_id" needs_restart
    return 0
  else
    macos_vendor_install "$tool_id" "$architecture" || { macos_json_state "$tool_id" failed; return 1; }
  fi

  state="$(get_macos_tool_state "$tool_id")" || return 1
  case "$state" in
    *'"status":"ready"'*) printf '%s\n' "$state" ;;
    *'"status":"missing"'*) macos_json_state "$tool_id" needs_restart ;;
    *) macos_json_state "$tool_id" failed; return 1 ;;
  esac
}

docker_macos_artifact() {
  case "$(macos_architecture)" in
    arm64) printf '%s\n' "$MACOS_DOCKER_ARM64_FILENAME" ;;
    x86_64) printf '%s\n' "$MACOS_DOCKER_X86_64_FILENAME" ;;
    *) return 65 ;;
  esac
}

macos_docker_download_url() {
  case "$1" in
    arm64) printf '%s\n' "$MACOS_DOCKER_ARM64_URL" ;;
    x86_64) printf '%s\n' "$MACOS_DOCKER_X86_64_URL" ;;
    *) return 65 ;;
  esac
}

macos_docker_sha256() {
  case "$1" in
    arm64) printf '%s\n' "$MACOS_DOCKER_ARM64_SHA256" ;;
    x86_64) printf '%s\n' "$MACOS_DOCKER_X86_64_SHA256" ;;
    *) return 65 ;;
  esac
}

verify_macos_docker() {
  command -v docker >/dev/null 2>&1 || return 1
  docker version >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1
}

wait_macos_docker_ready() {
  local timeout_seconds="$1" deadline
  case "$timeout_seconds" in
    ''|*[!0-9]*) return 64 ;;
  esac
  if [ "$timeout_seconds" -lt 1 ] || [ "$timeout_seconds" -gt "$MACOS_DOCKER_READY_TIMEOUT_SECONDS" ]; then
    return 64
  fi

  deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if verify_macos_docker; then
      macos_json_state docker_desktop ready
      return 0
    fi
    sleep 1
  done

  macos_json_state docker_desktop failed
  return 1
}

install_macos_docker_desktop() (
  local confirmation="$1" architecture artifact filename url expected_sha256 work_dir mount_dir mounted=false
  macos_docker_cleanup() {
    if [ "$mounted" = true ]; then
      hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    if [ -n "${work_dir:-}" ] && [ -e "$work_dir" ]; then
      rm -rf "$work_dir"
    fi
  }

  if [ "$confirmation" != yes ]; then
    macos_json_state docker_desktop skipped
    return 2
  fi
  if verify_macos_docker; then
    macos_json_state docker_desktop ready
    return 0
  fi

  architecture="$(macos_architecture)" || { macos_json_state docker_desktop failed; return 65; }
  artifact="$(docker_macos_artifact)" || { macos_json_state docker_desktop failed; return 65; }
  url="$(macos_docker_download_url "$architecture")" || { macos_json_state docker_desktop failed; return 65; }
  expected_sha256="$(macos_docker_sha256 "$architecture")" || { macos_json_state docker_desktop failed; return 65; }
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/course-toolchain-docker.XXXXXX")" || { macos_json_state docker_desktop failed; return 1; }
  mount_dir="$work_dir/mount"
  filename="$work_dir/$artifact"
  trap macos_docker_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  curl --fail --location --proto '=https' --tlsv1.2 --output "$filename" "$url" || { macos_json_state docker_desktop failed; return 1; }
  printf '%s  %s\n' "$expected_sha256" "$filename" | shasum -a 256 -c - || { macos_json_state docker_desktop failed; return 1; }
  mkdir -p "$mount_dir" || { macos_json_state docker_desktop failed; return 1; }
  hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$filename" || { macos_json_state docker_desktop failed; return 1; }
  mounted=true
  if [ ! -d "$mount_dir/Docker.app" ]; then
    macos_json_state docker_desktop failed
    return 1
  fi
  if [ -e "$MACOS_DOCKER_DESKTOP_APP_PATH" ]; then
    macos_json_state docker_desktop failed
    return 1
  fi

  sudo ditto "$mount_dir/Docker.app" "$MACOS_DOCKER_DESKTOP_APP_PATH" || { macos_json_state docker_desktop failed; return 1; }
  open "$MACOS_DOCKER_DESKTOP_APP_PATH" || { macos_json_state docker_desktop failed; return 1; }
  wait_macos_docker_ready "$MACOS_DOCKER_READY_TIMEOUT_SECONDS"
)
