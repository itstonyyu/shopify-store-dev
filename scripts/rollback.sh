#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# rollback.sh — Instant restore to any previous version
#
# Usage:
#   ./scripts/rollback.sh --list              # List available versions
#   ./scripts/rollback.sh --list -n 5         # Last 5 versions
#   ./scripts/rollback.sh --to <tag>          # Restore to a specific version
#   ./scripts/rollback.sh --to v3-push        # Example
#
# What it does:
#   1. Checks out the specified version from Git
#   2. Uploads ALL theme files from that version to the dev theme
#   3. Tags the rollback for audit trail
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

# --- Upload a single file to Shopify ---
upload_file() {
    local key="$1"
    local local_path="${THEME_DIR}/${key}"

    if [[ ! -f "$local_path" ]]; then
        return 1
    fi

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

    shopify_api PUT "themes/${DEV_THEME_ID}/assets.json" "$payload" >/dev/null
    rate_limit
}

# --- List versions ---
list_versions() {
    local count="${1:-20}"

    print_header "Available Versions"

    if [[ ! -d "${THEME_DIR}/.git" ]]; then
        print_err "No Git repo found. Run init-store.sh first."
        exit 1
    fi

    (
        cd "${THEME_DIR}"
        local tags
        tags=$(git tag --list --sort=-creatordate -n1 | head -"$count")

        if [[ -z "$tags" ]]; then
            print_warn "No tagged versions found."
            exit 0
        fi

        echo -e "${BOLD}Tag                 Date                    Message${NC}"
        echo "────────────────────────────────────────────────────────────────"

        git tag --list --sort=-creatordate --format='%(refname:short)|%(creatordate:short)|%(subject)' | \
            head -"$count" | while IFS='|' read -r tag date msg; do
            printf "  %-18s %-24s %s\n" "$tag" "$date" "$msg"
        done
    )

    echo ""
    echo -e "Usage: ${BOLD}./scripts/rollback.sh --to <tag>${NC}"
}

# --- Rollback to a specific version ---
rollback_to() {
    local target_tag="$1"

    load_config

    if [[ ! -d "${THEME_DIR}/.git" ]]; then
        print_err "No Git repo found. Run init-store.sh first."
        exit 1
    fi

    # Verify tag exists
    if ! (cd "${THEME_DIR}" && git rev-parse "$target_tag" &>/dev/null); then
        print_err "Tag '${target_tag}' not found."
        echo ""
        list_versions
        exit 1
    fi

    # --- Safety check ---
    print_info "Running safety check..."
    "${SCRIPT_DIR}/theme-guard.sh" "$DEV_THEME_ID" || {
        print_err "Safety check failed. Aborting."
        exit 1
    }

    print_header "Rolling Back to: ${target_tag}"

    # Step 1: Snapshot current state before rollback
    print_info "Snapshotting current state..."
    (
        cd "${THEME_DIR}"
        git add -A
        if ! git diff --cached --quiet 2>/dev/null; then
            git commit -q -m "Pre-rollback snapshot (before rolling back to ${target_tag})"
        fi
    )

    # Step 2: Checkout the target version
    print_info "Checking out ${target_tag}..."
    (
        cd "${THEME_DIR}"
        git checkout "$target_tag" -- .
    )

    # Step 3: Get list of all files in the restored version
    local files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
    done < <(cd "${THEME_DIR}" && find . -type f -not -path './.git/*' | sed 's|^\./||')

    print_info "Restoring ${#files[@]} files to Shopify..."

    # Step 4: Upload all files
    local success=0
    local fail=0

    for key in "${files[@]}"; do
        if upload_file "$key"; then
            success=$((success + 1))
            if (( success % 10 == 0 )); then
                echo -ne "\r  Uploaded: ${success}/${#files[@]}"
            fi
        else
            print_warn "Failed: ${key}"
            fail=$((fail + 1))
        fi
    done
    echo ""

    # Step 5: Handle files that exist on remote but not in the restored version
    # Get current remote assets
    print_info "Checking for files to remove..."
    local remote_assets
    remote_assets=$(shopify_api GET "themes/${DEV_THEME_ID}/assets.json") || {
        print_warn "Could not fetch remote asset list. Skipping cleanup."
        remote_assets=""
    }
    rate_limit

    if [[ -n "$remote_assets" ]]; then
        local remote_keys
        remote_keys=$(echo "$remote_assets" | jq -r '.assets[].key')
        local deleted=0

        while IFS= read -r remote_key; do
            [[ -z "$remote_key" ]] && continue
            if [[ ! -f "${THEME_DIR}/${remote_key}" ]]; then
                # File exists on remote but not in our restored version — delete it
                shopify_api DELETE "themes/${DEV_THEME_ID}/assets.json?asset%5Bkey%5D=${remote_key}" >/dev/null 2>&1 && {
                    deleted=$((deleted + 1))
                } || true
                rate_limit
            fi
        done <<< "$remote_keys"

        if [[ $deleted -gt 0 ]]; then
            print_ok "Removed ${deleted} files not in restored version"
        fi
    fi

    # Step 6: Commit and tag the rollback
    local rollback_tag="${target_tag}-rollback-$(date +%s)"
    (
        cd "${THEME_DIR}"
        git add -A
        git commit -q -m "Rollback to ${target_tag}" --allow-empty
        git tag -a "$rollback_tag" -m "Rolled back to ${target_tag}"
    )

    # --- Output ---
    print_header "Rollback Complete ✅"

    echo -e "${BOLD}Restored to:${NC}   ${target_tag}"
    echo -e "${BOLD}Rollback tag:${NC}  ${rollback_tag}"
    echo -e "${BOLD}Files:${NC}         ${success} uploaded, ${fail} failed"
    echo -e "${BOLD}Preview:${NC}"
    echo -e "  ${CYAN}https://${STORE}.myshopify.com/?preview_theme_id=${DEV_THEME_ID}${NC}"
}

# --- Usage ---
usage() {
    echo "Usage: $0 --list [-n <count>]"
    echo "       $0 --to <tag>"
    echo ""
    echo "  --list       List available version tags"
    echo "  -n <count>   Number of versions to show (default: 20)"
    echo "  --to <tag>   Rollback to a specific tagged version"
    exit 1
}

# --- Main ---
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    local action=""
    local target=""
    local count=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list|-l)
                action="list"
                shift
                ;;
            --to)
                action="rollback"
                target="$2"
                shift 2
                ;;
            -n)
                count="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_err "Unknown option: $1"
                usage
                ;;
        esac
    done

    case "$action" in
        list)
            load_config
            list_versions "$count"
            ;;
        rollback)
            if [[ -z "$target" ]]; then
                print_err "No target tag specified."
                usage
            fi
            rollback_to "$target"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
