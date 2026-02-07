#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# theme-guard.sh — Safety check: is this theme live?
#
# Usage:
#   ./theme-guard.sh <theme-id>              # Checks if theme is live (exits 1 if yes)
#   ./theme-guard.sh <theme-id> --promote    # Allows live theme (for promote.sh)
#   ./theme-guard.sh --validate <theme-id>   # Just check if theme exists
#
# Exit codes:
#   0 = Safe to proceed (theme is NOT live, or --promote flag used)
#   1 = BLOCKED (theme is live and no --promote flag)
#   2 = Theme not found or API error
#
# Used by other scripts to prevent accidental writes to the live theme.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- Load config ---
load_config() {
    local config_file=".shopify-dev/config.json"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}✗ No config found. Run init-store.sh first.${NC}" >&2
        exit 2
    fi

    STORE=$(jq -r '.store' "$config_file")
    TOKEN=$(jq -r '.access_token' "$config_file")
    API_VERSION=$(jq -r '.api_version' "$config_file")
}

# --- API helper ---
shopify_api() {
    local method="$1"
    local endpoint="$2"
    local url="https://${STORE}.myshopify.com/admin/api/${API_VERSION}/${endpoint}"

    local response
    response=$(curl -s -w "\n%{http_code}" -X "$method" \
        -H "X-Shopify-Access-Token: ${TOKEN}" \
        -H "Content-Type: application/json" \
        "$url")

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 400 ]]; then
        echo "$body"
        return 1
    fi

    echo "$body"
}

# --- Usage ---
usage() {
    echo "Usage: $0 <theme-id> [--promote]"
    echo "       $0 --validate <theme-id>"
    echo ""
    echo "Checks if a theme is the live (published) theme."
    echo "Returns exit code 0 if safe to modify, 1 if live, 2 on error."
    exit 2
}

# --- Main ---
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    local theme_id=""
    local allow_live=false
    local validate_only=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --promote)
                allow_live=true
                shift
                ;;
            --validate)
                validate_only=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                theme_id="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$theme_id" ]]; then
        echo -e "${RED}✗ No theme ID provided.${NC}" >&2
        usage
    fi

    # Validate theme ID is numeric
    if ! [[ "$theme_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ Invalid theme ID: ${theme_id} (must be numeric)${NC}" >&2
        exit 2
    fi

    load_config

    # --- Fetch theme info ---
    local theme_json
    theme_json=$(shopify_api GET "themes/${theme_id}.json") || {
        echo -e "${RED}✗ Theme ${theme_id} not found or API error.${NC}" >&2
        exit 2
    }

    local theme_name
    theme_name=$(echo "$theme_json" | jq -r '.theme.name // "Unknown"')
    local theme_role
    theme_role=$(echo "$theme_json" | jq -r '.theme.role // "unknown"')

    # --- Validate-only mode ---
    if [[ "$validate_only" == true ]]; then
        echo -e "${GREEN}✓${NC} Theme exists: ${theme_name} (ID: ${theme_id}, role: ${theme_role})"
        exit 0
    fi

    # --- Check if live ---
    if [[ "$theme_role" == "main" ]]; then
        if [[ "$allow_live" == true ]]; then
            echo -e "${YELLOW}⚠ Theme '${theme_name}' (${theme_id}) is the LIVE theme.${NC}"
            echo -e "${YELLOW}  Proceeding because --promote flag was used.${NC}"
            exit 0
        else
            echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}" >&2
            echo -e "${RED}║  🛑 BLOCKED: Theme '${theme_name}' is the LIVE theme!   ${NC}" >&2
            echo -e "${RED}║                                                          ║${NC}" >&2
            echo -e "${RED}║  Theme ID: ${theme_id}                                   ${NC}" >&2
            echo -e "${RED}║  Role: main (= published/live)                           ║${NC}" >&2
            echo -e "${RED}║                                                          ║${NC}" >&2
            echo -e "${RED}║  DO NOT modify the live theme directly.                  ║${NC}" >&2
            echo -e "${RED}║  Use safe-push.sh to push to the dev theme instead.      ║${NC}" >&2
            echo -e "${RED}║  Use promote.sh when ready to go live.                   ║${NC}" >&2
            echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}" >&2
            exit 1
        fi
    fi

    # Theme is not live — safe to modify
    echo -e "${GREEN}✓${NC} Theme '${theme_name}' (${theme_id}) is safe to modify (role: ${theme_role})"
    exit 0
}

main "$@"
