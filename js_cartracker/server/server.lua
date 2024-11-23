local ESX = exports['es_extended']:getSharedObject()

local TaskQueue, ActiveTasks, CurrentTask = {}, {}, {
    player = nil,
    vehicle = { model = nil, plate = nil, entity = nil, spawnCoords = nil },
    active = false
}

local NPC = { ped = "mp_m_execpa_01", coords = vec4(206.3391, -760.1450, 47.0770, 181.1776) }

local function LoadDatabase()
    local data = LoadResourceFile(GetCurrentResourceName(), "data/database.json")
    return data and json.decode(data) or {}
end

local function SaveDatabase(data)
    SaveResourceFile(GetCurrentResourceName(), "data/database.json", json.encode(data, { indent = true }))
end

lib.callback.register('js_cartracker:GetPosition', function(source)
    return NPC
end)

lib.callback.register('js_cartracker:CheckPolice', function(source)
    return #ESX.GetExtendedPlayers('job', 'police') >= Config.RequirePolice
end)

lib.callback.register('js_cartracker:GetProfilePlayer', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    local database = LoadDatabase()
    local playerData = database[xPlayer.identifier]

    return playerData or {}
end)

local function AddToQueue(playerId, Points)
    if not ESX.GetPlayerFromId(playerId) or TaskQueue[playerId] then return false end
    table.insert(TaskQueue, { playerId = playerId, identifier = ESX.GetPlayerFromId(playerId).identifier, Points = Points })
    ExecuteQueue()
    return true
end

local function RemoveFromQueue(playerId)
    for i, task in ipairs(TaskQueue) do
        if task.playerId == playerId then table.remove(TaskQueue, i); break end
    end
end

local function DisconnectHandler(playerId)
    RemoveFromQueue(playerId)
    for index, task in ipairs(ActiveTasks) do
        if task.playerId == playerId then
            table.remove(ActiveTasks, index)
            break
        end
    end

    if not CurrentTask.active then
        ExecuteQueue()
    end
end


local function RemovePlayerFromCurrentTask()
    if CurrentTask.active then
        CurrentTask = { player = nil, vehicle = { model = nil, plate = nil, entity = nil, spawnCoords = nil }, active = false }
        ExecuteQueue()
    end
end


local function CreateServerVehicle(model, spawnCoords, heading)
    local vehicle = CreateVehicleServerSetter(model, 'automobile', spawnCoords.x, spawnCoords.y, spawnCoords.z, heading)
    if vehicle then
        local plate = "TKI" .. tostring(math.random(1000, 9999))
        SetVehicleNumberPlateText(vehicle, plate)
        return true, vehicle, plate
    else
        return false
    end
end

local function BeginTask(taskData)
    if CurrentTask.active then return end
    CurrentTask.active, CurrentTask.player = true, taskData.playerId

    local location = Config.Locations[math.random(1, #Config.Locations)]
    local spawn = location.vehPositions[math.random(1, #location.vehPositions)]
    local thiefLevel = GetThiefLevel(taskData.Points)
    local vehicleModel = thiefLevel and thiefLevel.Vehicles[math.random(1, #thiefLevel.Vehicles)]
    if not vehicleModel then return RemovePlayerFromCurrentTask() end

    local success, entity, plate = CreateServerVehicle(vehicleModel, spawn, spawn.w)
    if not success then return RemovePlayerFromCurrentTask() end

    CurrentTask.vehicle = { model = vehicleModel, plate = plate, entity = entity, spawnCoords = spawn }
    TriggerClientEvent('js_cartracker:addCPoints', taskData.playerId, {
        carPosition = spawn, area = location.areaPosition, model = vehicleModel, plate = plate, entity = entity
    })
end

function ExecuteQueue()
    if #TaskQueue > 0 then BeginTask(table.remove(TaskQueue, 1)) end
end

AddEventHandler('playerDropped', function()
    local playerId = source
    DisconnectHandler(playerId)
end)

lib.callback.register('js_cartracker:JoinQueue', function(playerId, Points)
    local policeAvailable = #ESX.GetExtendedPlayers('job', 'police')
    if policeAvailable < Config.RequirePolice then
        return false, "Brak wystarczającej liczby policjantów"
    end
    local success = AddToQueue(playerId, Points)
    if success then
        lib.print.info("Gracz dołączył do kolejki")
    else
        lib.print.error("Nie udało się dodać gracza do kolejki")
    end
    return success, "Dołączono do kolejki"
end)

lib.callback.register('js_cartracker:IsInQueue', function(source)
    local playerId = source

    if CurrentTask and CurrentTask.player == playerId then
        return true
    end

    for _, task in ipairs(TaskQueue) do
        if task.playerId == playerId then
            return true
        end
    end

    return false
end)

RegisterNetEvent('js_cartracker:LeaveTaskQueue', function()
    local playerId = source
    RemoveFromQueue(playerId)
end)

lib.callback.register('js_cartracker:GetServerVehicleNetID', function(source)
    if CurrentTask and CurrentTask.vehicle and DoesEntityExist(CurrentTask.vehicle.entity) then
        return NetworkGetNetworkIdFromEntity(CurrentTask.vehicle.entity)
    end
    return nil
end)


RegisterNetEvent('js_cartracker:setTracker', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)

    if CurrentTask.player == source then
        return
    end

    if CurrentTask.player then
        SendNotification("Zawiodleś inny złodziej zdażyl Ci już ukraść pojazd", "error", 5000, CurrentTask.player)
        TriggerClientEvent('js_cartracker:DestroyVehicle', CurrentTask.player, true)
    end

    CurrentTask.player = source
end)

RegisterNetEvent('js_cartracker:stopMission', function()
    if CurrentTask.vehicle.entity and DoesEntityExist(CurrentTask.vehicle.entity) then DeleteEntity(CurrentTask.vehicle.entity) end
    RemovePlayerFromCurrentTask()
end)

RegisterNetEvent('js_cartracker:PoliceGPS', function(coords)
    local xPlayers = ESX.GetExtendedPlayers('job', 'police')
    for _, xPlayer in pairs(xPlayers) do
        TriggerClientEvent('js_cartracker:PoliceBlip', xPlayer.source, coords, CurrentTask.vehicle.entity)
    end
end)

RegisterNetEvent('js_cartracker:GPSRemoved', function(coords)
    local xPlayers = ESX.GetExtendedPlayers('job', 'police')
    for _, xPlayer in pairs(xPlayers) do
        TriggerClientEvent('js_cartracker:GPSRemoved', xPlayer.source)
    end
end)

RegisterNetEvent('js_cartracker:PointsManage', function(remove, isFinish)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)

    if not CurrentTask or CurrentTask.player ~= source then
        SendNotification("Nie jesteś przypisany do tego zadania", "error", 5000, source)
        return
    end

    AddPointsToPlayer(xPlayer.identifier, remove)

    UpdatePlayerStats(xPlayer.identifier, remove)
    if isFinish then
        GrantRewards(xPlayer.identifier)
    end
end)

function AddPointsToPlayer(identifier, remove)
    local db = LoadDatabase()
    local data = db[identifier] or {}
    local thiefLevel = GetThiefLevel(data.Points or 0)
    local change = (remove and -1 or 1) * (remove and thiefLevel.PointsMultiplier.fail or thiefLevel.PointsMultiplier.success)
    data.Points = math.max(0, (data.Points or 0) + change)
    db[identifier] = data
    SaveDatabase(db)
end

function GrantRewards(identifier)
    local database = LoadDatabase()
    local playerData = database[identifier]

    if not playerData then
        return
    end

    local thiefLevel = GetThiefLevel(playerData.Points)
    if not thiefLevel then
        return
    end

    local rewards = thiefLevel.Reward
    local totalEarned = 0

    for rewardType, rewardConfig in pairs(rewards) do
        if rewardType == "money" or rewardType == "blackmoney" then
            local amount = math.random(rewardConfig.min, rewardConfig.max)
            totalEarned = totalEarned + amount

            if rewardType == "money" then
                exports.ox_inventory:AddItem(source, "money", amount)
            elseif rewardType == "blackmoney" then
                exports.ox_inventory:AddItem(source, "black_money", amount)
            end

            SendNotification("Otrzymałeś $" .. amount .. " jako " .. (rewardType == "money" and "nagrodę" or "czarne pieniądze"), "success", 5000, CurrentTask.player)
        else
            local count = rewardConfig.count or 1
            exports.ox_inventory:AddItem(source, rewardType, count)
            SendNotification("Otrzymałeś " .. count .. "x " .. rewardType .. ".", "success", 5000, CurrentTask.player)
        end
    end

    UpdateEarnedMoney(identifier, totalEarned)
end

function UpdatePlayerStats(identifier, remove)
    local database = LoadDatabase()
    local playerData = database[identifier]

    if not playerData then
        return
    end

    if remove then
        playerData.FailedDeliveries = (playerData.FailedDeliveries or 0) + 1
    else
        playerData.DeliveredVehicles = (playerData.DeliveredVehicles or 0) + 1
    end

    playerData.StolenCars = (playerData.StolenCars or 0) + 1

    database[identifier] = playerData
    SaveDatabase(database)
end

function UpdateEarnedMoney(identifier, amount)
    if amount <= 0 then
        return
    end

    local database = LoadDatabase()
    local playerData = database[identifier]

    if not playerData then
        return
    end

    playerData.EarnedMoney = (playerData.EarnedMoney or 0) + amount

    database[identifier] = playerData
    SaveDatabase(database)
end
