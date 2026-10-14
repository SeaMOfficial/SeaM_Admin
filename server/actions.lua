local A = SeaMAdmin

local function fail(message) return { ok = false, error = message } end
local function success(data) data = data or {}; data.ok = true; return data end

local function inventoryError(reason)
    local messages = {
        invalid_item = 'That SeaM Inventory item does not exist.',
        invalid_count = 'Enter a valid item amount.',
        no_space = 'The player has no inventory space.',
        too_heavy = 'The item would exceed the player inventory weight.',
        not_loaded = 'That player does not have a loaded SeaM Inventory.',
        not_enough = 'That inventory slot no longer contains the requested amount.',
        in_use = 'Another staff member is already viewing that inventory.',
        no_access = 'SeaM Inventory rejected the admin request.',
    }
    return messages[reason] or 'SeaM Inventory could not complete the request.'
end

local function targetPlayer(payload, actor, enforceHierarchy)
    local target = tonumber(payload.target)
    if not target or not GetPlayerName(target) then return nil, fail('That player is no longer online.') end
    if enforceHierarchy and actor and not A.CanTarget(actor, target) then
        return nil, fail('You cannot act on a staff member with an equal or higher role.')
    end
    local data = A.PlayerData(target)
    if not data then return nil, fail('Their SeaM Core character is not loaded.') end
    return data, nil, target
end

local function playerLicense(data, target)
    return data.license or A.Identifier(target, 'license')
end

local function requireGame(actor)
    if actor.type ~= 'game' or not actor.source then return false, fail('This action is only available inside the city.') end
    return true
end

local function requireDuty(actor)
    if Config.RequireDutyForInCityTools == false or actor.onDuty then return true end
    return false, fail('Go on admin duty before using in-city staff tools.')
end

local function decode(value)
    if type(value) == 'table' then return value end
    local ok, decoded = pcall(json.decode, value or '{}')
    return ok and type(decoded) == 'table' and decoded or {}
end

local function accountExists(name)
    for _, account in ipairs(exports['SeaM_Core']:GetAccounts() or {}) do
        if account.name == name then return true end
    end
    return false
end

A.RegisterAction('bootstrap', 'dashboard.view', function(actor)
    local players, teleports, accounts = A.OnlinePlayers(), {}, {}
    for index, point in ipairs(Config.Teleports) do teleports[index] = { label = point.label } end
    for _, account in ipairs(exports['SeaM_Core']:GetAccounts() or {}) do
        if not account.hidden then accounts[#accounts + 1] = { name = account.name, label = account.label or account.name } end
    end

    local staffOnline, staffOnDuty = 0, 0
    for _, player in ipairs(players) do
        if player.role then staffOnline = staffOnline + 1 end
        if player.staffOnDuty then staffOnDuty = staffOnDuty + 1 end
    end
    local reportCount = MySQL.scalar.await("SELECT COUNT(*) FROM seam_admin_reports WHERE status <> 'closed'") or 0
    local banCount = MySQL.scalar.await('SELECT COUNT(*) FROM seam_bans WHERE expires IS NULL OR expires > UNIX_TIMESTAMP()') or 0
    local history = MySQL.query.await([[
        SELECT players, staff, UNIX_TIMESTAMP(created_at) AS timestamp
        FROM seam_admin_metrics WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        ORDER BY created_at ASC LIMIT 288
    ]]) or {}

    return success({
        server = {
            name = (A.Core.Config and A.Core.Config.Server and A.Core.Config.Server.Name) or Config.ServerName,
            online = #players,
            maxPlayers = tonumber(GetConvar('sv_maxclients', '48')) or 48,
            staffOnline = staffOnline,
            staffOnDuty = staffOnDuty,
            reports = reportCount,
            activeBans = banCount,
            uptime = os.time() - A.StartedAt,
        },
        admin = {
            name = actor.name,
            identifier = actor.identifier,
            role = actor.role,
            roleLabel = actor.roleLabel,
            roleColor = actor.roleColor,
            permissions = actor.permissions,
            sourceType = actor.type,
            onDuty = actor.onDuty,
        },
        players = players,
        history = history,
        teleports = teleports,
        accounts = accounts,
        roles = SeaMAdminPermissions.PublicRoles(),
        banDurations = Config.BanDurations,
    })
end)

A.RegisterAction('players.list', 'players.view', function()
    return success({ players = A.OnlinePlayers() })
end)

A.RegisterAction('characters.list', 'characters.view', function(_, payload)
    local search = '%' .. A.SafeText(payload.search, 80) .. '%'
    local rows = MySQL.query.await([[
        SELECT citizenid, license, name, money, charinfo, job, metadata, last_seen
        FROM seam_players
        WHERE citizenid LIKE ? OR name LIKE ? OR charinfo LIKE ? OR license LIKE ?
        ORDER BY last_seen DESC LIMIT 250
    ]], { search, search, search, search }) or {}
    local characters = {}
    for _, row in ipairs(rows) do
        local charinfo, job, money, metadata = decode(row.charinfo), decode(row.job), decode(row.money), decode(row.metadata)
        local characterName = row.name or ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or ''))
        characters[#characters + 1] = {
            citizenid = row.citizenid,
            license = row.license,
            accountName = row.license,
            characterName = characterName:gsub('^%s+', ''):gsub('%s+$', ''),
            phone = charinfo.phone or metadata.phone,
            job = job.label or job.name or 'Unemployed',
            grade = job.gradeLabel or job.grade,
            cash = money.cash or 0,
            bank = money.bank or 0,
            accounts = money,
            isDead = metadata.isDead == true,
            lastUpdated = row.last_seen,
        }
    end
    return success({ characters = characters })
end)

A.RegisterAction('player.details', 'players.view', function(actor, payload)
    local data, err, target = targetPlayer(payload, actor, true)
    if not data then return err end
    local metadata = data.metadata or {}
    local license = data.license or A.Identifier(target, 'license')
    local warnings = MySQL.query.await('SELECT id, reason, admin_name, created_at FROM seam_admin_warnings WHERE citizenid = ? OR license = ? ORDER BY id DESC LIMIT 25', {
        data.citizenid, license
    }) or {}
    local notes = MySQL.query.await('SELECT id, note, admin_name, created_at FROM seam_admin_player_notes WHERE citizenid = ? OR license = ? ORDER BY id DESC LIMIT 50', {
        data.citizenid, license
    }) or {}
    local inventory
    if A.Has(actor, 'players.inventory') then
        inventory = exports['SeaM_Inventory']:GetInventory(target)
    end
    return success({
        player = A.PlayerSummary(target),
        accounts = data.money or {},
        metadata = {
            hunger = metadata.hunger,
            thirst = metadata.thirst,
            stress = metadata.stress,
            isdead = metadata.isDead,
            inlaststand = metadata.inLastStand,
        },
        gang = data.gang,
        charinfo = data.charinfo,
        warnings = warnings,
        notes = notes,
        inventory = inventory,
    })
end)

A.RegisterAction('player.goto', 'players.goto', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local coords = GetEntityCoords(GetPlayerPed(target))
    TriggerClientEvent('seam_admin:client:teleport', actor.source, { x = coords.x, y = coords.y, z = coords.z + 1.0 })
    A.Log(actor, 'player.goto', target)
    return success()
end)

A.RegisterAction('player.bring', 'players.bring', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local ped = GetPlayerPed(actor.source)
    if ped <= 0 then return fail('Your character is not available.') end
    local coords = GetEntityCoords(ped)
    TriggerClientEvent('seam_admin:client:teleport', target, { x = coords.x, y = coords.y, z = coords.z })
    A.Log(actor, 'player.bring', target)
    return success()
end)

A.RegisterAction('player.spectate', 'players.spectate', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local coords = GetEntityCoords(GetPlayerPed(target))
    TriggerClientEvent('SeaM_Core:admin:spectate', actor.source, target, { x = coords.x, y = coords.y, z = coords.z })
    A.Log(actor, 'player.spectate', target)
    return success()
end)

A.RegisterAction('player.freeze', 'players.freeze', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    TriggerClientEvent('seam_admin:client:setFrozen', target, payload.enabled == true)
    A.Log(actor, payload.enabled == true and 'player.freeze' or 'player.unfreeze', target)
    return success()
end)

A.RegisterAction('player.revive', 'players.revive', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    exports['SeaM_Core']:SetMetadata(target, 'isDead', false)
    exports['SeaM_Core']:SetMetadata(target, 'inLastStand', false)
    TriggerClientEvent('SeaM_Core:admin:revive', target)
    A.Notify(target, 'You were revived by staff.', 'success')
    A.Log(actor, 'player.revive', target)
    return success()
end)

A.RegisterAction('player.heal', 'players.heal', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    -- Health is applied client-side by seam_admin:client:heal below; there is no
    -- server-side SetEntityHealth in FiveM.
    exports['SeaM_Core']:SetMetadata(target, 'health', 200)
    exports['SeaM_Core']:SetMetadata(target, 'armour', 100)
    TriggerClientEvent('SeaM_Core:admin:armour', target, 100)
    TriggerClientEvent('seam_admin:client:heal', target)
    A.Log(actor, 'player.heal', target)
    return success()
end)

A.RegisterAction('player.feed', 'players.heal', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    exports['SeaM_Core']:SetMetadata(target, 'hunger', 100)
    exports['SeaM_Core']:SetMetadata(target, 'thirst', 100)
    A.Notify(target, 'Your hunger and thirst were restored by staff.', 'success')
    A.Log(actor, 'player.feed', target)
    return success()
end)

A.RegisterAction('player.warn', 'players.warn', function(actor, payload)
    local player, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local reason = A.SafeText(payload.reason, 500)
    if #reason < 3 then return fail('Enter a warning reason.') end
    MySQL.insert.await('INSERT INTO seam_admin_warnings (citizenid, license, player_name, reason, admin_name) VALUES (?, ?, ?, ?, ?)', {
        player.citizenid, playerLicense(player, target), player.name or GetPlayerName(target), reason, actor.name
    })
    A.Notify(target, ('You were warned by %s: %s'):format(actor.name, reason), 'error', 12000, 'Warning')
    A.Log(actor, 'player.warn', target, { reason = reason })
    return success()
end)

A.RegisterAction('player.kick', 'players.kick', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local reason = A.SafeText(payload.reason, 500)
    if #reason < 3 then return fail('Enter a kick reason.') end
    A.Log(actor, 'player.kick', target, { reason = reason })
    DropPlayer(target, ('Kicked by %s: %s'):format(actor.name, reason))
    return success()
end)

A.RegisterAction('player.ban', 'players.ban', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local reason = A.SafeText(payload.reason, 255)
    local duration = math.min(315360000, math.max(0, math.floor(tonumber(payload.duration) or 0)))
    if #reason < 3 then return fail('Enter a ban reason.') end
    A.Log(actor, 'player.ban', target, { reason = reason, duration = duration })
    exports['SeaM_Core']:Ban(target, reason, duration, actor.name)
    return success()
end)

A.RegisterAction('player.giveItem', 'players.giveitem', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local item = A.SafeText(payload.item, 80):lower()
    local amount = math.min(1000, math.max(1, math.floor(tonumber(payload.amount) or 1)))
    local items = exports['SeaM_Inventory']:GetItems() or {}
    if not items[item] then return fail('That SeaM Inventory item does not exist.') end
    local ok, response = exports['SeaM_Inventory']:AddItem(target, item, amount)
    if not ok then return fail(inventoryError(response)) end
    A.Log(actor, 'player.giveItem', target, { item = item, amount = amount })
    return success()
end)

A.RegisterAction('player.openInventory', 'players.inventory', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    TriggerClientEvent('seam_admin:client:close', actor.source)
    local ok, reason = exports['SeaM_Inventory']:OpenPlayerInventory(actor.source, target)
    if not ok then
        local message = inventoryError(reason)
        A.Notify(actor.source, message, 'error')
        return fail(message)
    end
    A.Log(actor, 'player.openInventory', target)
    return success()
end)

A.RegisterAction('player.setJob', 'players.setjob', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local job = A.SafeText(payload.job, 60):lower()
    local grade = math.max(0, math.floor(tonumber(payload.grade) or 0))
    local jobs = exports['SeaM_Core']:GetJobs() or {}
    if not jobs[job] or not jobs[job].grades[grade] then return fail('That SeaM Core job or grade does not exist.') end
    local ok, reason = exports['SeaM_Core']:SetJob(target, job, grade)
    if not ok then return fail(reason or 'SeaM Core rejected the job change.') end
    A.Log(actor, 'player.setJob', target, { job = job, grade = grade })
    return success()
end)

A.RegisterAction('player.money', 'players.money', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local operation = payload.operation == 'remove' and 'remove' or 'add'
    local account = A.SafeText(payload.account, 24):lower()
    local amount = math.min(10000000, math.max(1, math.floor(tonumber(payload.amount) or 0)))
    if not accountExists(account) then return fail('That SeaM Core money account does not exist.') end
    local ok, reason
    if operation == 'remove' then ok, reason = exports['SeaM_Core']:RemoveMoney(target, account, amount, 'SeaM Admin')
    else ok, reason = exports['SeaM_Core']:AddMoney(target, account, amount, 'SeaM Admin') end
    if not ok then return fail(reason or 'SeaM Core rejected the money operation.') end
    A.Log(actor, 'player.money.' .. operation, target, { account = account, amount = amount })
    return success()
end)

A.RegisterAction('player.kill', 'players.kill', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    TriggerClientEvent('seam_admin:client:kill', target)
    A.Log(actor, 'player.kill', target)
    return success()
end)

A.RegisterAction('player.armour', 'players.armour', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local amount = math.min(100, math.max(0, math.floor(tonumber(payload.amount) or 100)))
    exports['SeaM_Core']:SetMetadata(target, 'armour', amount)
    TriggerClientEvent('seam_admin:client:setArmour', target, amount)
    A.Log(actor, 'player.armour', target, { amount = amount })
    return success()
end)

A.RegisterAction('player.needs', 'players.needs', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local hunger = math.min(100, math.max(0, math.floor(tonumber(payload.hunger) or 100)))
    local thirst = math.min(100, math.max(0, math.floor(tonumber(payload.thirst) or 100)))
    local stress = math.min(100, math.max(0, math.floor(tonumber(payload.stress) or 0)))
    exports['SeaM_Core']:SetMetadata(target, 'hunger', hunger)
    exports['SeaM_Core']:SetMetadata(target, 'thirst', thirst)
    exports['SeaM_Core']:SetMetadata(target, 'stress', stress)
    A.Notify(target, 'Your needs were adjusted by staff.', 'inform')
    A.Log(actor, 'player.needs', target, { hunger = hunger, thirst = thirst, stress = stress })
    return success()
end)

A.RegisterAction('player.message', 'players.message', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local message = A.SafeText(payload.message, 500)
    if #message < 1 then return fail('Enter a message.') end
    A.Notify(target, message, 'inform', 12000, ('Staff · %s'):format(actor.name))
    A.Log(actor, 'player.message', target, { message = message })
    return success()
end)

A.RegisterAction('player.clearTasks', 'players.cleartasks', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    TriggerClientEvent('seam_admin:client:clearTasks', target)
    A.Log(actor, 'player.clearTasks', target)
    return success()
end)

A.RegisterAction('player.setModel', 'players.model', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local model = A.SafeText(payload.model, 80):lower()
    if not model:match('^[%w_]+$') then return fail('Enter a valid GTA pedestrian model.') end
    TriggerClientEvent('seam_admin:client:setModel', target, model)
    A.Log(actor, 'player.setModel', target, { model = model })
    return success()
end)

A.RegisterAction('player.note', 'players.notes', function(actor, payload)
    local player, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local note = A.SafeText(payload.note, 1000)
    if #note < 3 then return fail('Enter a useful staff note.') end
    MySQL.insert.await('INSERT INTO seam_admin_player_notes (citizenid, license, player_name, note, admin_name, admin_identifier) VALUES (?, ?, ?, ?, ?, ?)', {
        player.citizenid, playerLicense(player, target), player.name or GetPlayerName(target), note, actor.name, actor.identifier
    })
    A.Log(actor, 'player.note', target, { note = note })
    return success()
end)

A.RegisterAction('player.deleteNote', 'players.notes.remove', function(actor, payload)
    local player, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local id = math.floor(tonumber(payload.id) or 0)
    local changed = MySQL.update.await('DELETE FROM seam_admin_player_notes WHERE id = ? AND (citizenid = ? OR license = ?)', {
        id, player.citizenid, playerLicense(player, target)
    })
    if changed < 1 then return fail('That staff note no longer exists.') end
    A.Log(actor, 'player.deleteNote', target, { noteId = id })
    return success()
end)

A.RegisterAction('player.removeWarning', 'players.warn.remove', function(actor, payload)
    local player, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local id = math.floor(tonumber(payload.id) or 0)
    local changed = MySQL.update.await('DELETE FROM seam_admin_warnings WHERE id = ? AND (citizenid = ? OR license = ?)', {
        id, player.citizenid, playerLicense(player, target)
    })
    if changed < 1 then return fail('That warning no longer exists.') end
    A.Log(actor, 'player.removeWarning', target, { warningId = id })
    return success()
end)

A.RegisterAction('player.removeItem', 'players.inventory', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    local item = A.SafeText(payload.item, 80):lower()
    local amount = math.min(1000, math.max(1, math.floor(tonumber(payload.amount) or 1)))
    local slot = math.floor(tonumber(payload.slot) or 0)
    local ok, reason = exports['SeaM_Inventory']:RemoveItem(target, item, amount, nil, slot > 0 and slot or nil)
    if not ok then return fail(inventoryError(reason)) end
    A.Log(actor, 'player.removeItem', target, { item = item, amount = amount, slot = slot })
    return success()
end)

A.RegisterAction('player.clearInventory', 'players.inventory.clear', function(actor, payload)
    local _, targetErr, target = targetPlayer(payload, actor, true); if targetErr then return targetErr end
    if not exports['SeaM_Inventory']:ClearInventory(target) then return fail('SeaM Inventory could not clear that inventory.') end
    A.Log(actor, 'player.clearInventory', target)
    return success()
end)

A.RegisterAction('staff.duty', 'staff.duty', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    local enabled = payload.enabled == true
    A.SetDuty(actor, enabled)
    A.Log(actor, enabled and 'staff.duty.start' or 'staff.duty.end', actor.source)
    return success({ onDuty = enabled })
end)

A.RegisterAction('self.action', 'self.manage', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local allowedActions = {
        noclip = true, invisible = true, god = true, names = true, blips = true,
        radar = true, stamina = true, ragdoll = true, heal = true, revive = true,
        marker = true, back = true, superjump = true, fastrun = true,
        infiniteammo = true, coords = true, devlaser = true
    }
    local action = A.SafeText(payload.action, 40)
    if not allowedActions[action] then return fail('Unknown self action.') end
    if action == 'devlaser' and not A.Has(actor, 'self.devtools') then
        return fail('Your role does not have developer-tool access.')
    end
    if action == 'revive' then
        exports['SeaM_Core']:SetMetadata(actor.source, 'isDead', false)
        exports['SeaM_Core']:SetMetadata(actor.source, 'inLastStand', false)
        TriggerClientEvent('SeaM_Core:admin:revive', actor.source)
    elseif action == 'heal' then
        exports['SeaM_Core']:SetMetadata(actor.source, 'health', 200)
        exports['SeaM_Core']:SetMetadata(actor.source, 'armour', 100)
        TriggerClientEvent('SeaM_Core:admin:armour', actor.source, 100)
        TriggerClientEvent('seam_admin:client:heal', actor.source)
    else
        TriggerClientEvent('seam_admin:client:selfAction', actor.source, action, payload.enabled)
    end
    A.Log(actor, 'self.' .. action, actor.source, { enabled = payload.enabled })
    return success()
end)

A.RegisterAction('self.teleportCoords', 'self.manage', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
    local w = tonumber(payload.w)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z or math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then
        return fail('Enter valid world coordinates.')
    end
    TriggerClientEvent('seam_admin:client:teleport', actor.source, { x = x, y = y, z = z, w = w })
    A.Log(actor, 'self.teleportCoords', actor.source, { x = x, y = y, z = z, w = w })
    return success()
end)

A.RegisterAction('self.teleportPreset', 'self.manage', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local point = Config.Teleports[math.floor(tonumber(payload.index) or 0)]
    if not point then return fail('Unknown teleport location.') end
    TriggerClientEvent('seam_admin:client:teleport', actor.source, {
        x = point.coords.x, y = point.coords.y, z = point.coords.z, w = point.coords.w
    })
    A.Log(actor, 'self.teleport', actor.source, { location = point.label })
    return success()
end)

A.RegisterAction('items.list', 'items.view', function()
    local items = {}
    for name, item in pairs(exports['SeaM_Inventory']:GetItems() or {}) do
        items[#items + 1] = {
            name = name,
            label = item.label or name,
            weight = item.weight or 0,
            type = 'item',
            unique = item.stack == false,
        }
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    return success({ items = items })
end)

A.RegisterAction('vehicles.list', 'vehicles.view', function()
    local vehicles = {}
    for _, vehicle in ipairs(Config.VehicleCatalog) do vehicles[#vehicles + 1] = vehicle end
    table.sort(vehicles, function(a, b) return ((a.brand or '') .. a.name) < ((b.brand or '') .. b.name) end)
    return success({ vehicles = vehicles })
end)

A.RegisterAction('vehicle.action', 'vehicles.manage', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local valid = {
        spawn = true, repair = true, delete = true, max = true, fuel = true,
        clean = true, flip = true, boost = true, engine = true, unlock = true,
        god = true, inspect = true
    }
    local action = A.SafeText(payload.action, 30)
    if not valid[action] then return fail('Unknown vehicle action.') end
    if action == 'spawn' then
        local model = A.SafeText(payload.model, 80):lower()
        if not model:match('^[%w_]+$') then return fail('Enter a valid GTA vehicle model.') end
        TriggerClientEvent('seam_admin:client:vehicleAction', actor.source, action, model)
        A.Log(actor, 'vehicle.spawn', actor.source, { model = model })
    else
        TriggerClientEvent('seam_admin:client:vehicleAction', actor.source, action)
        A.Log(actor, 'vehicle.' .. action, actor.source)
    end
    return success()
end)

A.RegisterAction('server.clearArea', 'server.cleararea', function(actor, payload)
    local allowed, err = requireGame(actor); if not allowed then return err end
    allowed, err = requireDuty(actor); if not allowed then return err end
    local entityType = A.SafeText(payload.entityType, 20):lower()
    if entityType ~= 'vehicles' and entityType ~= 'peds' and entityType ~= 'objects' and entityType ~= 'all' then
        return fail('Choose vehicles, peds, objects or all entities.')
    end
    local radius = math.min(Config.MaxClearAreaRadius or 100, math.max(5, math.floor(tonumber(payload.radius) or 25)))
    TriggerClientEvent('seam_admin:client:clearArea', actor.source, entityType, radius)
    A.Log(actor, 'server.clearArea', actor.source, { entityType = entityType, radius = radius })
    return success()
end)

RegisterNetEvent('seam_admin:server:deleteEntity', function(networkId)
    local source = source
    local actor = A.MakeActor('game', source)
    if not actor or not A.Has(actor, 'self.devtools') or (Config.RequireDutyForInCityTools ~= false and not actor.onDuty) then return end
    networkId = tonumber(networkId)
    if not networkId or networkId < 1 then return end
    local entity = NetworkGetEntityFromNetworkId(networkId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    local entityType = GetEntityType(entity)
    if entityType < 1 or entityType > 3 or (entityType == 1 and IsPedAPlayer(entity)) then return end
    DeleteEntity(entity)
    A.Log(actor, 'developer.deleteEntity', nil, { networkId = networkId, entityType = entityType })
end)

RegisterNetEvent('seam_admin:server:clearEntities', function(networkIds)
    local source = source
    local actor = A.MakeActor('game', source)
    if not actor or not A.Has(actor, 'server.cleararea') or type(networkIds) ~= 'table'
        or (Config.RequireDutyForInCityTools ~= false and not actor.onDuty) then return end
    local actorPed = GetPlayerPed(source)
    if not actorPed or actorPed == 0 then return end
    local origin = GetEntityCoords(actorPed)
    local deleted = 0
    for index = 1, math.min(#networkIds, 200) do
        local networkId = tonumber(networkIds[index])
        local entity = networkId and NetworkGetEntityFromNetworkId(networkId) or 0
        if entity and entity ~= 0 and DoesEntityExist(entity)
            and #(GetEntityCoords(entity) - origin) <= (Config.MaxClearAreaRadius or 100) + 2.0
            and not (GetEntityType(entity) == 1 and IsPedAPlayer(entity)) then
            DeleteEntity(entity)
            deleted = deleted + 1
        end
    end
    A.Log(actor, 'server.clearEntities', nil, { deleted = deleted })
end)

A.RegisterAction('server.announce', 'server.announce', function(actor, payload)
    local message = A.SafeText(payload.message, 500)
    if #message < 3 then return fail('Enter an announcement.') end
    TriggerClientEvent('chat:addMessage', -1, { color = { 85, 214, 166 }, multiline = true, args = { Config.ServerName, message } })
    TriggerClientEvent('SeaM_Core:notify', -1, message, 'warning', 10000, Config.ServerName)
    A.Log(actor, 'server.announce', nil, { message = message })
    return success()
end)

A.RegisterAction('server.resources', 'server.view', function()
    local resources = {}
    for index = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(index)
        if name then
            local protected = Config.ProtectedResources[name] == true
                or name:lower() == GetCurrentResourceName():lower()
                or name:lower() == 'seam_core'
            resources[#resources + 1] = { name = name, state = GetResourceState(name), protected = protected }
        end
    end
    table.sort(resources, function(a, b) return a.name < b.name end)
    return success({ resources = resources })
end)

A.RegisterAction('server.resourceAction', 'server.resources', function(actor, payload)
    local name = A.SafeText(payload.resource, 100)
    local action = A.SafeText(payload.action, 20)
    if Config.ProtectedResources[name] or name:lower() == GetCurrentResourceName():lower() or name:lower() == 'seam_core' then
        return fail('That resource is protected in config.lua.')
    end
    if GetResourceState(name) == 'unknown' then return fail('Unknown resource.') end
    if action == 'start' then StartResource(name)
    elseif action == 'stop' then StopResource(name)
    elseif action == 'restart' then StopResource(name); Wait(250); StartResource(name)
    else return fail('Unknown resource action.') end
    A.Log(actor, 'resource.' .. action, nil, { resource = name })
    return success({ state = GetResourceState(name) })
end)

A.RegisterAction('server.world', 'server.weather', function(actor, payload)
    local weather = A.SafeText(payload.weather, 20):upper()
    if not Config.AllowedWeather[weather] then return fail('Unsupported weather type.') end
    TriggerClientEvent('seam_admin:client:setWeather', -1, weather)
    A.Log(actor, 'server.weather', nil, { weather = weather })
    return success()
end)

A.RegisterAction('server.time', 'server.time', function(actor, payload)
    local hour = math.min(23, math.max(0, math.floor(tonumber(payload.hour) or 12)))
    local minute = math.min(59, math.max(0, math.floor(tonumber(payload.minute) or 0)))
    TriggerClientEvent('seam_admin:client:setTime', -1, hour, minute)
    A.Log(actor, 'server.time', nil, { hour = hour, minute = minute })
    return success()
end)

A.RegisterAction('analytics.snapshot', 'analytics.view', function()
    local ok, economy = pcall(function() return exports['SeaM_Core']:GetEconomySnapshot(24) end)
    if not ok or type(economy) ~= 'table' then economy = {} end

    local totals = MySQL.single.await([[
        SELECT
            (SELECT COUNT(*) FROM seam_players) AS characters,
            (SELECT COUNT(*) FROM seam_admin_warnings) AS warnings,
            (SELECT COUNT(*) FROM seam_admin_reports WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)) AS reports_today,
            (SELECT COUNT(*) FROM seam_admin_logs WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)) AS actions_today,
            (SELECT COALESCE(SUM(CASE WHEN ended_at IS NULL THEN TIMESTAMPDIFF(SECOND, started_at, NOW()) ELSE duration_seconds END), 0)
                FROM seam_admin_duty_sessions WHERE started_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)) AS duty_seconds
    ]]) or {}

    local actions = MySQL.query.await([[
        SELECT action, COUNT(*) AS uses
        FROM seam_admin_logs
        WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        GROUP BY action ORDER BY uses DESC LIMIT 12
    ]]) or {}

    local duty = MySQL.query.await([[
        SELECT staff_name, role_name,
            COALESCE(SUM(CASE WHEN ended_at IS NULL THEN TIMESTAMPDIFF(SECOND, started_at, NOW()) ELSE duration_seconds END), 0) AS seconds,
            COUNT(*) AS sessions
        FROM seam_admin_duty_sessions
        WHERE started_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
        GROUP BY staff_identifier, staff_name, role_name
        ORDER BY seconds DESC LIMIT 20
    ]]) or {}

    local inventoryStacks, inventoryWeight = 0, 0
    for _, playerId in ipairs(GetPlayers()) do
        local inventory = exports['SeaM_Inventory']:GetInventory(tonumber(playerId))
        if inventory then
            inventoryStacks = inventoryStacks + #(inventory.items or {})
            inventoryWeight = inventoryWeight + (tonumber(inventory.weight) or 0)
        end
    end

    return success({
        totals = {
            characters = tonumber(totals.characters) or 0,
            warnings = tonumber(totals.warnings) or 0,
            reportsToday = tonumber(totals.reports_today) or 0,
            actionsToday = tonumber(totals.actions_today) or 0,
            dutySeconds = tonumber(totals.duty_seconds) or 0,
            inventoryStacks = inventoryStacks,
            inventoryWeight = inventoryWeight,
        },
        economy = economy,
        actions = actions,
        duty = duty,
    })
end)

A.RegisterAction('bans.list', 'bans.view', function(_, payload)
    local search = '%' .. A.SafeText(payload.search, 80) .. '%'
    local bans = MySQL.query.await([[
        SELECT b.id,
            COALESCE(p.name, b.citizenid, b.license, 'Unknown') AS player_name,
            b.license, b.discord AS discord_id, b.reason, b.banned_by AS admin_name,
            CASE WHEN b.expires IS NULL THEN NULL ELSE FROM_UNIXTIME(b.expires) END AS expires_at,
            (b.expires IS NULL OR b.expires > UNIX_TIMESTAMP()) AS active,
            b.created_at
        FROM seam_bans b
        LEFT JOIN seam_players p ON p.citizenid = b.citizenid
        WHERE COALESCE(p.name, '') LIKE ? OR COALESCE(b.citizenid, '') LIKE ?
            OR COALESCE(b.license, '') LIKE ? OR COALESCE(b.discord, '') LIKE ?
            OR b.reason LIKE ? OR CAST(b.id AS CHAR) LIKE ?
        ORDER BY b.id DESC LIMIT 250
    ]], { search, search, search, search, search, search }) or {}
    return success({ bans = bans })
end)

A.RegisterAction('bans.revoke', 'bans.manage', function(actor, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    if id < 1 then return fail('Invalid ban ID.') end
    local changed = MySQL.update.await('DELETE FROM seam_bans WHERE id = ?', { id })
    if changed < 1 then return fail('That SeaM Core ban does not exist.') end
    A.Log(actor, 'ban.revoke', { name = 'Ban #' .. id, identifier = tostring(id) })
    return success()
end)

A.RegisterAction('logs.list', 'logs.view', function(_, payload)
    local search = '%' .. A.SafeText(payload.search, 80) .. '%'
    local logs = MySQL.query.await([[
        SELECT id, action, admin_name, target_name, details, source_type, created_at
        FROM seam_admin_logs WHERE action LIKE ? OR admin_name LIKE ? OR COALESCE(target_name, '') LIKE ?
        ORDER BY id DESC LIMIT 300
    ]], { search, search, search }) or {}
    for _, log in ipairs(logs) do
        if log.details then
            local ok, decoded = pcall(json.decode, log.details)
            log.details = ok and decoded or log.details
        end
    end
    return success({ logs = logs })
end)

local function publicStaff()
    local output = {}
    for _, staff in pairs(A.StaffById) do
        local row = {
            id = staff.id,
            name = staff.name,
            role = staff.role,
            created_by = staff.created_by,
            created_at = staff.created_at,
            updated_at = staff.updated_at,
            identifiers = staff.identifiers,
            identifierText = table.concat(staff.identifiers, ' '),
        }
        for _, identifier in ipairs(staff.identifiers) do
            local kind, value = identifier:match('^([^:]+):(.+)$')
            if kind == 'discord' then row.discord_id = value
            elseif kind then row[kind] = identifier end
        end
        output[#output + 1] = row
    end
    table.sort(output, function(a, b) return a.name < b.name end)
    return output
end

A.RegisterAction('staff.list', 'staff.manage', function()
    return success({ staff = publicStaff(), roles = SeaMAdminPermissions.PublicRoles() })
end)

local function collectIdentifiers(payload)
    local identifiers, seen = {}, {}
    local function add(kind, raw)
        raw = A.SafeText(raw, 100)
        if raw == '' then return end
        local identifier = A.NormalizeIdentifier(raw:find(':', 1, true) and raw or (kind .. ':' .. raw))
        if identifier and not seen[identifier] then
            seen[identifier] = true
            identifiers[#identifiers + 1] = identifier
        end
    end
    if type(payload.identifiers) == 'table' then
        for _, identifier in ipairs(payload.identifiers) do add('', identifier) end
    end
    add('license', payload.license)
    add('license2', payload.license2)
    add('discord', payload.discordId)
    add('fivem', payload.fivem)
    add('steam', payload.steam)
    add('xbl', payload.xbl)
    add('live', payload.live)
    return identifiers
end

A.RegisterAction('staff.save', 'staff.manage', function(actor, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local name = A.SafeText(payload.name, 80)
    local role = A.SafeText(payload.role, 32)
    local identifiers = collectIdentifiers(payload)
    if #name < 2 or not Config.Roles[role] then return fail('Enter a name and valid role.') end
    if #identifiers < 1 then return fail('Add at least one license, Discord, FiveM, Steam, XBL or Live identifier.') end

    for _, identifier in ipairs(identifiers) do
        local existing = MySQL.single.await('SELECT staff_id FROM seam_admin_staff_identifiers WHERE identifier = ?', { identifier })
        if existing and tonumber(existing.staff_id) ~= id then return fail(identifier .. ' is already assigned to another staff member.') end
    end

    if id > 0 then
        if not MySQL.single.await('SELECT id FROM seam_admin_staff WHERE id = ?', { id }) then return fail('Staff member not found.') end
        MySQL.update.await('UPDATE seam_admin_staff SET name = ?, role = ? WHERE id = ?', { name, role, id })
    else
        id = MySQL.insert.await('INSERT INTO seam_admin_staff (name, role, created_by) VALUES (?, ?, ?)', { name, role, actor.identifier })
    end

    MySQL.update.await('DELETE FROM seam_admin_staff_identifiers WHERE staff_id = ?', { id })
    for _, identifier in ipairs(identifiers) do
        MySQL.insert.await('INSERT INTO seam_admin_staff_identifiers (staff_id, identifier) VALUES (?, ?)', { id, identifier })
    end
    A.RefreshStaff()
    A.Log(actor, 'staff.save', { name = name, identifier = identifiers[1] }, { role = role, staffId = id, identifiers = identifiers })
    return success({ id = id })
end)

A.RegisterAction('staff.delete', 'staff.manage', function(actor, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local row = A.StaffById[id]
    if not row then return fail('Staff member not found.') end
    MySQL.update.await('DELETE FROM seam_admin_staff WHERE id = ?', { id })
    A.RefreshStaff()
    A.Log(actor, 'staff.delete', { name = row.name, identifier = row.identifiers[1] })
    return success()
end)
