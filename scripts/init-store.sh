#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# init-store.sh — One-time Shopify store setup for safe theme development
#
# Usage: ./init-store.sh <store-name> <admin-api-access-token>
#
# Example: ./init-store.sh odd-pieces-puzzles shpat_xxxxxxxxxxxxx
#
# What it does:
#   1. Validates connection to the store via Admin API
#   2. Lists all themes, identifies live vs dev themes
#   3. Creates a dev theme if none exists
#   4. Initializes a Git repo for version control
#   5. Downloads current dev theme state as initial snapshot
#   6. Saves config to .shopify-dev/config.json
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_VERSION="2024-01"

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

# --- Dependency check ---
check_deps() {
    local missing=()
    for cmd in curl git jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_err "Missing required tools: ${missing[*]}"
        echo "  Install them and try again."
        exit 1
    fi
}

# --- Usage ---
usage() {
    echo "Usage: $0 <store-name> <access-token>"
    echo ""
    echo "  store-name     Your Shopify store name (e.g. 'my-store' from my-store.myshopify.com)"
    echo "  access-token   Admin API access token from your Custom App"
    echo ""
    echo "See references/setup-guide.md for how to create a Custom App and get a token."
    exit 1
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
        print_err "API error (HTTP $http_code): $endpoint"
        echo "$body" | jq . 2>/dev/null || echo "$body"
        return 1
    fi

    echo "$body"
}

# --- Rate limit helper (Shopify REST = 2 req/sec) ---
rate_limit() {
    sleep 0.55
}

# --- Main ---
main() {
    check_deps

    if [[ $# -lt 2 ]]; then
        usage
    fi

    STORE="$1"
    TOKEN="$2"

    # Strip .myshopify.com if included
    STORE="${STORE%.myshopify.com}"

    print_header "Initializing Store: ${STORE}"

    # --- Test connection ---
    print_info "Testing API connection..."
    local shop_info
    shop_info=$(shopify_api GET "shop.json") || {
        print_err "Failed to connect to ${STORE}.myshopify.com"
        print_err "Check your store name and access token."
        exit 1
    }

    local shop_name
    shop_name=$(echo "$shop_info" | jq -r '.shop.name // "Unknown"')
    local shop_domain
    shop_domain=$(echo "$shop_info" | jq -r '.shop.domain // "Unknown"')
    print_ok "Connected to: ${shop_name} (${shop_domain})"
    rate_limit

    # --- List themes ---
    print_header "Discovering Themes"
    local themes_json
    themes_json=$(shopify_api GET "themes.json") || {
        print_err "Failed to list themes. Check that your token has read_themes scope."
        exit 1
    }
    rate_limit

    local theme_count
    theme_count=$(echo "$themes_json" | jq '.themes | length')
    print_info "Found ${theme_count} theme(s):"
    echo ""

    local live_theme_id=""
    local live_theme_name=""
    local dev_theme_id=""
    local dev_theme_name=""

    # Display all themes and identify live + dev candidates
    echo "$themes_json" | jq -r '.themes[] | "\(.id)|\(.name)|\(.role)"' | while IFS='|' read -r id name role; do
        if [[ "$role" == "main" ]]; then
            echo -e "  ${RED}[LIVE]${NC} ${BOLD}${name}${NC} (ID: ${id})"
        elif [[ "$role" == "unpublished" ]]; then
            echo -e "  ${GREEN}[DEV]${NC}  ${name} (ID: ${id})"
        elif [[ "$role" == "demo" ]]; then
            echo -e "  ${YELLOW}[DEMO]${NC} ${name} (ID: ${id})"
        else
            echo -e "         ${name} (ID: ${id}, role: ${role})"
        fi
    done

    # Extract live theme
    live_theme_id=$(echo "$themes_json" | jq -r '.themes[] | select(.role == "main") | .id')
    live_theme_name=$(echo "$themes_json" | jq -r '.themes[] | select(.role == "main") | .name')

    if [[ -z "$live_theme_id" ]]; then
        print_err "Could not identify the live theme. Something is wrong."
        exit 1
    fi

    print_ok "Live theme: ${live_theme_name} (ID: ${live_theme_id})"

    # --- Find or create dev theme ---
    print_header "Setting Up Dev Theme"

    # Look for an existing unpublished theme
    local unpublished_themes
    unpublished_themes=$(echo "$themes_json" | jq '[.themes[] | select(.role == "unpublished")]')
    local unpublished_count
    unpublished_count=$(echo "$unpublished_themes" | jq 'length')

    if [[ "$unpublished_count" -gt 0 ]]; then
        # Use the first unpublished theme as dev
        dev_theme_id=$(echo "$unpublished_themes" | jq -r '.[0].id')
        dev_theme_name=$(echo "$unpublished_themes" | jq -r '.[0].name')
        print_ok "Using existing dev theme: ${dev_theme_name} (ID: ${dev_theme_id})"

        if [[ "$unpublished_count" -gt 1 ]]; then
            print_warn "Found ${unpublished_count} unpublished themes. Using the first one."
            print_info "To use a different one, edit .shopify-dev/config.json after setup."
        fi
    else
        # Create a new dev theme by duplicating the live theme
        print_info "No unpublished themes found. Creating a dev copy of the live theme..."

        local create_payload
        create_payload=$(jq -n --arg name "${live_theme_name} [DEV]" --argjson src "$live_theme_id" \
            '{theme: {name: $name, role: "unpublished", source_theme_id: $src}}')

        # Note: source_theme_id copies all assets from the source theme
        # This may not be available on all API versions; fallback to manual copy
        local create_response
        create_response=$(shopify_api POST "themes.json" "$create_payload") || {
            # Fallback: create empty theme
            print_warn "Could not duplicate theme. Creating empty dev theme..."
            create_payload=$(jq -n --arg name "${live_theme_name} [DEV]" \
                '{theme: {name: $name, role: "unpublished"}}')
            create_response=$(shopify_api POST "themes.json" "$create_payload") || {
                print_err "Failed to create dev theme. Check write_themes scope."
                exit 1
            }
        }
        rate_limit

        dev_theme_id=$(echo "$create_response" | jq -r '.theme.id')
        dev_theme_name=$(echo "$create_response" | jq -r '.theme.name')
        print_ok "Created dev theme: ${dev_theme_name} (ID: ${dev_theme_id})"

        # Wait for theme processing
        print_info "Waiting for theme to finish processing..."
        local retries=0
        while [[ $retries -lt 30 ]]; do
            rate_limit
            local theme_status
            theme_status=$(shopify_api GET "themes/${dev_theme_id}.json")
            local previewable
            previewable=$(echo "$theme_status" | jq -r '.theme.previewable')
            if [[ "$previewable" == "true" ]]; then
                print_ok "Theme is ready."
                break
            fi
            retries=$((retries + 1))
            echo -n "."
        done
        if [[ $retries -ge 30 ]]; then
            print_warn "Theme may still be processing. Continuing anyway..."
        fi
    fi

    # --- Initialize Git repo ---
    print_header "Initializing Git Repository"

    local work_dir=".shopify-dev"
    mkdir -p "${work_dir}/theme"

    if [[ -d "${work_dir}/theme/.git" ]]; then
        print_warn "Git repo already exists. Skipping init."
    else
        (cd "${work_dir}/theme" && git init -q)
        print_ok "Git repo initialized at ${work_dir}/theme/"
    fi

    # Create .gitignore for the config (token security)
    cat > "${work_dir}/.gitignore" <<'GITIGNORE'
config.json
*.token
GITIGNORE
    print_ok "Created .gitignore (config.json excluded from version control)"

    # --- Download dev theme assets as initial snapshot ---
    print_header "Downloading Dev Theme Snapshot"
    print_info "Fetching asset list for dev theme..."

    local assets_json
    assets_json=$(shopify_api GET "themes/${dev_theme_id}/assets.json") || {
        print_err "Failed to list assets for dev theme."
        exit 1
    }
    rate_limit

    local asset_keys
    asset_keys=$(echo "$assets_json" | jq -r '.assets[].key')
    local asset_count
    asset_count=$(echo "$asset_keys" | wc -l | tr -d ' ')
    print_info "Found ${asset_count} assets to download..."

    local downloaded=0
    local failed=0

    while IFS= read -r key; do
        [[ -z "$key" ]] && continue

        # Create directory structure
        local dir
        dir=$(dirname "${work_dir}/theme/${key}")
        mkdir -p "$dir"

        # Download asset
        local asset_data
        asset_data=$(shopify_api GET "themes/${dev_theme_id}/assets.json?asset%5Bkey%5D=${key}") || {
            print_warn "Failed to download: ${key}"
            failed=$((failed + 1))
            continue
        }
        rate_limit

        # Assets can be text (value) or binary (attachment — base64)
        local value
        value=$(echo "$asset_data" | jq -r '.asset.value // empty')
        if [[ -n "$value" ]]; then
            echo "$value" > "${work_dir}/theme/${key}"
        else
            local attachment
            attachment=$(echo "$asset_data" | jq -r '.asset.attachment // empty')
            if [[ -n "$attachment" ]]; then
                echo "$attachment" | base64 -d > "${work_dir}/theme/${key}" 2>/dev/null || {
                    # macOS base64 uses -D
                    echo "$attachment" | base64 -D > "${work_dir}/theme/${key}" 2>/dev/null || {
                        print_warn "Failed to decode binary asset: ${key}"
                        failed=$((failed + 1))
                        continue
                    }
                }
            else
                print_warn "Empty asset: ${key}"
                failed=$((failed + 1))
                continue
            fi
        fi

        downloaded=$((downloaded + 1))

        # Progress indicator
        if (( downloaded % 10 == 0 )); then
            echo -ne "\r  Downloaded: ${downloaded}/${asset_count}"
        fi
    done <<< "$asset_keys"

    echo ""
    print_ok "Downloaded ${downloaded} assets (${failed} failed)"

    # --- Git commit initial snapshot ---
    (
        cd "${work_dir}/theme"
        git add -A
        git commit -q -m "Initial snapshot of dev theme: ${dev_theme_name}" --allow-empty
        git tag -a "v0-init" -m "Initial snapshot from init-store.sh"
    )
    print_ok "Committed and tagged as v0-init"

    # --- Save config ---
    print_header "Saving Configuration"

    local config_file="${work_dir}/config.json"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n \
        --arg store "$STORE" \
        --arg api_version "$API_VERSION" \
        --arg live_id "$live_theme_id" \
        --arg live_name "$live_theme_name" \
        --arg dev_id "$dev_theme_id" \
        --arg dev_name "$dev_theme_name" \
        --arg token "$TOKEN" \
        --arg created "$now" \
        '{
            store: $store,
            api_version: $api_version,
            live_theme_id: ($live_id | tonumber),
            live_theme_name: $live_name,
            dev_theme_id: ($dev_id | tonumber),
            dev_theme_name: $dev_name,
            access_token: $token,
            created_at: $created,
            base_url: ("https://" + $store + ".myshopify.com/admin/api/" + $api_version)
        }' > "$config_file"

    print_ok "Config saved to ${config_file}"

    # --- Summary ---
    print_header "Setup Complete! 🎉"

    echo -e "${BOLD}Store:${NC}      ${shop_name}"
    echo -e "${BOLD}Domain:${NC}     ${shop_domain}"
    echo -e "${BOLD}Live Theme:${NC} ${live_theme_name} (ID: ${live_theme_id}) ${RED}← DO NOT TOUCH${NC}"
    echo -e "${BOLD}Dev Theme:${NC}  ${dev_theme_name} (ID: ${dev_theme_id}) ${GREEN}← Safe to edit${NC}"
    echo ""
    echo -e "${BOLD}Preview URL:${NC}"
    echo -e "  ${CYAN}https://${STORE}.myshopify.com/?preview_theme_id=${dev_theme_id}${NC}"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Edit theme files in .shopify-dev/theme/"
    echo "  2. Push changes: ./scripts/safe-push.sh <file1> [file2...]"
    echo "  3. Preview at the URL above"
    echo "  4. When ready: ./scripts/promote.sh"
    echo ""
    echo -e "${YELLOW}⚠ Your access token is stored in .shopify-dev/config.json${NC}"
    echo -e "${YELLOW}  This file is gitignored. NEVER commit it to a public repo.${NC}"
}

main "$@"
