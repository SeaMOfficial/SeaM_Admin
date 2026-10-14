local menuOpen = false
local uiMode = nil
local requestCounter = 0
local pending = {}
local previousCoords = nil
local vehicleGod = {}

local function resetProtectedVehicles()
    for vehicle in pairs(vehicleGod) do
        if DoesEntityExist(vehicle) then
            SetEntityInvincible(vehicle, false)
            SetVehicleCanBeVisiblyDamaged(vehicle, true)
        end
    end
    vehicleGod = {}
end

local function closeMenu()
    menuOpen = false
    uiMode = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

local function notify(message, kind)
    local ok = pcall(function()
        exports['SeaM_Core']:Notify(message, kind or 'inform', 4000, 'SeaM Admin')
    end)
    if not ok then TriggerEvent('SeaM_Core:notify', message, kind or 'inform', 4000, 'SeaM Admin') end
end

local function teleport(coords)
    if not coords or not coords.x or not coords.y or not coords.z then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped and vehicle or ped
    local current = GetEntityCoords(entity)
    previousCoords = { x = current.x, y = current.y, z = current.z, w = GetEntityHeading(entity) }
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(entity, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false)
    if coords.w then SetEntityHeading(entity, coords.w + 0.0) end
    local timeout = GetGameTimer() + 2000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(0) end
    DoScreenFadeIn(250)
end

RegisterCommand(Config.Command, function()
    TriggerServerEvent('seam_admin:server:open')
end, false)

RegisterKeyMapping(Config.Command, 'Open SeaM Admin', 'keyboard', Config.Keybind)

RegisterNetEvent('seam_admin:client:open', function()
    menuOpen = true
    uiMode = 'admin'
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open' })
end)

RegisterNetEvent('seam_admin:client:openReportCenter', function(draft)
    menuOpen = true
    uiMode = 'report'
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'openPlayerReports', draft = tostring(draft or '') })
end)

RegisterNetEvent('seam_admin:client:close', closeMenu)

RegisterNetEvent('seam_admin:client:response', function(requestId, result)
    local callback = pending[requestId]
    if callback then
        pending[requestId] = nil
        callback(result)
    end
end)

RegisterNetEvent('seam_admin:client:reportResponse', function(requestId, result)
    local callback = pending[requestId]
    if callback then
        pending[requestId] = nil
        callback(result)
    end
end)

RegisterNetEvent('seam_admin:client:reportUpdated', function(reportId)
    if menuOpen and uiMode == 'report' then
        SendNUIMessage({ type = 'playerReportUpdated', reportId = reportId })
    end
end)

RegisterNetEvent('seam_admin:client:reportsChanged', function(reportId)
    if menuOpen and uiMode == 'admin' then
        SendNUIMessage({ type = 'adminReportsChanged', reportId = reportId })
    end
end)

RegisterNUICallback('rpc', function(data, cb)
    requestCounter = requestCounter + 1
    local requestId = ('%s:%s'):format(GetPlayerServerId(PlayerId()), requestCounter)
    pending[requestId] = cb
    TriggerServerEvent('seam_admin:server:request', requestId, data.action, data.payload or {})
    SetTimeout(15000, function()
        if pending[requestId] then
            pending[requestId]({ ok = false, error = 'The server did not respond in time.' })
            pending[requestId] = nil
        end
    end)
end)

RegisterNUICallback('reportRpc', function(data, cb)
    requestCounter = requestCounter + 1
    local requestId = ('report:%s:%s'):format(GetPlayerServerId(PlayerId()), requestCounter)
    pending[requestId] = cb
    TriggerServerEvent('seam_admin:server:playerReportRequest', requestId, data.action, data.payload or {})
    SetTimeout(15000, function()
        if pending[requestId] then
            pending[requestId]({ ok = false, error = 'The report server did not respond in time.' })
            pending[requestId] = nil
        end
    end)
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({ ok = true })
end)

RegisterNUICallback('copy', function(data, cb)
    SendNUIMessage({ type = 'copy', value = tostring(data.value or '') })
    cb({ ok = true })
end)

RegisterNetEvent('seam_admin:client:teleport', function(coords)
    teleport(coords)
end)

RegisterNetEvent('seam_admin:client:gotoPlayer', function(targetServerId)
    local targetPlayer = GetPlayerFromServerId(tonumber(targetServerId))
    if targetPlayer == -1 then return notify('That player is outside your streaming range. Try again.', 'error') end
    local targetPed = GetPlayerPed(targetPlayer)
    local coords = GetEntityCoords(targetPed)
    teleport({ x = coords.x, y = coords.y, z = coords.z + 1.0 })
end)

RegisterNetEvent('seam_admin:client:setFrozen', function(enabled)
    FreezeEntityPosition(PlayerPedId(), enabled == true)
    notify(enabled and 'You were frozen by staff.' or 'You were unfrozen by staff.', enabled and 'warning' or 'success')
end)

RegisterNetEvent('seam_admin:client:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    notify('You were healed by staff.', 'success')
end)

RegisterNetEvent('seam_admin:client:kill', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('seam_admin:client:setArmour', function(amount)
    SetPedArmour(PlayerPedId(), math.min(100, math.max(0, math.floor(tonumber(amount) or 0))))
end)

RegisterNetEvent('seam_admin:client:clearTasks', function()
    ClearPedTasksImmediately(PlayerPedId())
    ClearPedSecondaryTask(PlayerPedId())
    notify('Your current animation and tasks were cleared by staff.', 'inform')
end)

RegisterNetEvent('seam_admin:client:setModel', function(model)
    local hash = joaat(tostring(model or ''))
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return notify('Staff selected an invalid pedestrian model.', 'error') end
    RequestModel(hash)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(hash) then return notify('The pedestrian model did not load.', 'error') end
    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)
    notify(('Your model was changed to %s by staff.'):format(model), 'inform')
end)

RegisterNetEvent('seam_admin:client:vehicleAction', function(action, model)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if action == 'spawn' then
        local hash = joaat(model)
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return notify('Invalid vehicle model.', 'error') end
        RequestModel(hash)
        local deadline = GetGameTimer() + 10000
        while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
        if not HasModelLoaded(hash) then return notify('The vehicle model did not load.', 'error') end
        local coords = GetEntityCoords(ped)
        vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
        SetVehicleOnGroundProperly(vehicle)
        SetPedIntoVehicle(ped, vehicle, -1)
        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleNumberPlateText(vehicle, ('ADMIN%03d'):format(math.random(0, 999)))
        SetModelAsNoLongerNeeded(hash)
        return notify(('Spawned %s.'):format(model), 'success')
    end

    if vehicle == 0 then
        local coords = GetEntityCoords(ped)
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 7.0, 0, 71)
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return notify('No vehicle found.', 'error') end
    if action == 'repair' then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleDirtLevel(vehicle, 0.0)
        for wheel = 0, 7 do SetVehicleTyreFixed(vehicle, wheel) end
    elseif action == 'delete' then
        vehicleGod[vehicle] = nil
        NetworkRequestControlOfEntity(vehicle)
        local timeout = GetGameTimer() + 1500
        while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do Wait(0) end
        DeleteEntity(vehicle)
    elseif action == 'max' then
        SetVehicleModKit(vehicle, 0)
        for modType = 0, 49 do
            local count = GetNumVehicleMods(vehicle, modType)
            if count > 0 then SetVehicleMod(vehicle, modType, count - 1, false) end
        end
        ToggleVehicleMod(vehicle, 18, true)
        ToggleVehicleMod(vehicle, 20, true)
        ToggleVehicleMod(vehicle, 22, true)
        SetVehicleTyresCanBurst(vehicle, false)
    elseif action == 'fuel' then
        SetVehicleFuelLevel(vehicle, 100.0)
        Entity(vehicle).state.fuel = 100.0
    elseif action == 'clean' then
        SetVehicleDirtLevel(vehicle, 0.0)
        WashDecalsFromVehicle(vehicle, 1.0)
    elseif action == 'flip' then
        local heading = GetEntityHeading(vehicle)
        SetEntityRotation(vehicle, 0.0, 0.0, heading, 2, true)
        SetVehicleOnGroundProperly(vehicle)
    elseif action == 'boost' then
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleEnginePowerMultiplier(vehicle, 45.0)
        SetVehicleForwardSpeed(vehicle, math.max(35.0, GetEntitySpeed(vehicle) + 18.0))
        SetTimeout(5000, function()
            if DoesEntityExist(vehicle) then SetVehicleEnginePowerMultiplier(vehicle, 0.0) end
        end)
    elseif action == 'engine' then
        SetVehicleEngineOn(vehicle, not GetIsVehicleEngineRunning(vehicle), false, true)
    elseif action == 'unlock' then
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    elseif action == 'god' then
        vehicleGod[vehicle] = not vehicleGod[vehicle]
        SetEntityInvincible(vehicle, vehicleGod[vehicle])
        SetVehicleCanBeVisiblyDamaged(vehicle, not vehicleGod[vehicle])
        notify(vehicleGod[vehicle] and 'Vehicle protection enabled.' or 'Vehicle protection disabled.', 'success')
        return
    elseif action == 'inspect' then
        local coords = GetEntityCoords(vehicle)
        local modelHash = GetEntityModel(vehicle)
        local details = ('model=%s hash=%s plate=%s coords=vector4(%.2f, %.2f, %.2f, %.2f) netId=%s'):format(
            GetDisplayNameFromVehicleModel(modelHash), modelHash, GetVehicleNumberPlateText(vehicle),
            coords.x, coords.y, coords.z, GetEntityHeading(vehicle), NetworkGetNetworkIdFromEntity(vehicle)
        )
        SendNUIMessage({ type = 'copy', value = details })
        notify('Vehicle details copied.', 'success')
        return
    end
    notify('Vehicle action completed.', 'success')
end)

RegisterNetEvent('seam_admin:client:dutyState', function(enabled)
    if enabled ~= true then resetProtectedVehicles() end
end)

RegisterNetEvent('seam_admin:client:clearArea', function(entityType, radius)
    radius = math.min(tonumber(radius) or 25, Config.MaxClearAreaRadius or 100)
    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local currentVehicle = GetVehiclePedIsIn(ped, false)
    local pools = {}
    if entityType == 'vehicles' or entityType == 'all' then pools[#pools + 1] = 'CVehicle' end
    if entityType == 'peds' or entityType == 'all' then pools[#pools + 1] = 'CPed' end
    if entityType == 'objects' or entityType == 'all' then pools[#pools + 1] = 'CObject' end
    local networkIds, localDeleted = {}, 0
    for _, pool in ipairs(pools) do
        for _, entity in ipairs(GetGamePool(pool)) do
            if DoesEntityExist(entity) and entity ~= ped and entity ~= currentVehicle and #(GetEntityCoords(entity) - origin) <= radius then
                if not IsEntityAPed(entity) or not IsPedAPlayer(entity) then
                    if NetworkGetEntityIsNetworked(entity) then
                        networkIds[#networkIds + 1] = NetworkGetNetworkIdFromEntity(entity)
                    else
                        SetEntityAsMissionEntity(entity, true, true)
                        DeleteEntity(entity)
                        localDeleted = localDeleted + 1
                    end
                end
            end
        end
    end
    if #networkIds > 0 then TriggerServerEvent('seam_admin:server:clearEntities', networkIds) end
    notify(('Clear-area request sent for %s networked and %s local entities.'):format(#networkIds, localDeleted), 'success')
end)

RegisterNetEvent('seam_admin:client:setWeather', function(weather)
    SetWeatherTypeOvertimePersist(weather, 2.0)
    Wait(2000)
    SetWeatherTypeNowPersist(weather)
end)

RegisterNetEvent('seam_admin:client:setTime', function(hour, minute)
    NetworkOverrideClockTime(tonumber(hour) or 12, tonumber(minute) or 0, 0)
end)

RegisterNetEvent('seam_admin:client:selfAction', function(action, enabled)
    if action == 'marker' then
        local waypoint = GetFirstBlipInfoId(8)
        if not DoesBlipExist(waypoint) then return notify('Place a waypoint first.', 'error') end
        local coords = GetBlipInfoIdCoord(waypoint)
        local found, ground = false, 0.0
        for height = 1000.0, 0.0, -50.0 do
            SetEntityCoordsNoOffset(PlayerPedId(), coords.x, coords.y, height, false, false, false)
            Wait(0)
            found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, height, false)
            if found then break end
        end
        teleport({ x = coords.x, y = coords.y, z = found and ground + 1.0 or 1000.0 })
    elseif action == 'back' then
        if not previousCoords then return notify('No previous location is stored.', 'error') end
        local current = GetEntityCoords(PlayerPedId())
        local destination = previousCoords
        previousCoords = current
        teleport({ x = destination.x, y = destination.y, z = destination.z, w = destination.w })
    else
        TriggerEvent('seam_admin:client:setPower', action, enabled)
    end
end)

CreateThread(function()
    while true do
        if menuOpen and IsControlJustReleased(0, 200) then
            closeMenu()
        end
        Wait(menuOpen and 0 or 300)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    resetProtectedVehicles()
    SetNuiFocus(false, false)
end)
