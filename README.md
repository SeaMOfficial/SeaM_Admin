# SeaM Admin

SeaM Admin is a native SeaM Core administration resource. It provides one Svelte interface for the in-city NUI and remote browser dashboard, with the same server-side permissions and permanent audit log on both surfaces.

No external permission system or framework role is read. Staff access is resolved only from full FiveM identifiers.

## Included

- Shared maritime Svelte interface for browser and in-city use, with parchment folios, brass accents and oxblood seals
- Readable period-inspired typography with traditional serif headings and clean system UI text
- Integrated icon-only **Compact menu** control in the bottom-right that docks the in-city interface on the right
- In-city menu on `/admin` or `F10`
- Remote dashboard with Discord OAuth
- Identifier-based roles for `license:`, `license2:`, `discord:`, `fivem:`, `steam:`, `xbl:` and `live:`
- Multiple identifiers on one staff profile
- Live players, SeaM characters, jobs, money accounts and metadata
- Goto, bring, spectate, freeze, revive, heal, feed, armour, needs, kill, clear-tasks, message, kick, warn and ban tools
- SeaM Core ban list and revocation
- Live SeaM Inventory inspection from either interface, with item removal, granting and protected full clears
- Native noclip, invisibility, god mode, super jump, fast run, infinite stamina, infinite ammo, player names, blips and coordinate display
- Entity laser with model, network ID, health and coordinate readout
- Vehicle spawning, repair, clean, flip, boost, fuel, engine, unlock, protection, upgrades and inspection tools
- Full `/report` player support centre with categories, ticket history, live chat, ownership checks and player-side closing
- Linked report queue in both admin surfaces with live claim, reply, close, goto and bring actions
- Announcements, time, weather and resource controls
- Persistent player notes, warning management and equal-or-higher staff protection
- Admin duty sessions, duty leaderboard, economy flow and action analytics
- Staff editor, audit history, webhook logging and activity metrics
- CSRF protection, rate limiting, secure browser sessions and permission checks on every request

## Requirements

- `SeaM_Core` 1.0.0 (included in this pack)
- `oxmysql`
- `SeaM_Inventory` 1.0.0 (included in this pack)
- A recent FiveM artifact with the Node.js 22 server runtime
- OneSync

SeaM Core is the only framework used. Item definitions, grants and live player inspection are handled directly by SeaM Inventory.

## New installation

1. Install SeaM Core and import its `install/schema.sql`.
2. Place `SeaM_Admin` in your resources directory.
3. Import `SeaM_Admin/install.sql` into the same database.
4. Put one full identifier in `Config.StaffIdentifiers` in `config.lua` so the first owner can sign in:

```lua
Config.StaffIdentifiers = {
    ['license:0123456789abcdef0123456789abcdef01234567'] = 'owner',
    -- The same person may have more than one entry:
    ['discord:123456789012345678'] = 'owner',
}
```

5. Start resources in this order:

```cfg
ensure oxmysql
ensure SeaM_Core
ensure SeaM_Inventory
ensure SeaM_Admin
```

6. Restart the server, join the city and open `/admin`. Use **Staff & roles** to create database-managed staff profiles.

Use the complete identifier, including its prefix. You can obtain identifiers from the player drawer in the admin menu or the FiveM server console. A staff profile may contain several identifiers; matching any one grants its assigned role. If several matches exist, the highest role wins.

Static entries in `Config.StaffIdentifiers` are intended for bootstrap and emergency owners. They do not appear in the staff editor and cannot be deleted from the browser.

## Upgrade from SeaM Admin 1.x

If SeaM Admin 1.x was installed, back up the database and import `migrate_v1_to_v2.sql`, followed by `migrate_v2_2_to_v2_3.sql` and `migrate_v2_3_to_v2_4.sql`, in that order. The migrations preserve existing data while adding identifier profiles, player notes, duty sessions and the full report-centre fields. Keep the new bootstrap owner in `Config.StaffIdentifiers` until you have verified access.

## Upgrade from SeaM Admin 2.2.x

Back up the database and import `migrate_v2_2_to_v2_3.sql`, then `migrate_v2_3_to_v2_4.sql`, once before starting version 2.4.0. The first adds private player notes and persistent staff duty. The second adds report category, subject and player-history indexing without deleting existing reports or conversations.

## Upgrade from SeaM Admin 2.3.x

Back up the database and import `migrate_v2_3_to_v2_4.sql` once before starting version 2.4.0. Existing reports are retained and receive the default category **General support** and subject **Support request**. Do not run the migration twice.

## Identifier permissions

The included hierarchy is configured in `Config.Roles`:

| Role | Default access |
| --- | --- |
| Support | Dashboard, players, reports, duty, movement, care tools, staff notes and logs |
| Moderator | Support plus kill, kick, ban, live inventory, items, vehicles and announcements |
| Administrator | Moderator plus analytics, jobs, money, characters, inventory clears, developer tools, bans and world controls |
| Owner | Every permission, resource controls and staff management |

In-city access checks every supported identifier exposed by FiveM. Browser access checks the authenticated Discord account as `discord:USER_ID`. The browser never supplies or chooses its role.

Staff hierarchy is enforced on the server. Unless the acting user is an owner, a staff member cannot moderate another staff member whose configured role has an equal or higher rank.

## In-city power controls

Open the dashboard and select **Go on duty** before starting a staff session. Duty history is stored in `seam_admin_duty_sessions` and appears on the Analytics page.

Use the circular compact icon in the bottom-right to switch the in-city interface into a smaller right-side dock. The preference is remembered on that game client; press the icon again to restore the full layout.

Noclip uses the normal movement keys:

| Control | Action |
| --- | --- |
| `W A S D` | Move with the gameplay camera |
| `Space` | Move upward |
| `Q` | Move downward |
| `Shift` | Fast movement |
| `Ctrl` | Precise movement |

When the entity laser is active, aim at a vehicle, ped or object. Press `E` to copy its model, network ID, health and coordinates. Press `Delete` to remove a non-player entity through a fresh server-side permission check.

Going off duty disables every active power and removes player overlays.

## Player report system

Players use `/report` to open the report centre. They can create a categorized report, read their report history, see whether a request is open, claimed or closed, exchange live replies with staff, and close their own request when it is resolved. `/report some details` opens the same centre with those details already placed in the description field.

Every report is owned server-side by the player's stable FiveM identifier. The client cannot choose an identifier, read another player's report, impersonate staff or bypass the open-report and cooldown limits. Report text is cleaned and length-limited before it reaches SQL.

The report appears immediately in **Reports** on both the in-city admin panel and the browser dashboard. Authorised staff can claim it, reply, close it, and—while on duty in-city—goto or bring the reporting player. Staff replies and state changes are pushed to the player's open report centre, and the browser queue refreshes through the existing live event stream.

The default categories and limits are in `config.lua`:

```lua
Config.ReportCategories = {
    { id = 'general', label = 'General support' },
    { id = 'player', label = 'Report a player' },
    { id = 'bug', label = 'Bug or technical issue' },
    { id = 'rules', label = 'Rules question' },
    { id = 'other', label = 'Other' },
}
Config.ReportMaxOpen = 3
Config.ReportHistoryLimit = 30
Config.ReportCreateCooldown = 10
Config.ReportReplyCooldown = 2
```

Category IDs should remain short lowercase values. Labels may be changed freely. Restart `SeaM_Admin` after changing report settings.

## Browser dashboard

For complete local, LAN, public-domain, Nginx, HTTPS, hosting-panel and troubleshooting instructions, read **[WEB_SETUP.md](WEB_SETUP.md)**.

Create an application in the [Discord Developer Portal](https://discord.com/developers/applications). Under OAuth2, register:

```text
https://admin.yourdomain.com/auth/callback
```

Add these convars to `server.cfg` and keep the client secret private:

```cfg
set seam_admin_web_enabled "true"
set seam_admin_web_host "127.0.0.1"
set seam_admin_web_port "30121"
set seam_admin_public_url "https://admin.yourdomain.com"
set seam_admin_discord_client_id "YOUR_DISCORD_CLIENT_ID"
set seam_admin_discord_client_secret "YOUR_DISCORD_CLIENT_SECRET"
```

Use `0.0.0.0` for `seam_admin_web_host` only when your container or network layout requires it. Put the numeric Discord user ID on the staff profile, or add its full `discord:` identifier to `Config.StaffIdentifiers`.

Expose the dashboard through HTTPS. Example Nginx location:

```nginx
location / {
    proxy_pass http://127.0.0.1:30121;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_buffering off;
    proxy_read_timeout 60s;
}
```

## Commands

| Command | Use |
| --- | --- |
| `/admin` | Open the in-city menu |
| `/report` | Open the player report centre |
| `/report [message]` | Open the report centre with a prefilled description |
| `/reportreply [id] [message]` | Quick-reply to one of your open reports |

## Exports

```lua
local canBan = exports['SeaM_Admin']:HasPermission(source, 'players.ban')
local role = exports['SeaM_Admin']:GetRole(source)
local identifiers = exports['SeaM_Admin']:GetIdentifiers(source)
local onDuty = exports['SeaM_Admin']:IsOnDuty(source)
```

## Configuration

- Edit `Config.Roles` to change permissions and inheritance.
- Edit `Config.VehicleCatalog` to populate the vehicle directory. Admins can also type any valid GTA vehicle model.
- Edit `Config.ProtectedResources` before enabling resource controls.
- Set `Config.MaxClearAreaRadius` to cap world-cleanup requests. The default is `100` metres.
- `Config.RequireDutyForInCityTools = true` requires duty before movement, powers, entity tools, the full inventory NUI and local vehicle actions. Remote-safe browser actions remain available.
- Set `seam_admin_webhook` in `server.cfg` to mirror admin actions to a Discord webhook.
- Browser sessions last 12 hours and are rejected as soon as the matching Discord identifier loses access.
- Goto, spectate, opening the full inventory NUI, powers, entity tools and local vehicle controls appear only in-city. The browser can still inspect and edit a live SeaM Inventory through the player drawer when its role has permission.
- Keep the resource folder names `SeaM_Inventory` and `SeaM_Admin`; the protected inspection export accepts only the admin resource.

## Svelte development

The compiled UI is included. To rebuild it:

```bash
cd SeaM_Admin/web
npm ci
npm run check
npm run build
```

FiveM loads `web/dist/index.html`; production servers do not need the source dependencies.
