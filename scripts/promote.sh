#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# promote.sh — Safely promote dev theme → live
#
# Usage:
#   ./scripts/promote.sh              # Interactive confirmation
#   ./scripts/promote.sh --yes        # Skip confirmation (for CI/automation)
#
# What it does:
#   1. Snapshots the current LIVE theme (safety net)
#   2. Copies all dev theme files to the live theme
#   3. Tags the promotion in Git
#   4. Outputs rollback command
#
# ⚠️ This modifies the LIVE theme. Use with extreme care.
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
    DEV_THEME_NAME=$(jq -r '.dev_theme_name' "$config_file")
    LIVE_THEME_NAME=$(jq -r '.live_theme_name' "$config_file")
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

# --- Download all assets from a theme to a directory ---
download_theme() {
    local theme_id="$1"
    local target_dir="$2"

    local assets_json
    assets_json=$(shopify_api GET "themes/${theme_id}/assets.json") || {
        print_err "Failed to list assets for theme ${theme_id}"
        return 1
    }
    rate_limit

    local asset_keys
    asset_keys=$(echo "$assets_json" | jq -r '.assets[].key')
    local count=0

    while IFS= read -r key; do
        [[ -z "$key" ]] && continue

        local dir
        dir=$(dirname "${target_dir}/${key}")
        mkdir -p "$dir"

        local asset_data
        asset_data=$(shopify_api GET "themes/${theme_id}/assets.json?asset%5Bkey%5D=${key}") || {
            print_warn "Failed to download: ${key}"
            continue
        }
        rate_limit

        local value
        value=$(echo "$asset_data" | jq -r '.asset.value // empty')
        if [[ -n "$value" ]]; then
            echo "$value" > "${target_dir}/${key}"
        else
            local attachment
            attachment=$(echo "$asset_data" | jq -r '.asset.attachment // empty')
            if [[ -n "$attachment" ]]; then
                echo "$attachment" | base64 -d > "${target_dir}/${key}" 2>/dev/null || \
                echo "$attachment" | base64 -D > "${target_dir}/${key}" 2>/dev/null || true
            fi
        fi

        count=$((count + 1))
        if (( count % 10 == 0 )); then
            echo -ne "\r  Downloaded: ${count} files"
        fi
    done <<< "$asset_keys"
    echo ""

    echo "$count"
}

# --- Upload a file to a specific theme ---
upload_to_theme() {
    local theme_id="$1"
    local key="$2"
    local source_dir="$3"
    local local_path="${source_dir}/${key}"

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

    shopify_api PUT "themes/${theme_id}/assets.json" "$payload" >/dev/null
    rate_limit
}

# --- Main ---
main() {
    local skip_confirm=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)
                skip_confirm=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--yes]"
                echo ""
                echo "Promotes the dev theme to live."
                echo "  --yes    Skip confirmation prompt"
                exit 0
                ;;
            *)
                print_err "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    load_config

    # --- Verify themes still exist and have correct roles ---
    print_header "Pre-Promotion Checks"

    # Re-verify live theme (CRITICAL: never trust cached data)
    local live_check
    live_check=$(shopify_api GET "themes/${LIVE_THEME_ID}.json") || {
        print_err "Could not verify live theme. Aborting."
        exit 1
    }
    rate_limit

    local actual_live_role
    actual_live_role=$(echo "$live_check" | jq -r '.theme.role')
    local actual_live_name
    actual_live_name=$(echo "$live_check" | jq -r '.theme.name')

    if [[ "$actual_live_role" != "main" ]]; then
        print_err "Theme ${LIVE_THEME_ID} is no longer the live theme (role: ${actual_live_role})."
        print_err "Run init-store.sh again to update your config."
        exit 1
    fi
    print_ok "Live theme verified: ${actual_live_name} (role: main)"

    # Verify dev theme
    "${SCRIPT_DIR}/theme-guard.sh" "$DEV_THEME_ID" || {
        print_err "Dev theme ${DEV_THEME_ID} check failed. Is it still the live theme?"
        exit 1
    }

    # --- Confirmation ---
    print_header "⚠️  PROMOTION WARNING"

    echo -e "${YELLOW}You are about to copy:${NC}"
    echo -e "  ${BOLD}FROM:${NC} ${DEV_THEME_NAME} (ID: ${DEV_THEME_ID}) [dev]"
    echo -e "  ${BOLD}TO:${NC}   ${actual_live_name} (ID: ${LIVE_THEME_ID}) ${RED}[LIVE]${NC}"
    echo ""
    echo -e "${YELLOW}This will overwrite the live theme files.${NC}"
    echo -e "${YELLOW}A snapshot of the current live theme will be saved first.${NC}"
    echo ""

    if [[ "$skip_confirm" != true ]]; then
        echo -en "${BOLD}Type 'PROMOTE' to confirm: ${NC}"
        read -r confirmation
        if [[ "$confirmation" != "PROMOTE" ]]; then
            print_info "Aborted. No changes made."
            exit 0
        fi
    else
        print_warn "Skipping confirmation (--yes flag)"
    fi

    # --- Step 1: Snapshot live theme ---
    print_header "Step 1: Snapshotting Live Theme"
    print_info "Downloading current live theme state..."

    local live_backup_dir=".shopify-dev/live-backup-$(date +%s)"
    mkdir -p "$live_backup_dir"

    local live_file_count
    live_file_count=$(download_theme "$LIVE_THEME_ID" "$live_backup_dir")
    print_ok "Live theme snapshot: ${live_file_count} files saved to ${live_backup_dir}"

    # Commit the pre-promotion state
    local pre_promote_tag="pre-promote-$(date +%Y%m%d-%H%M%S)"
    (
        cd "${THEME_DIR}"
        git add -A
        if ! git diff --cached --quiet 2>/dev/null; then
            git commit -q -m "Pre-promotion snapshot"
        fi
        git tag -a "$pre_promote_tag" -m "Live theme state before promotion"
    )
    print_ok "Tagged pre-promotion state as: ${pre_promote_tag}"

    # --- Step 2: Copy dev files to live ---
    print_header "Step 2: Promoting Dev → Live"

    local dev_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && dev_files+=("$file")
    done < <(cd "${THEME_DIR}" && find . -type f -not -path './.git/*' | sed 's|^\./||')

    print_info "Uploading ${#dev_files[@]} files to live theme..."

    local success=0
    local fail=0

    for key in "${dev_files[@]}"; do
        if upload_to_theme "$LIVE_THEME_ID" "$key" "$THEME_DIR"; then
            success=$((success + 1))
            if (( success % 10 == 0 )); then
                echo -ne "\r  Uploaded: ${success}/${#dev_files[@]}"
            fi
        else
            print_warn "Failed: ${key}"
            fail=$((fail + 1))
        fi
    done
    echo ""

    # --- Step 3: Tag the promotion ---
    local promote_tag="promote-$(date +%Y%m%d-%H%M%S)"
    (
        cd "${THEME_DIR}"
        git tag -a "$promote_tag" -m "Promoted dev to live"
    )

    # Clean up backup dir (already in Git)
    rm -rf "$live_backup_dir"

    # --- Output ---
    print_header "Promotion Complete 🚀"

    echo -e "${BOLD}Promoted:${NC}       ${DEV_THEME_NAME} → ${actual_live_name}"
    echo -e "${BOLD}Files:${NC}          ${success} uploaded, ${fail} failed"
    echo -e "${BOLD}Promotion tag:${NC}  ${promote_tag}"
    echo -e "${BOLD}Pre-promote:${NC}    ${pre_promote_tag}"
    echo ""
    echo -e "${BOLD}Live URL:${NC}"
    echo -e "  ${CYAN}https://${STORE}.myshopify.com${NC}"
    echo ""
    echo -e "${YELLOW}To rollback to the pre-promotion state:${NC}"
    echo -e "  ${BOLD}./scripts/rollback.sh --to ${pre_promote_tag}${NC}"
    echo -e "  ${BOLD}# Then re-promote the restored version${NC}"

    if [[ $fail -gt 0 ]]; then
        echo ""
        print_warn "${fail} files failed to upload. Check the errors above."
        print_warn "The live theme may be in a partial state."
        print_warn "Consider rolling back: ./scripts/rollback.sh --to ${pre_promote_tag}"
    fi
}

main "$@"
