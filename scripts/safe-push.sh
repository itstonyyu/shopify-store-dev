#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# safe-push.sh — Git-backed theme push with automatic snapshots
#
# Usage:
#   ./scripts/safe-push.sh <file1> [file2...] [-m "commit message"]
#   ./scripts/safe-push.sh templates/index.liquid sections/header.liquid
#   ./scripts/safe-push.sh assets/custom.css -m "Updated header styles"
#
# What it does:
#   1. Pre-push: downloads current theme state → Git commit (snapshot)
#   2. Uploads specified files to dev theme via Admin API
#   3. Post-push: downloads new state → Git commit + tag
#   4. Outputs preview URL
#
# File paths are relative to the theme root (e.g. templates/index.liquid)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() { echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"; }
print_ok()     { echo -e "${GREEN}✓${NC} $1"; }
print_warn()   { echo -e "${YELLOW}⚠${NC} $1"; }
print_err()    { echo -e "${RED}✗${NC} $1"; }
print_info()   { echo -e "${CYAN}→${NC} $1"; }

# --- Load config ---
load_config() {
    local config_file=".shopify-dev/config.json"
    if [[ ! -f "$config_file" ]]; then
        print_err "No config found. Run init-store.sh first."
        exit 1
    fi

    STORE=$(jq -r '.store' "$config_file")
    TOKEN=$(jq -r '.access_token' "$config_file")
    API_VERSION=$(jq -r '.api_version' "$config_file")
    DEV_THEME_ID=$(jq -r '.dev_theme_id' "$config_file")
    LIVE_THEME_ID=$(jq -r '.live_theme_id' "$config_file")
    THEME_DIR=".shopify-dev/theme"
}

# --- API helper ---
shopify_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local url="https://${STORE}.myshopify.com/admin/api/${API_VERSION}/${endpoint}"

    local args=(-s -w "\n%{http_code}" -X "$method"
        -H "X-Shopify-Access-Token: ${TOKEN}"
        -H "Content-Type: application/json")

    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi

    local response
    response=$(curl "${args[@]}" "$url")

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 400 ]]; then
        echo "$body" >&2
        return 1
    fi

    echo "$body"
}

rate_limit() { sleep 0.55; }

# --- Snapshot current state of specific files ---
snapshot_files() {
    local files=("$@")

    for key in "${files[@]}"; do
        local dir
        dir=$(dirname "${THEME_DIR}/${key}")
        mkdir -p "$dir"

        local asset_data
        asset_data=$(shopify_api GET "themes/${DEV_THEME_ID}/assets.json?asset%5Bkey%5D=${key}" 2>/dev/null) || {
            # File might not exist on remote yet (new file)
            continue
        }
        rate_limit

        local value
        value=$(echo "$asset_data" | jq -r '.asset.value // empty')
        if [[ -n "$value" ]]; then
            echo "$value" > "${THEME_DIR}/${key}"
        else
            local attachment
            attachment=$(echo "$asset_data" | jq -r '.asset.attachment // empty')
            if [[ -n "$attachment" ]]; then
                echo "$attachment" | base64 -d > "${THEME_DIR}/${key}" 2>/dev/null || \
                echo "$attachment" | base64 -D > "${THEME_DIR}/${key}" 2>/dev/null || true
            fi
        fi
    done
}

# --- Upload a file to Shopify ---
upload_file() {
    local key="$1"
    local local_path="${THEME_DIR}/${key}"

    if [[ ! -f "$local_path" ]]; then
        print_err "File not found: ${local_path}"
        return 1
    fi

    # Determine if binary or text based on file type
    local is_binary=false
    case "$key" in
        *.png|*.jpg|*.jpeg|*.gif|*.ico|*.svg|*.woff|*.woff2|*.ttf|*.eot|*.webp)
            is_binary=true
            ;;
    esac

    local payload
    if [[ "$is_binary" == true ]]; then
        local b64
        b64=$(base64 < "$local_path" | tr -d '\n')
        payload=$(jq -n --arg key "$key" --arg attachment "$b64" \
            '{asset: {key: $key, attachment: $attachment}}')
    else
        local content
        content=$(cat "$local_path")
        payload=$(jq -n --arg key "$key" --arg value "$content" \
            '{asset: {key: $key, value: $value}}')
    fi

    shopify_api PUT "themes/${DEV_THEME_ID}/assets.json" "$payload" >/dev/null || {
        print_err "Failed to upload: ${key}"
        return 1
    }
    rate_limit
}

# --- Generate next version tag ---
next_version_tag() {
    local latest
    latest=$(cd "${THEME_DIR}" && git tag --list 'v*' --sort=-version:refname | head -1)

    if [[ -z "$latest" ]]; then
        echo "v1"
        return
    fi

    # Extract number, handling formats like v1, v2-push, v0-init
    local num
    num=$(echo "$latest" | sed 's/^v//' | sed 's/-.*//')

    if [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "v$((num + 1))"
    else
        echo "v1"
    fi
}

# --- Usage ---
usage() {
    echo "Usage: $0 <file1> [file2...] [-m \"commit message\"]"
    echo ""
    echo "  Files are theme-relative paths (e.g. templates/index.liquid)"
    echo "  -m    Commit message (optional, defaults to file list)"
    echo ""
    echo "Example:"
    echo "  $0 templates/index.liquid sections/header.liquid -m 'Redesign homepage'"
    exit 1
}

# --- Main ---
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    load_config

    # Parse args
    local files=()
    local message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--message)
                message="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        print_err "No files specified."
        usage
    fi

    # Default commit message
    if [[ -z "$message" ]]; then
        message="Push: ${files[*]}"
    fi

    # --- Safety check ---
    print_info "Running safety check on dev theme ${DEV_THEME_ID}..."
    "${SCRIPT_DIR}/theme-guard.sh" "$DEV_THEME_ID" || {
        print_err "Safety check failed. Aborting."
        exit 1
    }

    # --- Pre-push snapshot ---
    print_header "Pre-Push Snapshot"
    print_info "Downloading current state of ${#files[@]} file(s)..."

    snapshot_files "${files[@]}"

    (
        cd "${THEME_DIR}"
        git add -A
        if ! git diff --cached --quiet 2>/dev/null; then
            git commit -q -m "Pre-push snapshot: ${message}"
            print_ok "Pre-push state committed"
        else
            print_info "No changes to snapshot (clean state)"
        fi
    )

    # --- Upload files ---
    print_header "Pushing Files"

    local success=0
    local fail=0

    for key in "${files[@]}"; do
        print_info "Uploading: ${key}"
        if upload_file "$key"; then
            print_ok "Uploaded: ${key}"
            success=$((success + 1))
        else
            fail=$((fail + 1))
        fi
    done

    echo ""
    print_info "Results: ${success} uploaded, ${fail} failed"

    if [[ $fail -gt 0 && $success -eq 0 ]]; then
        print_err "All uploads failed. Check your files and permissions."
        exit 1
    fi

    # --- Post-push snapshot ---
    print_header "Post-Push Snapshot"
    print_info "Downloading updated state..."

    snapshot_files "${files[@]}"

    local version_tag
    version_tag=$(next_version_tag)

    (
        cd "${THEME_DIR}"
        git add -A
        if ! git diff --cached --quiet 2>/dev/null; then
            git commit -q -m "Post-push: ${message}"
        fi
        git tag -a "${version_tag}-push" -m "${message}"
    )

    print_ok "Tagged as ${version_tag}-push"

    # --- Output ---
    print_header "Push Complete ✅"

    echo -e "${BOLD}Files pushed:${NC}  ${success}/${#files[@]}"
    echo -e "${BOLD}Version:${NC}       ${version_tag}-push"
    echo -e "${BOLD}Preview:${NC}"
    echo -e "  ${CYAN}https://${STORE}.myshopify.com/?preview_theme_id=${DEV_THEME_ID}${NC}"
    echo ""
    echo -e "To undo:  ${BOLD}./scripts/rollback.sh --to ${version_tag}-push${NC}"
    echo -e "To diff:  ${BOLD}./scripts/diff.sh HEAD~1 HEAD${NC}"
}

main "$@"
