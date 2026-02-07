# Shopify Admin API — Common Patterns Reference

All operations use the REST Admin API. No Shopify CLI required.

## Authentication

Every request needs:
```
X-Shopify-Access-Token: {your_access_token}
Content-Type: application/json
```

## Base URL

```
https://{store}.myshopify.com/admin/api/2024-01/
```

Replace `{store}` with your store name (e.g., `odd-pieces-puzzles`).

---

## Theme Operations

### List All Themes
```bash
curl -s \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes.json"
```

Response:
```json
{
  "themes": [
    {
      "id": 123456789,
      "name": "Dawn",
      "role": "main",           // ← LIVE theme
      "previewable": true,
      "processing": false
    },
    {
      "id": 987654321,
      "name": "Dawn [DEV]",
      "role": "unpublished",    // ← Safe to edit
      "previewable": true,
      "processing": false
    }
  ]
}
```

**Theme roles:**
- `"main"` — The live/published theme. Customers see this. **DO NOT MODIFY DIRECTLY.**
- `"unpublished"` — Not published. Safe for development.
- `"demo"` — Trial theme from the theme store.

### Get Single Theme
```bash
curl -s \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes/${THEME_ID}.json"
```

### Create a Theme
```bash
curl -s -X POST \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"theme": {"name": "My Dev Theme", "role": "unpublished"}}' \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes.json"
```

The theme starts empty. To create a copy of an existing theme, you can optionally
include `"source_theme_id": 123456` in the payload (copies all assets).

---

## Asset Operations

### List All Assets in a Theme
```bash
curl -s \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes/${THEME_ID}/assets.json"
```

Response:
```json
{
  "assets": [
    {"key": "layout/theme.liquid", "content_type": "text/x-liquid", ...},
    {"key": "templates/index.json", "content_type": "application/json", ...},
    {"key": "assets/base.css", "content_type": "text/css", ...},
    {"key": "assets/logo.png", "content_type": "image/png", ...}
  ]
}
```

### Get a Single Asset (Text)
```bash
curl -s \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes/${THEME_ID}/assets.json?asset%5Bkey%5D=layout/theme.liquid"
```

Response for text files:
```json
{
  "asset": {
    "key": "layout/theme.liquid",
    "value": "<!DOCTYPE html>\n<html>...",   // ← Text content
    "content_type": "text/x-liquid"
  }
}
```

Response for binary files (images, fonts):
```json
{
  "asset": {
    "key": "assets/logo.png",
    "attachment": "iVBORw0KGgo...",           // ← Base64-encoded
    "content_type": "image/png"
  }
}
```

### Upload/Update an Asset (Text)
```bash
curl -s -X PUT \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "asset": {
      "key": "sections/header.liquid",
      "value": "<div class=\"header\">{{ section.settings.title }}</div>"
    }
  }' \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes/${THEME_ID}/assets.json"
```

### Upload/Update an Asset (Binary)
```bash
# Base64-encode the file first
B64=$(base64 < logo.png | tr -d '\n')

curl -s -X PUT \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"asset\": {
      \"key\": \"assets/logo.png\",
      \"attachment\": \"${B64}\"
    }
  }" \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes/${THEME_ID}/assets.json"
```

### Delete an Asset
```bash
curl -s -X DELETE \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  "https://${STORE}.myshopify.com/admin/api/2024-01/themes/${THEME_ID}/assets.json?asset%5Bkey%5D=assets/old-file.css"
```

---

## Preview URLs

To preview an unpublished theme:
```
https://{store}.myshopify.com/?preview_theme_id={theme_id}
```

Example:
```
https://odd-pieces-puzzles.myshopify.com/?preview_theme_id=152170692781
```

This URL works for anyone with the link. Share it for review before promoting.

---

## Rate Limits

Shopify REST Admin API uses a **leaky bucket** algorithm:
- **Bucket size:** 40 requests
- **Leak rate:** 2 requests/second
- **Practical limit:** ~2 requests per second sustained

### Headers to monitor:
```
X-Shopify-Shop-Api-Call-Limit: 32/40    ← 32 of 40 used
Retry-After: 2.0                         ← Wait this many seconds (on 429)
```

### Best practices:
- Add `sleep 0.55` between requests (all scripts do this)
- For bulk operations, watch the `X-Shopify-Shop-Api-Call-Limit` header
- If you get `429 Too Many Requests`, wait for the `Retry-After` period
- Large themes (200+ files) take 2-3 minutes to fully download/upload

---

## Common Asset Key Patterns

```
layout/
  theme.liquid              ← Main layout wrapper
  password.liquid           ← Password page layout

templates/
  index.json                ← Homepage template
  product.json              ← Product page template
  collection.json           ← Collection page template
  cart.json                 ← Cart page template
  page.json                 ← Generic page template
  blog.json                 ← Blog page template
  article.json              ← Article page template
  404.json                  ← 404 page template

sections/
  header.liquid             ← Header section
  footer.liquid             ← Footer section
  announcement-bar.liquid   ← Announcement bar
  featured-collection.liquid

snippets/
  icon-cart.liquid           ← Reusable snippets
  price.liquid

assets/
  base.css                   ← Main stylesheet
  theme.js                   ← Main JavaScript
  logo.png                   ← Images

config/
  settings_schema.json       ← Theme settings schema
  settings_data.json         ← Current theme settings values

locales/
  en.default.json            ← English translations
  fr.json                    ← French translations
```

---

## Error Handling

### Common errors:

| HTTP Code | Meaning | Action |
|-----------|---------|--------|
| 401 | Unauthorized | Check your access token |
| 403 | Forbidden | Token missing required scope |
| 404 | Not found | Theme or asset doesn't exist |
| 422 | Validation error | Check the response body for details |
| 429 | Rate limited | Wait and retry (check Retry-After header) |

### Response format for errors:
```json
{
  "errors": {
    "asset": ["Expected a valid value for key"]
  }
}
```
