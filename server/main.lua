local Core = exports['SeaM_Core']:GetCoreObject()
local webhook = GetConvar('seam_admin_webhook', '')

SeaMAdmin = {
    Core = Core,
    Actions = {},
    StaffById = {},
    StaffByIdentifier = {},
    StaticStaffByIdentifier = {},
    Duty = {},
    StartedAt = os.time(),
}

local function debugPrint(...)
    if Config.Debug then print(('^5[SeaM Admin]^7 %s'):format(table.concat({ ... }, ' '))) end
end

function SeaMAdmin.NormalizeIdentifier(identifier)
    identifier = tostring(identifier or ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
    local kind, value = identifier:match('^([^:]+):(.+)$')
    if not kind or not Config.SupportedIdentifierTypes[kind] or value == '' then return nil end
    return kind .. ':' .. value
end

function SeaMAdmin.Identifiers(source)
    local identifiers = {}
    for index = 0, GetNumPlayerIdentifiers(source) - 1 do
        local identifier = SeaMAdmin.NormalizeIdentifier(GetPlayerIdentifier(source, index))
        if identifier then identifiers[#identifiers + 1] = identifier end
    end
    return identifiers
end

function SeaMAdmin.Identifier(source, kind)
    kind = tostring(kind or ''):lower()
    for _, identifier in ipairs(SeaMAdmin.Identifiers(source)) do
        if identifier:sub(1, #kind + 1) == kind .. ':' then return identifier end
    end
    return nil
end

function SeaMAdmin.DiscordId(source)
    local identifier = SeaMAdmin.Identifier(source, 'discord')
    return identifier and identifier:sub(9) or nil
end

function SeaMAdmin.Player(source)
    source = tonumber(source)
    if not source then return nil end
    return exports['SeaM_Core']:GetPlayer(source)
end

-- FiveM exports serialise tables between resources, so Player class methods and
-- metatables cannot be called safely from SeaM_Admin. Always ask SeaM Core for
-- its public snapshot and fall back to the serialised fields for older builds.
function SeaMAdmin.PlayerData(source)
    source = tonumber(source)
    if not source then return nil end

    local ok, data = pcall(function()
        return exports['SeaM_Core']:GetPlayerData(source)
    end)
    if ok and type(data) == 'table' then return data end

    local playerOk, player = pcall(function()
        return exports['SeaM_Core']:GetPlayer(source)
    end)
    if not playerOk or type(player) ~= 'table' then return nil end
    data = type(player.PlayerData) == 'table' and player.PlayerData or player
    return {
        source = source,
        citizenid = data.citizenid or data.citizenId,
        license = data.license,
        name = data.name,
        charinfo = data.charinfo or {},
        money = data.money or {},
        job = data.job or {},
        gang = data.gang or {},
        metadata = data.metadata or {},
        group = data.group or data.permission_group or 'user',
        playtime = data.playtime or 0,
    }
end

local function roleRank(name, visiting)
    local role = Config.Roles[name]
    if not role then return 0 end
    visiting = visiting or {}
    if visiting[name] then return 0 end
    visiting[name] = true
    return 1 + (role.inherits and roleRank(role.inherits, visiting) or 0)
end

function SeaMAdmin.RoleRank(name)
    return roleRank(name)
end

local function chooseRole(current, candidate)
    if not Config.Roles[candidate] then return current end
    if not current or roleRank(candidate) > roleRank(current) then return candidate end
    return current
end

for rawIdentifier, role in pairs(Config.StaffIdentifiers or {}) do
    local identifier = SeaMAdmin.NormalizeIdentifier(rawIdentifier)
    if not identifier then
        print(('^3[SeaM Admin] Ignoring invalid staff identifier in config.lua: %s^7'):format(tostring(rawIdentifier)))
    elseif not Config.Roles[role] then
        print(('^3[SeaM Admin] Ignoring unknown role "%s" for %s.^7'):format(tostring(role), identifier))
    else
        SeaMAdmin.StaticStaffByIdentifier[identifier] = role
    end
end

function SeaMAdmin.RefreshStaff()
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT s.id, s.name, s.role, s.created_by, s.created_at, s.updated_at, i.identifier
        FROM seam_admin_staff s
        LEFT JOIN seam_admin_staff_identifiers i ON i.staff_id = s.id
        ORDER BY s.name, i.identifier
    ]])
    if not ok then
        print('^1[SeaM Admin] Could not load identifier staff. Import install.sql before using the resource.^7')
        return false
    end

    SeaMAdmin.StaffById = {}
    SeaMAdmin.StaffByIdentifier = {}
    for _, row in ipairs(rows or {}) do
        local staff = SeaMAdmin.StaffById[row.id]
        if not staff then
            staff = {
                id = row.id,
                name = row.name,
                role = row.role,
                created_by = row.created_by,
                created_at = row.created_at,
                updated_at = row.updated_at,
                identifiers = {},
            }
            SeaMAdmin.StaffById[row.id] = staff
        end
        local identifier = SeaMAdmin.NormalizeIdentifier(row.identifier)
        if identifier then
            staff.identifiers[#staff.identifiers + 1] = identifier
            SeaMAdmin.StaffByIdentifier[identifier] = staff
        end
    end
    return true
end

function SeaMAdmin.ResolveIdentifiers(identifiers)
    local bestRole, matchedIdentifier, staff
    for _, raw in ipairs(identifiers or {}) do
        local identifier = SeaMAdmin.NormalizeIdentifier(raw)
        if identifier then
            local configured = SeaMAdmin.StaticStaffByIdentifier[identifier]
            local database = SeaMAdmin.StaffByIdentifier[identifier]
            local candidate = chooseRole(configured, database and database.role)
            local selected = chooseRole(bestRole, candidate)
            if selected ~= bestRole then
                bestRole = selected
                matchedIdentifier = identifier
                staff = database
            end
        end
    end
    return bestRole, matchedIdentifier, staff
end

function SeaMAdmin.RoleForSource(source)
    return SeaMAdmin.ResolveIdentifiers(SeaMAdmin.Identifiers(tonumber(source)))
end

function SeaMAdmin.RoleForDiscord(discordId)
    return SeaMAdmin.ResolveIdentifiers({ 'discord:' .. tostring(discordId or '') })
end

function SeaMAdmin.MakeActor(sourceType, source, webUser)
    local role, identifier, staff
    local name
    if sourceType == 'web' then
        role, identifier, staff = SeaMAdmin.RoleForDiscord(webUser and webUser.id)
        name = (staff and staff.name) or (webUser and webUser.username) or 'Web administrator'
    else
        role, identifier, staff = SeaMAdmin.RoleForSource(source)
        name = (staff and staff.name) or GetPlayerName(source) or 'Unknown administrator'
    end
    if not role then return nil end

    return {
        type = sourceType,
        source = sourceType == 'game' and tonumber(source) or nil,
        name = name,
        identifier = identifier or ('unknown:' .. tostring(source or 'web')),
        discordId = sourceType == 'web' and tostring(webUser.id) or SeaMAdmin.DiscordId(source),
        role = role,
        roleLabel = Config.Roles[role].label,
        roleColor = Config.Roles[role].color,
        permissions = SeaMAdminPermissions.ForRole(role),
        onDuty = sourceType == 'game' and SeaMAdmin.Duty[tonumber(source)] ~= nil or false,
    }
end

function SeaMAdmin.Has(actor, permission)
    return actor and SeaMAdminPermissions.Has(actor.role, permission)
end

function SeaMAdmin.CanTarget(actor, target)
    target = tonumber(target)
    if not actor or not target then return false end
    if actor.type == 'game' and actor.source == target then return true end
    if actor.role == 'owner' then return true end
    local targetRole = SeaMAdmin.RoleForSource(target)
    if not targetRole then return true end
    return SeaMAdmin.RoleRank(actor.role) > SeaMAdmin.RoleRank(targetRole)
end

function SeaMAdmin.SetDuty(actor, enabled)
    if not actor or actor.type ~= 'game' or not actor.source then return false end
    local source = tonumber(actor.source)
    local current = SeaMAdmin.Duty[source]
    enabled = enabled == true
    if enabled and not current then
        local sessionId = MySQL.insert.await([[
            INSERT INTO seam_admin_duty_sessions (staff_identifier, staff_name, role_name, player_source)
            VALUES (?, ?, ?, ?)
        ]], { actor.identifier, actor.name, actor.role, source })
        SeaMAdmin.Duty[source] = { id = sessionId, startedAt = os.time() }
    elseif not enabled and current then
        MySQL.update.await([[
            UPDATE seam_admin_duty_sessions
            SET ended_at = NOW(), duration_seconds = GREATEST(0, TIMESTAMPDIFF(SECOND, started_at, NOW()))
            WHERE id = ? AND ended_at IS NULL
        ]], { current.id })
        SeaMAdmin.Duty[source] = nil
    end
    TriggerClientEvent('seam_admin:client:dutyState', source, enabled)
    TriggerEvent('seam_admin:web:broadcast', { type = 'staff.duty', source = source, enabled = enabled })
    return true
end

function SeaMAdmin.Notify(source, message, kind, duration, title)
    if not source then return end
    local ok = pcall(function()
        exports['SeaM_Core']:Notify(source, message, kind or 'inform', duration, title or 'SeaM Admin')
    end)
    if not ok then TriggerClientEvent('SeaM_Core:notify', source, message, kind or 'inform', duration, title or 'SeaM Admin') end
end

function SeaMAdmin.SafeText(value, maxLength)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, maxLength or 500)
end

function SeaMAdmin.Log(actor, action, target, details)
    local targetName, targetIdentifier
    if type(target) == 'number' then
        targetName = GetPlayerName(target)
        targetIdentifier = SeaMAdmin.Identifier(target, 'license') or SeaMAdmin.Identifiers(target)[1]
    elseif type(target) == 'table' then
        targetName = target.name
        targetIdentifier = target.identifier
    end

    MySQL.insert('INSERT INTO seam_admin_logs (action, admin_name, admin_identifier, target_name, target_identifier, details, source_type) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        action, actor.name, actor.identifier, targetName, targetIdentifier,
        details and json.encode(details) or nil, actor.type
    })

    if webhook ~= '' then
        local description = ('**Administrator:** %s\n**Identifier:** %s\n**Action:** %s\n**Target:** %s\n**Source:** %s'):format(
            actor.name, actor.identifier, action, targetName or 'None', actor.type
        )
        PerformHttpRequest(webhook, function() end, 'POST', json.encode({
            username = 'SeaM Admin',
            embeds = {{ title = 'Administrative action', description = description, color = 5625510 }}
        }), { ['Content-Type'] = 'application/json' })
    end

    TriggerEvent('seam_admin:web:broadcast', { type = 'log.created', action = action })
end

function SeaMAdmin.RegisterAction(name, permission, handler)
    SeaMAdmin.Actions[name] = { permission = permission, handler = handler }
end

function SeaMAdmin.PlayerSummary(source)
    local data = SeaMAdmin.PlayerData(source)
    if not data then return nil end
    local job, charinfo = data.job or {}, data.charinfo or {}
    local ped = GetPlayerPed(source)
    local coords = ped and ped > 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
    local role = SeaMAdmin.RoleForSource(source)
    return {
        source = tonumber(source),
        name = GetPlayerName(source) or 'Unknown',
        characterName = data.name or ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')),
        citizenid = data.citizenid,
        license = data.license or SeaMAdmin.Identifier(source, 'license'),
        discordId = SeaMAdmin.DiscordId(source),
        identifiers = SeaMAdmin.Identifiers(source),
        job = job.name or 'unemployed',
        jobLabel = job.label or job.name or 'Unemployed',
        grade = job.gradeLabel or job.grade or 0,
        onDuty = job.onDuty == true,
        ping = GetPlayerPing(source),
        role = role,
        staffOnDuty = role and SeaMAdmin.Duty[tonumber(source)] ~= nil or false,
        coreGroup = data.group or 'user',
        coords = { x = coords.x, y = coords.y, z = coords.z },
    }
end

function SeaMAdmin.OnlinePlayers()
    local players = {}
    for _, source in ipairs(GetPlayers()) do
        local summary = SeaMAdmin.PlayerSummary(tonumber(source))
        if summary then players[#players + 1] = summary end
    end
    table.sort(players, function(a, b) return a.source < b.source end)
    return players
end

local function execute(actor, actionName, payload)
    local action = SeaMAdmin.Actions[actionName]
    if not actor then return { ok = false, error = 'None of your identifiers are authorised for SeaM Admin.' } end
    if not action then return { ok = false, error = 'Unknown action.' } end
    if action.permission and not SeaMAdmin.Has(actor, action.permission) then
        SeaMAdmin.Log(actor, 'permission.denied', nil, { requested = actionName })
        return { ok = false, error = 'Your role does not have permission for this action.' }
    end

    local ok, result = xpcall(function()
        return action.handler(actor, type(payload) == 'table' and payload or {})
    end, debug.traceback)
    if not ok then
        print(('^1[SeaM Admin] Action %s failed: %s^7'):format(actionName, result))
        return { ok = false, error = 'The action failed on the server. Check the server console.' }
    end
    if result == nil then result = { ok = true } end
    if result.ok == nil then result.ok = true end
    return result
end

RegisterNetEvent('seam_admin:server:request', function(requestId, action, payload)
    local source = source
    local result = execute(SeaMAdmin.MakeActor('game', source), SeaMAdmin.SafeText(action, 80), payload)
    TriggerClientEvent('seam_admin:client:response', source, requestId, result)
end)

AddEventHandler('seam_admin:server:webRequest', function(requestId, webUser, action, payload)
    local result = execute(SeaMAdmin.MakeActor('web', nil, webUser), SeaMAdmin.SafeText(action, 80), payload)
    TriggerEvent('seam_admin:web:response', requestId, result)
end)

RegisterNetEvent('seam_admin:server:open', function()
    local source = source
    local actor = SeaMAdmin.MakeActor('game', source)
    if not actor or not SeaMAdmin.Has(actor, 'dashboard.view') then
        return SeaMAdmin.Notify(source, 'None of your identifiers have access to this menu.', 'error')
    end
    TriggerClientEvent('seam_admin:client:open', source)
end)

AddEventHandler('playerDropped', function()
    local source = source
    local duty = SeaMAdmin.Duty[source]
    if duty then
        MySQL.update('UPDATE seam_admin_duty_sessions SET ended_at = NOW(), duration_seconds = GREATEST(0, TIMESTAMPDIFF(SECOND, started_at, NOW())) WHERE id = ? AND ended_at IS NULL', { duty.id })
        SeaMAdmin.Duty[source] = nil
    end
    TriggerEvent('seam_admin:web:broadcast', { type = 'players.changed' })
end)

AddEventHandler('SeaM_Core:player:loaded', function()
    TriggerEvent('seam_admin:web:broadcast', { type = 'players.changed' })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, duty in pairs(SeaMAdmin.Duty) do
        MySQL.update('UPDATE seam_admin_duty_sessions SET ended_at = NOW(), duration_seconds = GREATEST(0, TIMESTAMPDIFF(SECOND, started_at, NOW())) WHERE id = ? AND ended_at IS NULL', { duty.id })
    end
end)

MySQL.ready(function()
    SeaMAdmin.RefreshStaff()
    pcall(MySQL.update.await, 'UPDATE seam_admin_duty_sessions SET ended_at = NOW(), duration_seconds = GREATEST(0, TIMESTAMPDIFF(SECOND, started_at, NOW())) WHERE ended_at IS NULL')
end)

CreateThread(function()
    while true do
        Wait(60000)
        SeaMAdmin.RefreshStaff()
    end
end)

CreateThread(function()
    Wait(15000)
    while true do
        local players, staff = 0, 0
        for _, source in ipairs(GetPlayers()) do
            players = players + 1
            if SeaMAdmin.RoleForSource(tonumber(source)) then staff = staff + 1 end
        end
        pcall(MySQL.insert.await, 'INSERT INTO seam_admin_metrics (players, staff) VALUES (?, ?)', { players, staff })
        pcall(MySQL.query.await, 'DELETE FROM seam_admin_metrics WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)')
        Wait(300000)
    end
end)

exports('HasPermission', function(source, permission)
    local role = SeaMAdmin.RoleForSource(source)
    return role and SeaMAdminPermissions.Has(role, permission) or false
end)

exports('GetRole', function(source) return SeaMAdmin.RoleForSource(source) end)
exports('GetIdentifiers', function(source) return SeaMAdmin.Identifiers(source) end)
exports('IsOnDuty', function(source) return SeaMAdmin.Duty[tonumber(source)] ~= nil end)

debugPrint('SeaM Core bridge loaded')
