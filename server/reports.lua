local A = SeaMAdmin

local playerCooldowns = {}
local playerRequestBuckets = {}

local function fail(message) return { ok = false, error = message } end
local function success(data) data = data or {}; data.ok = true; return data end

local function reportIdentifier(source)
    return A.Identifier(source, 'license')
        or A.Identifier(source, 'license2')
        or A.Identifier(source, 'fivem')
        or A.Identifier(source, 'steam')
end

local function ownsReport(source, report)
    if not report or not report.reporter_license then return false end
    for _, identifier in ipairs(A.Identifiers(source)) do
        if identifier == report.reporter_license then return true end
    end
    return false
end

local function onlineReporter(report)
    local storedSource = report and tonumber(report.reporter_source)
    if storedSource and GetPlayerName(storedSource) and ownsReport(storedSource, report) then return storedSource end
    if not report or not report.reporter_license then return nil end
    for _, playerId in ipairs(GetPlayers()) do
        local source = tonumber(playerId)
        if ownsReport(source, report) then return source end
    end
    return nil
end

local function categoryAllowed(category)
    category = A.SafeText(category, 32):lower()
    for _, entry in ipairs(Config.ReportCategories or {}) do
        if tostring(entry.id):lower() == category then return category end
    end
    return nil
end

local function rateLimited(source, action, seconds)
    local now = os.time()
    local key = ('%s:%s'):format(source, action)
    if (playerCooldowns[key] or 0) > now then
        return true, playerCooldowns[key] - now
    end
    playerCooldowns[key] = now + seconds
    return false, 0
end

local function requestAllowed(source)
    local now = os.time()
    local bucket = playerRequestBuckets[source]
    if not bucket or now - bucket.startedAt >= 5 then
        bucket = { startedAt = now, count = 0 }
        playerRequestBuckets[source] = bucket
    end
    bucket.count = bucket.count + 1
    return bucket.count <= 25
end

local function notifyStaff(message, reportId)
    for _, playerId in ipairs(GetPlayers()) do
        local source = tonumber(playerId)
        local role = A.RoleForSource(source)
        if role and SeaMAdminPermissions.Has(role, 'reports.view') then
            if message then A.Notify(source, message, 'inform') end
            TriggerClientEvent('seam_admin:client:reportsChanged', source, reportId)
        end
    end
    TriggerEvent('seam_admin:web:broadcast', { type = 'reports.changed', reportId = reportId })
end

local function publishReport(reportId, staffMessage, playerMessage, playerKind)
    local report = MySQL.single.await('SELECT * FROM seam_admin_reports WHERE id = ?', { reportId })
    if not report then return end
    local reporter = onlineReporter(report)
    if reporter then
        if playerMessage then A.Notify(reporter, playerMessage, playerKind or 'inform') end
        TriggerClientEvent('seam_admin:client:reportUpdated', reporter, reportId)
    end
    notifyStaff(staffMessage, reportId)
end

local function listPlayerReports(source)
    local identifier = reportIdentifier(source)
    if not identifier then return fail('A supported FiveM identifier is required to use reports.') end
    MySQL.update.await("UPDATE seam_admin_reports SET reporter_source = ?, updated_at = updated_at WHERE reporter_license = ? AND status <> 'closed'", {
        source, identifier
    })
    local limit = math.max(5, math.min(100, math.floor(tonumber(Config.ReportHistoryLimit) or 30)))
    local reports = MySQL.query.await(([[
        SELECT id, reporter_name, category, subject, message, status, claimed_by, closed_by, created_at, updated_at
        FROM seam_admin_reports
        WHERE reporter_license = ?
        ORDER BY FIELD(status, 'open', 'claimed', 'closed'), updated_at DESC
        LIMIT %d
    ]]):format(limit), { identifier }) or {}
    return success({
        reports = reports,
        categories = Config.ReportCategories or {},
        maxOpen = math.max(1, math.floor(tonumber(Config.ReportMaxOpen) or 3)),
    })
end

local function playerReportDetails(source, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local identifier = reportIdentifier(source)
    if not identifier or id < 1 then return fail('Report not found.') end
    local report = MySQL.single.await('SELECT * FROM seam_admin_reports WHERE id = ? AND reporter_license = ?', { id, identifier })
    if not report then return fail('Report not found.') end
    local messages = MySQL.query.await([[
        SELECT id, sender_name, sender_type, message, created_at
        FROM seam_admin_report_messages
        WHERE report_id = ?
        ORDER BY id ASC
    ]], { id }) or {}
    return success({ report = report, messages = messages })
end

local function createPlayerReport(source, payload)
    local category = categoryAllowed(payload.category)
    local subject = A.SafeText(payload.subject, 120)
    local message = A.SafeText(payload.message, 1000)
    if not category then return fail('Choose a valid report category.') end
    if #subject < 3 then return fail('Enter a subject with at least 3 characters.') end
    if #message < 10 then return fail('Describe the issue using at least 10 characters.') end

    local identifier = reportIdentifier(source)
    if not identifier then return fail('A supported FiveM identifier is required to create a report.') end
    local limited, seconds = rateLimited(source, 'create', math.max(3, tonumber(Config.ReportCreateCooldown) or 10))
    if limited then return fail(('Please wait %s seconds before creating another report.'):format(seconds)) end

    local count = MySQL.scalar.await("SELECT COUNT(*) FROM seam_admin_reports WHERE reporter_license = ? AND status <> 'closed'", { identifier }) or 0
    local maxOpen = math.max(1, math.floor(tonumber(Config.ReportMaxOpen) or 3))
    if tonumber(count) >= maxOpen then return fail(('You can have up to %s active reports. Close one before creating another.'):format(maxOpen)) end

    local name = GetPlayerName(source) or 'Unknown player'
    local id = MySQL.insert.await([[
        INSERT INTO seam_admin_reports (reporter_source, reporter_name, reporter_license, category, subject, message)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { source, name, identifier, category, subject, message })
    if not id then return fail('The report could not be created. Try again.') end

    MySQL.insert.await([[
        INSERT INTO seam_admin_report_messages (report_id, sender_name, sender_type, message)
        VALUES (?, ?, 'player', ?)
    ]], { id, name, message })
    publishReport(id, ('%s opened report #%s: %s'):format(name, id, subject))
    return success({ id = id, message = ('Report #%s was sent to the staff team.'):format(id) })
end

local function replyToPlayerReport(source, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local message = A.SafeText(payload.message, 1000)
    if id < 1 or #message < 1 then return fail('Enter a reply.') end

    local identifier = reportIdentifier(source)
    if not identifier then return fail('A supported FiveM identifier is required to reply.') end
    local limited, seconds = rateLimited(source, 'reply', math.max(1, tonumber(Config.ReportReplyCooldown) or 2))
    if limited then return fail(('Please wait %s seconds before replying again.'):format(seconds)) end

    local report = MySQL.single.await("SELECT * FROM seam_admin_reports WHERE id = ? AND reporter_license = ? AND status <> 'closed'", { id, identifier })
    if not report then return fail('That report is unavailable or closed.') end
    local name = GetPlayerName(source) or report.reporter_name or 'Unknown player'
    MySQL.insert.await([[
        INSERT INTO seam_admin_report_messages (report_id, sender_name, sender_type, message)
        VALUES (?, ?, 'player', ?)
    ]], { id, name, message })
    MySQL.update.await('UPDATE seam_admin_reports SET reporter_source = ?, reporter_name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?', {
        source, name, id
    })
    publishReport(id, ('New player reply on report #%s.'):format(id))
    return success({ message = 'Your reply was sent.' })
end

local function closePlayerReport(source, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local identifier = reportIdentifier(source)
    if not identifier or id < 1 then return fail('Report not found.') end
    local name = GetPlayerName(source) or 'Player'
    local changed = MySQL.update.await([[
        UPDATE seam_admin_reports
        SET status = 'closed', closed_by = ?, reporter_source = ?
        WHERE id = ? AND reporter_license = ? AND status <> 'closed'
    ]], { name, source, id, identifier })
    if changed < 1 then return fail('That report is already closed or unavailable.') end
    publishReport(id, ('Report #%s was closed by the player.'):format(id))
    return success({ message = ('Report #%s was closed.'):format(id) })
end

local playerActions = {
    bootstrap = function(source) return listPlayerReports(source) end,
    details = playerReportDetails,
    create = createPlayerReport,
    reply = replyToPlayerReport,
    close = closePlayerReport,
}

RegisterNetEvent('seam_admin:server:playerReportRequest', function(requestId, action, payload)
    local source = source
    if type(requestId) ~= 'string' then return end
    requestId = A.SafeText(requestId, 96)
    if not requestAllowed(source) then
        return TriggerClientEvent('seam_admin:client:reportResponse', source, requestId, fail('Too many report requests. Please wait a moment.'))
    end
    action = A.SafeText(action, 32)
    local handler = playerActions[action]
    local result
    if not handler then
        result = fail('Unknown report action.')
    else
        local ok, response = xpcall(function()
            return handler(source, type(payload) == 'table' and payload or {})
        end, debug.traceback)
        if ok then
            result = response or success()
        else
            print(('^1[SeaM Admin] Player report action %s failed: %s^7'):format(action, response))
            result = fail('The report action failed on the server. Check the server console.')
        end
    end
    TriggerClientEvent('seam_admin:client:reportResponse', source, requestId, result)
end)

RegisterCommand('report', function(source, args)
    if source == 0 then return print('[SeaM Admin] /report can only be used by a player.') end
    local draft = A.SafeText(table.concat(args, ' '), 1000)
    TriggerClientEvent('seam_admin:client:openReportCenter', source, draft)
end, false)

-- Kept as a convenience for players who prefer commands. The full conversation
-- and the same reply will immediately appear in the /report interface.
RegisterCommand('reportreply', function(source, args)
    if source == 0 then return end
    local id = tonumber(args[1])
    table.remove(args, 1)
    local result = replyToPlayerReport(source, { id = id, message = table.concat(args, ' ') })
    A.Notify(source, result.ok and result.message or result.error, result.ok and 'success' or 'error')
end, false)

A.RegisterAction('reports.list', 'reports.view', function(_, payload)
    local includeClosed = payload.includeClosed == true
    local reports
    if includeClosed then
        reports = MySQL.query.await('SELECT * FROM seam_admin_reports ORDER BY updated_at DESC LIMIT 250') or {}
    else
        reports = MySQL.query.await("SELECT * FROM seam_admin_reports WHERE status <> 'closed' ORDER BY FIELD(status, 'open', 'claimed'), updated_at ASC LIMIT 250") or {}
    end
    return success({ reports = reports })
end)

A.RegisterAction('reports.details', 'reports.view', function(_, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local report = MySQL.single.await('SELECT * FROM seam_admin_reports WHERE id = ?', { id })
    if not report then return fail('Report not found.') end
    local messages = MySQL.query.await('SELECT id, sender_name, sender_type, message, created_at FROM seam_admin_report_messages WHERE report_id = ? ORDER BY id ASC', { id }) or {}
    report.online = onlineReporter(report) ~= nil
    return success({ report = report, messages = messages })
end)

A.RegisterAction('reports.claim', 'reports.manage', function(actor, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local changed = MySQL.update.await("UPDATE seam_admin_reports SET status = 'claimed', claimed_by = ? WHERE id = ? AND status = 'open'", { actor.name, id })
    if changed < 1 then return fail('That report was already claimed or closed.') end
    A.Log(actor, 'report.claim', { name = 'Report #' .. id, identifier = tostring(id) })
    publishReport(id, ('Report #%s was claimed by %s.'):format(id, actor.name), ('Your report #%s was claimed by %s.'):format(id, actor.name), 'inform')
    return success()
end)

A.RegisterAction('reports.reply', 'reports.manage', function(actor, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local message = A.SafeText(payload.message, 1000)
    if #message < 1 then return fail('Enter a reply.') end
    local report = MySQL.single.await("SELECT * FROM seam_admin_reports WHERE id = ? AND status <> 'closed'", { id })
    if not report then return fail('That report is closed or missing.') end
    MySQL.insert.await('INSERT INTO seam_admin_report_messages (report_id, sender_name, sender_type, message) VALUES (?, ?, ?, ?)', {
        id, actor.name, 'staff', message
    })
    if report.status == 'open' then
        MySQL.update.await("UPDATE seam_admin_reports SET status = 'claimed', claimed_by = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", { actor.name, id })
    else
        MySQL.update.await('UPDATE seam_admin_reports SET updated_at = CURRENT_TIMESTAMP WHERE id = ?', { id })
    end
    A.Log(actor, 'report.reply', { name = 'Report #' .. id, identifier = tostring(id) }, { message = message })
    publishReport(id, nil, ('Staff replied to report #%s. Open /report to read it.'):format(id), 'inform')
    return success()
end)

A.RegisterAction('reports.close', 'reports.manage', function(actor, payload)
    local id = math.floor(tonumber(payload.id) or 0)
    local report = MySQL.single.await("SELECT * FROM seam_admin_reports WHERE id = ? AND status <> 'closed'", { id })
    if not report then return fail('That report is already closed or missing.') end
    MySQL.update.await("UPDATE seam_admin_reports SET status = 'closed', closed_by = ? WHERE id = ?", { actor.name, id })
    A.Log(actor, 'report.close', { name = 'Report #' .. id, identifier = tostring(id) })
    publishReport(id, ('Report #%s was closed by %s.'):format(id, actor.name), ('Report #%s was closed by staff.'):format(id), 'success')
    return success()
end)

A.RegisterAction('reports.goto', 'players.goto', function(actor, payload)
    if actor.type ~= 'game' then return fail('This action is only available inside the city.') end
    if Config.RequireDutyForInCityTools ~= false and not actor.onDuty then return fail('Go on admin duty before using in-city staff tools.') end
    local report = MySQL.single.await("SELECT reporter_source, reporter_license FROM seam_admin_reports WHERE id = ? AND status <> 'closed'", { math.floor(tonumber(payload.id) or 0) })
    local reporter = onlineReporter(report)
    if not reporter then return fail('The reporting player is offline.') end
    if not A.CanTarget(actor, reporter) then return fail('You cannot act on a staff member with an equal or higher role.') end
    TriggerClientEvent('seam_admin:client:gotoPlayer', actor.source, reporter)
    A.Log(actor, 'report.goto', reporter, { reportId = payload.id })
    return success()
end)

A.RegisterAction('reports.bring', 'players.bring', function(actor, payload)
    if actor.type ~= 'game' then return fail('This action is only available inside the city.') end
    if Config.RequireDutyForInCityTools ~= false and not actor.onDuty then return fail('Go on admin duty before using in-city staff tools.') end
    local report = MySQL.single.await("SELECT reporter_source, reporter_license FROM seam_admin_reports WHERE id = ? AND status <> 'closed'", { math.floor(tonumber(payload.id) or 0) })
    local reporter = onlineReporter(report)
    if not reporter then return fail('The reporting player is offline.') end
    if not A.CanTarget(actor, reporter) then return fail('You cannot act on a staff member with an equal or higher role.') end
    local ped = GetPlayerPed(actor.source)
    if ped <= 0 then return fail('Your character is unavailable.') end
    local coords = GetEntityCoords(ped)
    TriggerClientEvent('seam_admin:client:teleport', reporter, { x = coords.x, y = coords.y, z = coords.z })
    A.Log(actor, 'report.bring', reporter, { reportId = payload.id })
    return success()
end)

AddEventHandler('playerDropped', function()
    local droppedSource = source
    playerRequestBuckets[droppedSource] = nil
    for key in pairs(playerCooldowns) do
        if key:sub(1, #tostring(droppedSource) + 1) == tostring(droppedSource) .. ':' then playerCooldowns[key] = nil end
    end
end)
