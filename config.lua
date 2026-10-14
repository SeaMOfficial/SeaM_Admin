Config = {}

Config.Debug = false
Config.Command = 'admin'
Config.Keybind = 'F10'
Config.ServerName = 'SeaM Roleplay'
Config.MaxClearAreaRadius = 100
Config.RequireDutyForInCityTools = true

-- Player report centre. /report opens the interface; text after the command is
-- carried into the description as a draft. These limits are also enforced on
-- the server, so a modified NUI cannot bypass them.
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

-- The web dashboard reads its settings and secrets from server.cfg convars.
-- See README.md. Do not put Discord secrets in this file.

-- Staff access is resolved directly from FiveM identifiers.
-- Add at least one owner here, restart the resource, then manage other staff
-- from the Staff & roles page. Every identifier must include its type prefix.
Config.StaffIdentifiers = {
    -- ['license:0123456789abcdef0123456789abcdef01234567'] = 'owner',
    -- ['discord:123456789012345678'] = 'owner',
    -- ['fivem:1234567'] = 'admin',
    -- ['steam:110000112345678'] = 'moderator',
}

Config.SupportedIdentifierTypes = {
    license = true,
    license2 = true,
    discord = true,
    fivem = true,
    steam = true,
    xbl = true,
    live = true,
}
Config.ProtectedResources = {
    ['SeaM_Core'] = true,
    ['oxmysql'] = true,
    ['SeaM_Inventory'] = true,
    ['seam_admin'] = true,
    ['sessionmanager'] = true,
    ['mapmanager'] = true,
    ['spawnmanager'] = true,
}

Config.Teleports = {
    { label = 'Legion Square', coords = vector4(215.76, -810.12, 30.73, 157.0) },
    { label = 'Pillbox Hospital', coords = vector4(307.13, -595.31, 43.28, 70.0) },
    { label = 'Mission Row PD', coords = vector4(428.23, -984.28, 30.71, 3.0) },
    { label = 'LS Customs', coords = vector4(-337.16, -136.84, 39.01, 70.0) },
    { label = 'Sandy Shores', coords = vector4(1853.15, 3689.51, 34.27, 210.0) },
    { label = 'Paleto Bay', coords = vector4(-104.77, 6469.55, 31.63, 225.0) },
}

Config.Roles = {
    support = {
        label = 'Support',
        color = '#38bdf8',
        permissions = {
            'dashboard.view', 'players.view', 'reports.view', 'reports.manage',
            'players.goto', 'players.bring', 'players.freeze', 'players.spectate',
            'players.heal', 'players.revive', 'players.warn', 'players.needs',
            'players.message', 'players.notes', 'self.manage', 'staff.duty', 'logs.view'
        }
    },
    moderator = {
        label = 'Moderator',
        color = '#a78bfa',
        inherits = 'support',
        permissions = {
            'players.kick', 'players.ban', 'players.inventory', 'players.giveitem',
            'players.kill', 'players.armour', 'players.cleartasks', 'players.warn.remove',
            'players.notes.remove', 'vehicles.manage', 'server.announce', 'bans.view'
        }
    },
    admin = {
        label = 'Administrator',
        color = '#fb923c',
        inherits = 'moderator',
        permissions = {
            'players.setjob', 'players.money', 'characters.view', 'bans.view',
            'bans.manage', 'items.view', 'vehicles.view', 'server.view',
            'server.weather', 'server.time', 'server.cleararea', 'players.inventory.clear',
            'players.model', 'self.devtools', 'analytics.view'
        }
    },
    owner = {
        label = 'Owner',
        color = '#f43f5e',
        inherits = 'admin',
        permissions = { '*' }
    }
}

Config.BanDurations = {
    { label = '1 hour', seconds = 3600 },
    { label = '6 hours', seconds = 21600 },
    { label = '1 day', seconds = 86400 },
    { label = '3 days', seconds = 259200 },
    { label = '7 days', seconds = 604800 },
    { label = '30 days', seconds = 2592000 },
    { label = 'Permanent', seconds = 0 },
}

Config.AllowedWeather = {
    CLEAR = true, EXTRASUNNY = true, CLOUDS = true, OVERCAST = true, FOGGY = true, SMOG = true,
    RAIN = true, THUNDER = true, CLEARING = true, NEUTRAL = true,
    SNOW = true, BLIZZARD = true, SNOWLIGHT = true, XMAS = true, HALLOWEEN = true
}

-- SeaM Core intentionally does not own a vehicle catalogue. These entries
-- populate the admin browser; admins may also type any valid GTA model.
Config.VehicleCatalog = {
    { model = 'adder', name = 'Adder', brand = 'Truffade', category = 'super', price = 1000000 },
    { model = 'sultan', name = 'Sultan', brand = 'Karin', category = 'sports', price = 120000 },
    { model = 'buffalo', name = 'Buffalo', brand = 'Bravado', category = 'sports', price = 95000 },
    { model = 'comet2', name = 'Comet', brand = 'Pfister', category = 'sports', price = 180000 },
    { model = 'elegy', name = 'Elegy RH8', brand = 'Annis', category = 'sports', price = 165000 },
    { model = 'kuruma', name = 'Kuruma', brand = 'Karin', category = 'sports', price = 135000 },
    { model = 'baller', name = 'Baller', brand = 'Gallivanter', category = 'suv', price = 85000 },
    { model = 'granger', name = 'Granger', brand = 'Declasse', category = 'suv', price = 72000 },
    { model = 'tailgater', name = 'Tailgater', brand = 'Obey', category = 'sedan', price = 68000 },
    { model = 'premier', name = 'Premier', brand = 'Declasse', category = 'sedan', price = 42000 },
    { model = 'bison', name = 'Bison', brand = 'Bravado', category = 'utility', price = 55000 },
    { model = 'rumpo', name = 'Rumpo', brand = 'Bravado', category = 'van', price = 48000 },
    { model = 'bati', name = 'Bati 801', brand = 'Pegassi', category = 'motorcycle', price = 45000 },
    { model = 'police', name = 'Police Cruiser', brand = 'Vapid', category = 'emergency', price = 0 },
    { model = 'ambulance', name = 'Ambulance', brand = 'Brute', category = 'emergency', price = 0 },
}
