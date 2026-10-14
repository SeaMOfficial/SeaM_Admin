# SeaM Admin Browser Dashboard Setup

This guide explains how to access SeaM Admin from a normal web browser. It covers:

1. A local-only dashboard on the same computer as the FiveM server.
2. An optional private LAN dashboard for devices on the same network.
3. A public dashboard using a domain, Nginx and HTTPS.

The browser dashboard is not a separate static website. `SeaM_Admin` starts its own HTTP server inside the FiveM resource, serves the compiled Svelte interface, handles Discord login and sends every action back through the same server-side permission system used by the in-city menu.

## What the browser dashboard requires

- `oxmysql`, `SeaM_Core`, `SeaM_Inventory` and `SeaM_Admin` installed and running.
- The `SeaM_Admin/install.sql` tables imported into the SeaM database.
- A recent FiveM artifact with the Node.js 22 server runtime.
- A Discord application with an OAuth2 client ID, client secret and matching redirect URL.
- At least one authorised `discord:USER_ID` staff identifier.
- Outbound HTTPS access from the FiveM server to `discord.com`.
- An additional TCP port or an HTTPS reverse proxy if the dashboard will be accessed from another machine.

Keep the resource folder names exactly `SeaM_Core`, `SeaM_Inventory` and `SeaM_Admin`.

If upgrading from SeaM Admin 2.2.x, import `migrate_v2_2_to_v2_3.sql` before restarting the resource. This adds the tables used by player notes, duty sessions and analytics.

## How browser access is secured

Discord confirms the user's numeric Discord ID. SeaM Admin then resolves that account as a full `discord:USER_ID` identifier and loads its configured staff role. The browser cannot submit or choose its own role.

The dashboard also uses:

- Server-side permission checks on every action.
- A short-lived OAuth state value during Discord login.
- HTTP-only, same-site session cookies.
- Secure cookies automatically when `seam_admin_public_url` starts with `https://`.
- CSRF tokens and exact-origin checks for browser actions.
- A limit of 120 actions per session per minute.
- Twelve-hour rolling sessions stored in memory.
- The permanent SeaM Admin audit log.
- Server-enforced staff hierarchy checks for player actions.

Restarting `SeaM_Admin` clears active browser sessions, so users must sign in again. Removing someone's staff identifier prevents their following requests from being authorised.

The browser can inspect live SeaM Inventory contents, remove items, clear inventories, manage player needs and money, add private staff notes, review analytics and perform the other remote-safe actions allowed by the signed-in role. Movement, noclip, entity-laser, full inventory NUI and local vehicle controls remain in-city only.

## Step 1: Authorise the first Discord account

Browser access must match a Discord identifier. Enable Developer Mode in Discord, right-click your account and select **Copy User ID**. Add the numeric ID to `SeaM_Admin/config.lua`:

```lua
Config.StaffIdentifiers = {
    ['discord:123456789012345678'] = 'owner',
}
```

Keep the `discord:` prefix. Do not enter a Discord username, display name or mention.

You can assign several identifiers to the same person while bootstrapping:

```lua
Config.StaffIdentifiers = {
    ['license:0123456789abcdef0123456789abcdef01234567'] = 'owner',
    ['discord:123456789012345678'] = 'owner',
}
```

After the first owner signs in, database-managed profiles can be created from **Staff & roles**. Static entries in `config.lua` remain intended for bootstrap or emergency access.

## Step 2: Create the Discord OAuth application

1. Open the [Discord Developer Portal](https://discord.com/developers/applications).
2. Select **New Application**, give it a name such as `SeaM Admin`, and open it.
3. Copy the **Application ID**. This becomes `seam_admin_discord_client_id`.
4. Open **OAuth2** and obtain the client secret. This becomes `seam_admin_discord_client_secret`.
5. Under the OAuth2 redirect settings, add the callback for the setup you will use:

| Setup | Redirect URL |
| --- | --- |
| Same computer | `http://127.0.0.1:30121/auth/callback` |
| Private LAN | `http://192.168.1.50:30121/auth/callback` |
| Public HTTPS | `https://admin.example.com/auth/callback` |

Replace the example LAN IP or domain with the real address. The redirect must match the dashboard's public URL exactly, including:

- `http` versus `https`.
- Hostname or IP address.
- Port number when a non-standard port is used.
- The `/auth/callback` path.

Do not add a trailing slash after `callback`. SeaM Admin requests only Discord's `identify` scope. A bot account does not need to be created or invited to a Discord server.

Discord's authorization-code flow requires the redirect URI used during login and token exchange to match a URI registered on the application. See the [Discord OAuth2 documentation](https://discord.com/developers/docs/topics/oauth2) for the underlying flow.

Treat the client secret like a password. Keep it in `server.cfg`; never place it in `config.lua`, the Svelte source, a public repository or a screenshot.

## Method A: Local-only dashboard

Use this method when the FiveM server and the web browser are running on the same computer. It is the simplest development or home-hosted setup and does not expose the admin dashboard to the network.

### A1. Register the local callback

Add this exact redirect in the Discord Developer Portal:

```text
http://127.0.0.1:30121/auth/callback
```

### A2. Configure `server.cfg`

Add the following settings before `ensure SeaM_Admin`:

```cfg
set seam_admin_web_enabled "true"
set seam_admin_web_host "127.0.0.1"
set seam_admin_web_port "30121"
set seam_admin_public_url "http://127.0.0.1:30121"
set seam_admin_discord_client_id "YOUR_DISCORD_APPLICATION_ID"
set seam_admin_discord_client_secret "YOUR_DISCORD_CLIENT_SECRET"

ensure oxmysql
ensure SeaM_Core
ensure SeaM_Inventory
ensure SeaM_Admin
```

`127.0.0.1` binds the dashboard only to the local computer. Other computers cannot connect to it.

### A3. Restart and test

Restart the FiveM server, or restart `SeaM_Admin` after saving every convar. The server console should contain:

```text
[SeaM Admin] Web dashboard listening on 127.0.0.1:30121
```

Open this health check in the same computer's browser:

```text
http://127.0.0.1:30121/health
```

A working server returns JSON similar to:

```json
{"ok":true,"resource":"SeaM_Admin"}
```

Then open:

```text
http://127.0.0.1:30121
```

Select **Continue with Discord** and sign in with the Discord account configured as staff.

Always browse using the exact origin configured in `seam_admin_public_url`. For example, do not configure `127.0.0.1` and then browse through `localhost`; the dashboard intentionally rejects browser actions sent from a different origin.

## Method B: Private LAN dashboard

Use this only when trusted devices on the same private network need access. This method uses ordinary HTTP and must not be port-forwarded to the public internet.

Assume the FiveM server computer has the private address `192.168.1.50`.

### B1. Register the LAN callback

Add this redirect to the Discord application:

```text
http://192.168.1.50:30121/auth/callback
```

### B2. Configure `server.cfg`

```cfg
set seam_admin_web_enabled "true"
set seam_admin_web_host "0.0.0.0"
set seam_admin_web_port "30121"
set seam_admin_public_url "http://192.168.1.50:30121"
set seam_admin_discord_client_id "YOUR_DISCORD_APPLICATION_ID"
set seam_admin_discord_client_secret "YOUR_DISCORD_CLIENT_SECRET"
```

`0.0.0.0` allows the HTTP server to accept connections through the machine's network interfaces. It is a bind address only; never enter `http://0.0.0.0:30121` as the public URL or Discord redirect.

Give the server computer a DHCP reservation or static private IP so its address does not change.

### B3. Allow only the private network through the firewall

Windows PowerShell, opened as Administrator:

```powershell
New-NetFirewallRule -DisplayName "SeaM Admin LAN" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 30121 -RemoteAddress LocalSubnet
```

Ubuntu with a typical `192.168.1.0/24` private subnet:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 30121 proto tcp
```

Adjust the subnet to match your own network. Do not create a router port-forward for TCP `30121` when using the LAN method.

### B4. Open it from another device

From a device connected to the same network, visit:

```text
http://192.168.1.50:30121
```

If the `/health` endpoint works locally but not from another device, check the private IP, operating-system firewall, Wi-Fi client isolation and whether the FiveM process is running with the updated bind address.

## Method C: Public dashboard with HTTPS

Use this method for access over the internet. The recommended layout keeps the SeaM Admin HTTP server private on `127.0.0.1:30121` and exposes only Nginx on ports `80` and `443`.

### C1. Create the DNS record

Create an `A` record such as:

```text
admin.example.com -> YOUR_VPS_PUBLIC_IPV4
```

Add an `AAAA` record only if the VPS and firewall are correctly configured for IPv6. Wait for the record to resolve to the server.

### C2. Register the HTTPS callback

Add this exact redirect to the Discord application:

```text
https://admin.example.com/auth/callback
```

### C3. Configure `server.cfg`

```cfg
set seam_admin_web_enabled "true"
set seam_admin_web_host "127.0.0.1"
set seam_admin_web_port "30121"
set seam_admin_public_url "https://admin.example.com"
set seam_admin_discord_client_id "YOUR_DISCORD_APPLICATION_ID"
set seam_admin_discord_client_secret "YOUR_DISCORD_CLIENT_SECRET"
```

Use the external HTTPS address for `seam_admin_public_url`, not the internal Nginx upstream. This causes SeaM Admin to set secure session cookies and validate browser requests against the correct public origin.

Restart `SeaM_Admin`, then confirm the upstream works on the VPS:

```bash
curl http://127.0.0.1:30121/health
```

### C4. Install and configure Nginx

Install Nginx using the package instructions for your Linux distribution. Create a site configuration such as `/etc/nginx/sites-available/seam-admin`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name admin.example.com;

    location / {
        proxy_pass http://127.0.0.1:30121;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 75s;
        proxy_send_timeout 75s;
    }
}
```

The dashboard uses a server-sent event stream for live updates. Disabling proxy buffering lets those updates pass through immediately; Nginx documents this behavior in its [HTTP proxy module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html).

Enable the site on Debian or Ubuntu:

```bash
sudo ln -s /etc/nginx/sites-available/seam-admin /etc/nginx/sites-enabled/seam-admin
sudo nginx -t
sudo systemctl reload nginx
```

If a file with the same link already exists, do not create it again. Edit the existing site and run the final two commands.

### C5. Enable HTTPS

Install Certbot using the current instructions at [certbot.eff.org](https://certbot.eff.org/instructions), selecting your operating system and Nginx. Once Certbot is installed and DNS points to the VPS, the usual certificate command is:

```bash
sudo certbot --nginx -d admin.example.com
```

Allow HTTPS redirection when prompted. Then verify:

```text
https://admin.example.com/health
```

The dashboard must be opened at:

```text
https://admin.example.com
```

Do not publish or directly expose port `30121`. For a standard public setup, the firewall should expose Nginx ports `80` and `443`, while SeaM Admin remains bound to `127.0.0.1`.

### C6. Final public test

1. Open the dashboard in a private browser window.
2. Select **Continue with Discord**.
3. Confirm Discord returns to `https://admin.example.com/auth/callback`.
4. Confirm the dashboard loads the correct staff name and role.
5. Open **Players** and perform a harmless permitted action.
6. Confirm the action appears in **Audit logs**.
7. Leave the dashboard open briefly and confirm live counters continue updating.

## Pterodactyl and shared game-hosting panels

The dashboard needs its own reachable TCP endpoint. If FiveM runs inside a container or shared hosting panel:

1. Ask the host for an additional TCP allocation, or ask them to reverse-proxy a subdomain to the resource's web port.
2. Set `seam_admin_web_port` to the allocated internal port.
3. Use `0.0.0.0` only when the proxy or mapped port is outside the same container/network namespace and cannot reach `127.0.0.1`.
4. Set `seam_admin_public_url` to the address staff actually enter in their browser, including the external port if one is required.
5. Register that public URL plus `/auth/callback` in Discord.

Examples:

```cfg
# Hosting provider exposes the allocation directly over HTTP:
set seam_admin_web_host "0.0.0.0"
set seam_admin_web_port "30250"
set seam_admin_public_url "http://panel-node.example.com:30250"
```

```cfg
# Hosting provider reverse-proxies a secure subdomain:
set seam_admin_web_host "0.0.0.0"
set seam_admin_web_port "30250"
set seam_admin_public_url "https://admin.example.com"
```

Direct HTTP allocations are suitable only for private or temporary testing. Use the provider's HTTPS reverse proxy for real remote administration. Some shared FiveM hosts do not permit arbitrary HTTP listeners; in that case the hosting provider must supply the extra allocation or proxy.

## Complete convar reference

| Convar | Purpose | Recommended value |
| --- | --- | --- |
| `seam_admin_web_enabled` | Starts the browser HTTP server | `true` |
| `seam_admin_web_host` | Interface on which the internal server listens | `127.0.0.1` locally/behind same-host Nginx; otherwise `0.0.0.0` only when required |
| `seam_admin_web_port` | Internal HTTP listening port | `30121`, or an allocated unused TCP port |
| `seam_admin_public_url` | Exact origin entered by staff and used for OAuth, cookies and origin checks | `http://127.0.0.1:30121` locally or `https://admin.example.com` publicly |
| `seam_admin_discord_client_id` | Discord application ID | Numeric value copied from the Developer Portal |
| `seam_admin_discord_client_secret` | Discord OAuth client secret | Secret value stored only in `server.cfg` |
| `seam_admin_webhook` | Optional audit-log webhook | Discord webhook URL or empty/unset |

Every web convar is read when `SeaM_Admin` starts. Restart the resource after changing one.

## Exact URL rules

The following values must describe the same external dashboard:

```text
Browser address:
https://admin.example.com

server.cfg:
set seam_admin_public_url "https://admin.example.com"

Discord redirect:
https://admin.example.com/auth/callback
```

Common mismatches that break login or dashboard actions include:

- Opening `http://` while the public URL says `https://`.
- Opening an IP address while the public URL uses a domain.
- Opening `localhost` while the public URL uses `127.0.0.1`.
- Leaving a non-standard port out of one value.
- Adding the wrong callback path.
- Registering a callback for a different subdomain.

## Troubleshooting

### Nothing is listening on the web port

- Confirm `set seam_admin_web_enabled "true"` appears before `ensure SeaM_Admin`.
- Restart `SeaM_Admin`; changing the convar while it is running is not enough.
- Check the console for `Web dashboard listening on HOST:PORT` or a bind error.
- Confirm another program is not already using the chosen TCP port.
- Confirm the resource uses a recent FiveM artifact with its server-side JavaScript runtime.

### `/health` works locally but the page is unreachable remotely

- `127.0.0.1` is local-only. Use Nginx on the same host, or bind to `0.0.0.0` when a container/LAN allocation requires it.
- Check the host firewall, provider firewall, container port mapping and hosting-panel allocation.
- For a public Nginx setup, expose `80/443`, not `30121`.
- Confirm DNS resolves to the correct public server.

### “The web dashboard is not configured”

At least one of these is empty:

- `seam_admin_public_url`
- `seam_admin_discord_client_id`
- `seam_admin_discord_client_secret`

Correct it in `server.cfg` and restart `SeaM_Admin`.

### Discord says the redirect URI is invalid

Compare the Discord redirect with your configured public URL:

```text
PUBLIC_URL/auth/callback
```

The scheme, host and port must match character-for-character. Save the redirect in the correct Discord application.

### “Discord login failed” or HTTP 502 after the callback

- Confirm the application ID and secret belong to the same Discord application.
- Generate a new secret if the old one was reset.
- Confirm the server can make outbound HTTPS requests to Discord.
- Check the FiveM console for the detailed OAuth error.
- Confirm the configured public URL and registered redirect match exactly.

### “This Discord account is not authorised”

- Add the full `discord:USER_ID` identifier to `Config.StaffIdentifiers`, or add that ID to a database-managed staff profile.
- Confirm the copied value is a numeric user ID, not a username.
- Confirm the configured role exists in `Config.Roles`.
- Restart the resource after changing `config.lua`.

### “Invalid request token” when pressing dashboard buttons

The page origin does not match `seam_admin_public_url`, or the session is stale.

- Open the exact public URL configured in `server.cfg`.
- Do not switch between domain, IP, `localhost` and `127.0.0.1`.
- Confirm the proxy and public URL use HTTPS together.
- Sign out, clear the site's cookies if necessary, and sign in again.
- Restarting the resource invalidates old sessions by design.

### Nginx returns 502 Bad Gateway

- Run `curl http://127.0.0.1:30121/health` on the VPS.
- Confirm Nginx's `proxy_pass` port matches `seam_admin_web_port`.
- Confirm `SeaM_Admin` is running without a web server bind error.
- If Nginx and FiveM are in different containers, use the reachable container/service address rather than the Nginx container's own `127.0.0.1`.

### Live updates arrive late or stop

- Keep `proxy_http_version 1.1` in the Nginx location.
- Keep `proxy_buffering off` and `proxy_cache off`.
- Ensure the proxy read timeout is longer than the dashboard's 25-second keepalive interval.
- Disable caching or response buffering for the admin subdomain in any additional proxy/CDN layer.

### The page loads but an action is unavailable

- Confirm the staff role contains the required permission in `Config.Roles`.
- Some actions are intentionally in-city only, including opening the full inventory NUI, goto, spectate, powers, entity tools and local vehicle controls. Browser staff with permission can still inspect and edit live inventory from the player drawer.
- Browser and in-city requests both use server-side permission checks; hiding or changing a button never bypasses them.

## Security checklist before public use

- Use HTTPS and a trusted certificate.
- Keep the internal SeaM Admin port bound to `127.0.0.1` when Nginx is on the same server.
- Do not publish the Discord client secret.
- Use full `discord:USER_ID` identifiers and grant the lowest suitable staff role.
- Keep at least one emergency owner identifier secure in `config.lua`.
- Review `Config.Roles` and `Config.ProtectedResources` before giving remote access.
- Restrict SSH, hosting-panel and database access separately.
- Keep FiveM artifacts, SeaM Core, SeaM Inventory and SeaM Admin updated together.
- Review **Audit logs** and configure `seam_admin_webhook` if off-server log mirroring is required.
- Remove staff profiles immediately when access should end.

## Quick verification checklist

- [ ] `SeaM_Admin/install.sql` has been imported.
- [ ] A valid `discord:USER_ID` has a staff role.
- [ ] The Discord application ID and secret are configured.
- [ ] The exact `/auth/callback` URL is registered in Discord.
- [ ] All web convars appear before `ensure SeaM_Admin`.
- [ ] The console reports the expected listening host and port.
- [ ] `/health` returns `ok: true`.
- [ ] The dashboard is opened through the exact configured public URL.
- [ ] Discord returns to the dashboard after login.
- [ ] The expected staff role is displayed.
- [ ] A safe test action appears in the audit log.
- [ ] Public deployments use HTTPS and do not expose the internal upstream port.
