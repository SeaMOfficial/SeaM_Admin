local states = {
    noclip = false,
    invisible = false,
    god = false,
    superjump = false,
    fastrun = false,
    infiniteammo = false,
    names = false,
    blips = false,
    radar = false,
    stamina = false,
    ragdoll = false,
    coords = false,
    devlaser = false,
}

local playerBlips = {}
local gamerTags = {}
local noclipEntity = 0

local function notify(message, kind)
    local ok = pcall(function()
        exports['SeaM_Core']:Notify(message, kind or 'inform', 4000, 'SeaM Admin')
    end)
    if not ok then TriggerEvent('SeaM_Core:notify', message, kind or 'inform', 4000, 'SeaM Admin') end
end

local function title(value)
    local labels = {
        noclip = 'Noclip', invisible = 'Invisibility', god = 'God mode', superjump = 'Super jump',
        fastrun = 'Fast run', infiniteammo = 'Infinite ammo', names = 'Player names', blips = 'Player blips',
        radar = 'Forced radar', stamina = 'Infinite stamina', ragdoll = 'No ragdoll', coords = 'Coordinate display',
        devlaser = 'Entity laser',
    }
    return labels[value] or value
end

local function removePlayerOverlays()
    for _, blip in pairs(playerBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    for _, tag in pairs(gamerTags) do if IsMpGamerTagActive(tag) then RemoveMpGamerTag(tag) end end
    playerBlips, gamerTags = {}, {}
end

local function rotationToDirection(rotation)
    local adjustedZ = math.rad(rotation.z)
    local adjustedX = math.rad(rotation.x)
    local cosine = math.abs(math.cos(adjustedX))
    return vector3(-math.sin(adjustedZ) * cosine, math.cos(adjustedZ) * cosine, math.sin(adjustedX))
end

local function drawText(x, y, text, scale, centered)
    SetTextFont(4)
    SetTextScale(scale or 0.32, scale or 0.32)
    SetTextColour(242, 210, 138, 235)
    SetTextOutline()
    SetTextCentre(centered == true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function stopNoclip()
    if noclipEntity ~= 0 and DoesEntityExist(noclipEntity) then
        FreezeEntityPosition(noclipEntity, false)
        SetEntityCollision(noclipEntity, true, true)
        SetEntityAlpha(noclipEntity, 255, false)
        if not states.god then SetEntityInvincible(noclipEntity, false) end
    end
    noclipEntity = 0
end

local function resetPowers()
    for action in pairs(states) do states[action] = false end
    local ped = PlayerPedId()
    stopNoclip()
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetSwimMultiplierForPlayer(PlayerId(), 1.0)
    SetPedInfiniteAmmoClip(ped, false)
    SetPedCanRagdoll(ped, true)
    removePlayerOverlays()
end

local function raycastFromCamera(distance)
    local startCoords = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local destination = startCoords + direction * (distance or 300.0)
    local handle = StartShapeTestRay(startCoords.x, startCoords.y, startCoords.z, destination.x, destination.y, destination.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entity = GetShapeTestResult(handle)
    return hit == 1, endCoords, entity, startCoords
end

RegisterNetEvent('seam_admin:client:setPower', function(action, enabled)
    if states[action] == nil then return end
    if enabled == nil then enabled = not states[action] end
    states[action] = enabled == true

    local ped = PlayerPedId()
    if action == 'radar' then
        DisplayRadar(states.radar)
    elseif action == 'ragdoll' then
        SetPedCanRagdoll(ped, not states.ragdoll)
    elseif action == 'noclip' and not states.noclip then
        stopNoclip()
    elseif action == 'invisible' and not states.invisible then
        SetEntityVisible(ped, true, false)
        ResetEntityAlpha(ped)
    elseif action == 'god' and not states.god and not states.noclip then
        SetEntityInvincible(ped, false)
        SetPlayerInvincible(PlayerId(), false)
    elseif action == 'fastrun' and not states.fastrun then
        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
        SetSwimMultiplierForPlayer(PlayerId(), 1.0)
    elseif action == 'infiniteammo' and not states.infiniteammo then
        SetPedInfiniteAmmoClip(ped, false)
    elseif (action == 'names' or action == 'blips') and not states.names and not states.blips then
        removePlayerOverlays()
    end

    notify(('%s %s'):format(title(action), states[action] and 'enabled' or 'disabled'), 'success')
end)

RegisterNetEvent('seam_admin:client:dutyState', function(enabled)
    if enabled ~= true then resetPowers() end
    notify(enabled and 'You are now on admin duty.' or 'You are now off admin duty.', enabled and 'success' or 'inform')
end)

CreateThread(function()
    while true do
        local active = states.noclip or states.invisible or states.god or states.superjump or states.fastrun
            or states.infiniteammo or states.stamina or states.ragdoll or states.coords or states.devlaser
        if not active then Wait(350) else
            local ped = PlayerPedId()
            if states.god then
                SetPlayerInvincible(PlayerId(), true)
                SetEntityInvincible(ped, true)
                SetEntityHealth(ped, math.max(GetEntityHealth(ped), 200))
            end
            if states.invisible then
                SetEntityVisible(ped, false, false)
                SetLocalPlayerVisibleLocally(true)
            end
            if states.superjump then SetSuperJumpThisFrame(PlayerId()) end
            if states.fastrun then
                SetRunSprintMultiplierForPlayer(PlayerId(), 1.49)
                SetSwimMultiplierForPlayer(PlayerId(), 1.49)
            end
            if states.infiniteammo then SetPedInfiniteAmmoClip(ped, true) end
            if states.stamina then RestorePlayerStamina(PlayerId(), 1.0) end
            if states.ragdoll then SetPedCanRagdoll(ped, false) end

            if states.coords then
                local coords = GetEntityCoords(ped)
                drawText(0.015, 0.72, ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, GetEntityHeading(ped)), 0.31)
            end

            if states.devlaser then
                local hit, endCoords, entity, startCoords = raycastFromCamera(500.0)
                DrawLine(startCoords.x, startCoords.y, startCoords.z, endCoords.x, endCoords.y, endCoords.z, 215, 168, 78, 220)
                if hit and entity and entity ~= 0 and DoesEntityExist(entity) then
                    local entityType = GetEntityType(entity)
                    local typeLabel = entityType == 1 and 'PED' or entityType == 2 and 'VEHICLE' or entityType == 3 and 'OBJECT' or 'ENTITY'
                    local coords = GetEntityCoords(entity)
                    local networkId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or 0
                    local info = ('%s  model %s  net %s  health %s~n~vector4(%.2f, %.2f, %.2f, %.2f)~n~[E] copy   [DEL] delete'):format(
                        typeLabel, GetEntityModel(entity), networkId, GetEntityHealth(entity), coords.x, coords.y, coords.z, GetEntityHeading(entity)
                    )
                    drawText(0.5, 0.82, info, 0.30, true)
                    DisableControlAction(0, 38, true)
                    DisableControlAction(0, 178, true)
                    if IsDisabledControlJustPressed(0, 38) then
                        SendNUIMessage({ type = 'copy', value = info:gsub('~n~', ' ') })
                        notify('Entity details copied.', 'success')
                    elseif IsDisabledControlJustPressed(0, 178) and not (IsEntityAPed(entity) and IsPedAPlayer(entity)) then
                        if networkId > 0 then
                            TriggerServerEvent('seam_admin:server:deleteEntity', networkId)
                        else
                            SetEntityAsMissionEntity(entity, true, true)
                            DeleteEntity(entity)
                        end
                    end
                else
                    drawText(0.5, 0.84, 'ENTITY LASER · Aim at a world entity', 0.30, true)
                end
            end
            Wait(0)
        end
    end
end)

CreateThread(function()
    while true do
        if states.noclip then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            local entity = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped and vehicle or ped
            if noclipEntity ~= entity then
                stopNoclip()
                noclipEntity = entity
            end

            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, false, false)
            SetEntityInvincible(entity, true)
            SetEntityAlpha(entity, 190, false)
            SetEntityVelocity(entity, 0.0, 0.0, 0.0)

            for _, control in ipairs({ 30, 31, 32, 33, 34, 35, 21, 22, 36, 44 }) do DisableControlAction(0, control, true) end
            local rotation = GetGameplayCamRot(2)
            local direction = rotationToDirection(rotation)
            local right = vector3(math.cos(math.rad(rotation.z)), math.sin(math.rad(rotation.z)), 0.0)
            local speed = IsDisabledControlPressed(0, 21) and 8.0 or IsDisabledControlPressed(0, 36) and 0.45 or 2.0
            local position = GetEntityCoords(entity)
            if IsDisabledControlPressed(0, 32) then position = position + direction * speed end
            if IsDisabledControlPressed(0, 33) then position = position - direction * speed end
            if IsDisabledControlPressed(0, 34) then position = position - right * speed end
            if IsDisabledControlPressed(0, 35) then position = position + right * speed end
            if IsDisabledControlPressed(0, 22) then position = position + vector3(0.0, 0.0, speed) end
            if IsDisabledControlPressed(0, 44) then position = position - vector3(0.0, 0.0, speed) end
            SetEntityCoordsNoOffset(entity, position.x, position.y, position.z, true, true, true)
            SetEntityHeading(entity, rotation.z)
            drawText(0.5, 0.94, ('NOCLIP · %.2fx · SHIFT fast · CTRL precise'):format(speed / 2.0), 0.28, true)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if states.names or states.blips then
            local active = {}
            for _, player in ipairs(GetActivePlayers()) do
                if player ~= PlayerId() then
                    active[player] = true
                    local targetPed = GetPlayerPed(player)
                    if states.blips then
                        local blip = playerBlips[player]
                        if not blip or not DoesBlipExist(blip) then
                            blip = AddBlipForEntity(targetPed)
                            SetBlipCategory(blip, 7)
                            SetBlipScale(blip, 0.75)
                            ShowHeadingIndicatorOnBlip(blip, true)
                            playerBlips[player] = blip
                        end
                    elseif playerBlips[player] then
                        RemoveBlip(playerBlips[player]); playerBlips[player] = nil
                    end
                    if states.names then
                        local tag = gamerTags[player]
                        if not tag or not IsMpGamerTagActive(tag) then
                            tag = CreateFakeMpGamerTag(targetPed, ('[%s] %s'):format(GetPlayerServerId(player), GetPlayerName(player)), false, false, '', 0)
                            gamerTags[player] = tag
                        end
                        SetMpGamerTagVisibility(tag, 0, true)
                        SetMpGamerTagVisibility(tag, 2, true)
                        SetMpGamerTagHealthBarColor(tag, 18)
                    elseif gamerTags[player] then
                        RemoveMpGamerTag(gamerTags[player]); gamerTags[player] = nil
                    end
                end
            end
            for player, blip in pairs(playerBlips) do if not active[player] then RemoveBlip(blip); playerBlips[player] = nil end end
            for player, tag in pairs(gamerTags) do if not active[player] then RemoveMpGamerTag(tag); gamerTags[player] = nil end end
            Wait(750)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    resetPowers()
end)
