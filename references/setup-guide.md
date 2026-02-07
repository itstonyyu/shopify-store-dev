# Setup Guide — For Store Owners

This guide walks you through creating a Custom App in your Shopify store so the
development tools can connect to it. No coding knowledge required.

**Time needed:** About 5 minutes.

---

## Step 1: Enable Custom App Development

1. Log in to your Shopify admin: `https://your-store.myshopify.com/admin`
2. Click **Settings** (bottom-left gear icon)
3. Click **Apps and sales channels**
4. Click **Develop apps** (top-right)
5. If prompted, click **Allow custom app development**
   - You may need to confirm this — click "Allow" again

> **Note:** Only the store owner or a staff member with "Apps" permission can do this.

## Step 2: Create the App

1. On the "App development" page, click **Create an app**
2. Give it a name: `Theme Dev Tool` (or whatever you prefer)
3. Click **Create app**

## Step 3: Set Permissions

1. Click **Configure Admin API scopes**
2. Scroll down and find these two scopes. Check both:
   - ✅ **`read_themes`** — Allows reading theme files
   - ✅ **`write_themes`** — Allows modifying theme files
3. **Do NOT enable other scopes** — keep it minimal for security
4. Click **Save**

## Step 4: Install the App

1. Click the **API credentials** tab
2. Click **Install app**
3. Confirm by clicking **Install**

## Step 5: Copy Your Access Token

After installing:
1. You'll see the **Admin API access token**
2. Click **Reveal token once**

> ⚠️ **IMPORTANT:** This token is shown ONLY ONCE. Copy it now and save it somewhere safe.
> If you lose it, you'll need to uninstall and reinstall the app to get a new one.

The token looks like: `shpat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

## Step 6: Find Your Store Name

Your store name is the part before `.myshopify.com` in your admin URL.

Example: If your admin URL is `https://my-cool-store.myshopify.com/admin`,
your store name is: `my-cool-store`

## Step 7: Run the Setup Script

Open a terminal and run:

```bash
./scripts/init-store.sh my-cool-store shpat_your_token_here
```

Replace:
- `my-cool-store` with your actual store name
- `shpat_your_token_here` with the token you copied in Step 5

The script will:
- Connect to your store
- Find your themes
- Set up a safe development environment
- Give you a preview URL

---

## Troubleshooting

### "Failed to connect" error
- Double-check your store name (no `.myshopify.com`, just the name)
- Make sure you copied the full access token (starts with `shpat_`)
- Check that the app is installed (Step 4)

### "Check that your token has read_themes scope" error
- Go back to your app settings (Settings → Apps → Develop apps → your app)
- Click "Configure Admin API scopes"
- Make sure both `read_themes` and `write_themes` are checked
- Click Save, then reinstall the app

### "write_themes" error when pushing
- Your token may only have read access
- Reconfigure the API scopes to include `write_themes`
- Reinstall the app to get a new token with the updated scopes

### Need a new token?
1. Go to Settings → Apps → Develop apps → your app
2. Click **Uninstall app**
3. Reconfigure scopes if needed
4. Click **Install app** again
5. Copy the new token

---

## Security Notes

- Your access token is stored locally in `.shopify-dev/config.json`
- This file is automatically excluded from Git (gitignored)
- Never share your token with anyone
- Never paste it in public channels, emails, or code repositories
- If you think your token was compromised, uninstall the app immediately
  (Settings → Apps → Develop apps → your app → Uninstall)

## What Permissions Does This Give?

The `read_themes` + `write_themes` scopes allow:
- ✅ Reading theme files (Liquid templates, CSS, JS, images)
- ✅ Modifying theme files
- ✅ Creating new themes
- ✅ Listing themes

They do NOT allow:
- ❌ Accessing customer data
- ❌ Viewing or modifying orders
- ❌ Changing store settings
- ❌ Managing products
- ❌ Accessing payment information
- ❌ Anything outside of themes

This is the minimum permission set needed for theme development.
