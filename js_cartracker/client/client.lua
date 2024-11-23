local taskBlip, taskPoint, trackerBlip, zoneDrop, trackerPoliceBlip = nil, nil, nil, nil, nil
local isExitingVehicle, GpsDestroyed = false, false
local exitTimerThread, startedGPS = nil, 0

local function createNPC(coords, pedModel)
    lib.requestModel(pedModel, 100)
    local ped = CreatePed(28, joaat(pedModel), coords.x, coords.y, coords.z - 1, coords.w, false, false)
    SetEntityInvincible(ped)
    SetEntityCanBeDamaged(ped)
    SetBlockingOfNonTemporaryEvents(ped)
    FreezeEntityPosition(ped)
    SetPedDiesWhenInjured(ped)
    SetPedCanRagdollFromPlayerImpact(ped)
    SetPedCanRagdoll(ped)
    SetEntityAsMissionEntity(ped, true)
    SetEntityDynamic(ped)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GUARD_STAND', -1, false)
    return ped
end

local function setupNPCInteractions(ped)
    exports.ox_target:addLocalEntity(ped, {
        {
            name = "talk",
            icon = "fa-regular fa-circle-check",
            label = "Weź zlecenie",
            canInteract = function(_, distance) return distance < 1.5 end,
            onSelect = TalkingNPC
        }
    })
end

local function onEnter(coords, zones, index, pedModel)
    if not zones[index].Ped then
        zones[index].Ped = createNPC(coords, pedModel)
        setupNPCInteractions(zones[index].Ped)
    end
end

local function onExit(zones, index)
    if zones[index] and zones[index].Ped then
        exports.ox_target:removeLocalEntity(zones[index].Ped)
        DeletePed(zones[index].Ped)
        zones[index].Ped = nil
    end
end

local function GetVehicleDisplayName(vehicleModel)
    local displayName = GetLabelText(GetDisplayNameFromVehicleModel(joaat(vehicleModel)))
    return displayName ~= "NULL" and displayName or vehicleModel
end

CreateThread(function()
    local NPCData = lib.callback.await('js_cartracker:GetPosition', false)
    if NPCData then
        local zones = {}
        zones[1] = lib.zones.box({
            coords = vector3(NPCData.coords.x, NPCData.coords.y, NPCData.coords.z),
            size = vec3(150, 150, 100),
            rotation = NPCData.coords.w,
            onEnter = function() onEnter(NPCData.coords, zones, 1, NPCData.ped) end,
            onExit = function() onExit(zones, 1) end,
        })
    end
end)

function TalkingNPC()
    local Police = lib.callback.await('js_cartracker:CheckPolice', false)
    local GetProfilePlayer = lib.callback.await('js_cartracker:GetProfilePlayer', false)
    local isInQueue = lib.callback.await('js_cartracker:IsInQueue', false)
    lib.registerContext({
        id = 'js_cartracker_menu',
        title = 'Menu Zlecenia',
        options = {
            { title = 'Twój Profil', onSelect = ProfilePlayer },
            {
                title = isInQueue and 'Opuść kolejkę' or 'Dołącz do kolejki',
                disabled = not Police and not isInQueue,
                onSelect = function()
                    if isInQueue then
                        TriggerServerEvent('js_cartracker:LeaveTaskQueue')
                        TriggerEvent('js_cartracker:DestroyVehicle', false)
                    else
                        lib.callback('js_cartracker:JoinQueue', false, function(success, message)
                            SendNotification(message, success and 'success' or 'error', 1500)
                        end, GetProfilePlayer.Points)
                    end
                end
            }
        }
    })
    lib.showContext('js_cartracker_menu')
end


function ProfilePlayer()
    local GetProfilePlayer = lib.callback.await('js_cartracker:GetProfilePlayer', false)
    local levelData = GetThiefLevel(GetProfilePlayer.Points)

    local vehicleNames = {}
    for _, vehicle in ipairs(levelData.Vehicles) do
        table.insert(vehicleNames, GetVehicleDisplayName(vehicle))
    end

    local nextLevel = nil
    for i, level in ipairs(Config.Levels) do
        if level.RequiredPoints > GetProfilePlayer.Points then
            nextLevel = level
            break
        end
    end
    local pointsToNextLevel = nextLevel and (nextLevel.RequiredPoints - GetProfilePlayer.Points) or 0

    lib.registerContext({
        id = 'js_cartracker_profile',
        title = 'Twój profil',
        menu = 'js_cartracker_menu',
        options = {
            {
                title = 'Twój poziom: ' .. levelData.Name.. ' (' .. GetProfilePlayer.Points .. ' pkt.)',
                icon = 'fa-solid fa-trophy',
                metadata = {
                    {label = 'Klasa pojazdu', value = levelData.Class},
                    {label = 'Punkty do następnego poziomu', value = pointsToNextLevel > 0 and pointsToNextLevel or "Maksymalny poziom"},
                },
                description = 'Obecny poziom i nagrody za wykonanie zadań.',
            },
            {
                title = 'Dostępne pojazdy',
                icon = 'fa-solid fa-car',
                metadata = {
                    {label = 'Pojazdy', value = table.concat(vehicleNames, ', ')},
                },
                description = 'Lista dostępnych pojazdów dla tego poziomu.',
            },
            {
                title = 'Statystyki',
                icon = 'fa-solid fa-chart-bar',
                metadata = {
                    {label = 'Dostarczone pojazdy', value = GetProfilePlayer.DeliveredVehicles},
                    {label = 'Podjęte pojazdy', value = GetProfilePlayer.StolenCars},
                    {label = 'Nieudane dostawy', value = GetProfilePlayer.FailedDeliveries},
                    {label = 'Zarobione pieniądze', value = '$' .. GetProfilePlayer.EarnedMoney},
                },
                description = 'Twoje statystyki z aktualnych działań.',
            },
        }
    })

    lib.showContext('js_cartracker_profile')
end



RegisterNetEvent('js_cartracker:addCPoints', function(data)
    if taskBlip then
        RemoveBlip(taskBlip)
        taskBlip = nil
    end
    SendNotification("Zadanie zostało rozpoczęte. Pojazd: " .. GetVehicleDisplayName(data.model) .. ", Tablica: " .. data.plate, "success", 15000)
    local message =
    'Model pojazdu: ' .. GetVehicleDisplayName(data.model) .. '  \n' ..
    'Rejestracja: ' .. data.plate .. ''


    lib.showTextUI(message, {
        icon = 'car',
    })

    local radius = #(vec3(data.carPosition.x, data.carPosition.y, data.carPosition.z) - data.area) + 100.0
    taskBlip = AddBlipForRadius(data.area.x, data.area.y, data.area.z, radius)

    SetBlipColour(taskBlip, 49)
    SetBlipAlpha(taskBlip, 150)
    SetBlipAsShortRange(taskBlip, false)

    if taskPoint then
        taskPoint:remove()
        taskPoint = nil
    end

    taskPoint = lib.points.new({
        coords = vec3(data.carPosition.x, data.carPosition.y, data.carPosition.z),
        distance = 10 
    })

    function taskPoint:onEnter()
        if taskBlip then
            RemoveBlip(taskBlip)
            taskBlip = nil
        end
        lib.hideTextUI()
    end
end)

RegisterNetEvent('js_cartracker:DestroyVehicle', function(isTrackerStolen, time)
    local function RemoveBlips()
        if taskBlip then
            RemoveBlip(taskBlip)
            taskBlip = nil
        end

        if trackerBlip then
            RemoveBlip(trackerBlip)
            trackerBlip = nil
        end
    end

    local function ClearPointsAndZones()
        if taskPoint then
            taskPoint:remove()
            taskPoint = nil
        end

        if zoneDrop then
            zoneDrop:remove()
            zoneDrop = nil
        end
    end

    RemoveBlips()
    ClearPointsAndZones()

    if isTrackerStolen then
        SendNotification("Twoje zadanie zostało anulowane, tracker przejęty przez innego złodzieja.", "error", 5000)
        TriggerServerEvent('js_cartracker:PointsManage', true)
    else
        if time then
            TriggerServerEvent('js_cartracker:PointsManage', true)
        end
        TriggerServerEvent('js_cartracker:stopMission')
    end

    lib.hideTextUI()
    taskBlip, taskPoint, trackerBlip, zoneDrop = nil, nil, nil, nil
    isExitingVehicle, GpsDestroyed = false, false
    exitTimerThread, startedGPS = nil, 0
end)



lib.onCache('vehicle', function(vehicle)
    local function ResetExitTimer()
        isExitingVehicle = false
        if exitTimerThread then
            lib.hideTextUI()
            exitTimerThread = nil
        end
    end

    if vehicle then
        ResetExitTimer()

        local clientNetID = NetworkGetNetworkIdFromEntity(vehicle)
        local serverNetID = lib.callback.await('js_cartracker:GetServerVehicleNetID', false)

        if serverNetID and clientNetID == serverNetID then
            TriggerServerEvent('js_cartracker:setTracker', clientNetID)
            TriggerEvent('js_cartracker:TimerVehicle')
        end
    else
        local serverNetID = lib.callback.await('js_cartracker:GetServerVehicleNetID', false)
        if not serverNetID or GpsDestroyed then
            ResetExitTimer()
            return
        end

        if not isExitingVehicle then
            isExitingVehicle = true
            local returnSeconds = 5

            exitTimerThread = Citizen.CreateThread(function()
                while returnSeconds > 0 do
                    Citizen.Wait(1000)
                    returnSeconds = returnSeconds - 1

                    lib.showTextUI(("Zostało ci %s sekund na powrót do auta"):format(returnSeconds), {
                        position = "top-center",
                        icon = 'car',
                    })

                    if not isExitingVehicle then
                        lib.hideTextUI()
                        return
                    end
                end

                lib.hideTextUI()
                isExitingVehicle = false

                if not GpsDestroyed and serverNetID then
                    TriggerEvent('js_cartracker:DestroyVehicle', false, true)
                end
            end)
        end
    end
end)


local function GPSDestroyed()
    GpsDestroyed = true
    SendNotification("Zagłuszono lokalizator, udaj się na miejsce spotkania.", "success", 5000)
    lib.hideTextUI()
    TriggerServerEvent('js_cartracker:GPSRemoved')

    local trackerLocation = Config.CarReturnLocation[math.random(1, #Config.CarReturnLocation)]
    trackerBlip = AddBlipForCoord(trackerLocation.x, trackerLocation.y, trackerLocation.z)
    SetBlipSprite(trackerBlip, 271)
    SetBlipScale(trackerBlip, 1.0)
    SetBlipDisplay(trackerBlip, 2)
    SetBlipColour(trackerBlip, 73)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString('# Spotkanie')
    EndTextCommandSetBlipName(trackerBlip)
    SetBlipRoute(trackerBlip, true)

    zoneDrop = lib.zones.box({
        coords = trackerLocation,
        size = vector3(6, 6, 6),
        rotation = 0,
        inside = function()
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                TaskLeaveVehicle(PlayerPedId(), GetVehiclePedIsIn(PlayerPedId(), false), 0)
                TriggerServerEvent('js_cartracker:PointsManage', false, true)
                TriggerEvent('js_cartracker:DestroyVehicle', false)
                if zoneDrop then
                    zoneDrop:remove()
                end
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end,
    })
end

RegisterNetEvent('js_cartracker:PoliceBlip', function(coords)
    if trackerPoliceBlip then
        RemoveBlip(trackerPoliceBlip)
    end
    trackerPoliceBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(trackerPoliceBlip, 227)
    SetBlipScale(trackerPoliceBlip, 1.5)
    SetBlipDisplay(trackerPoliceBlip, 2)
    SetBlipColour(trackerPoliceBlip, 49)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString('# Skradziony pojazd')
    EndTextCommandSetBlipName(trackerPoliceBlip)
end)

RegisterNetEvent('js_cartracker:GPSRemoved', function()
    Citizen.SetTimeout(5000, function()
        if trackerPoliceBlip then
            RemoveBlip(trackerPoliceBlip)
            trackerPoliceBlip = nil
        end
    end)
end)

AddEventHandler('js_cartracker:TimerVehicle', function()
    startedGPS = GetGameTimer() 

    while true do
        Citizen.Wait(1000)

        if IsPedInAnyVehicle(PlayerPedId(), false) then
            local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
            local vehicleCoords = GetEntityCoords(vehicle)

            local currentTime = GetGameTimer()
            local elapsedTimeInSeconds = (currentTime - startedGPS) / 1000 

            if elapsedTimeInSeconds >= 300 and not GpsDestroyed then
                GPSDestroyed()
                GpsDestroyed = true
            end

            if not GpsDestroyed then
                TriggerServerEvent('js_cartracker:PoliceGPS', vehicleCoords)
            else
                break
            end
        else
            lib.hideTextUI()
            break
        end
    end
end)
