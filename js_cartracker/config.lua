Config = {}

Config.RequirePolice = 0

Config.Levels = {
    [1] = {
        Name = "Insignificant Thief",
        RequiredPoints = 0,
        PointsMultiplier = { success = 1, fail = 1 },
        Reward = { 
            ['money'] = {min = 1000, max = 2000},
            ['blackmoney'] = {min = 1000, max = 2000},
        },
        Class = "D",
        Vehicles = { 'brioso', 'blade', 'buccaneer', 'moonbeam2', 'impaler', 'gauntlet' }
    },
    [2] = {
        Name = "Novice Thief",
        RequiredPoints = 20,
        PointsMultiplier = { success = 1, fail = 1 },
        Reward = { 
            ['money'] = {min = 2000, max = 3000},
            ['blackmoney'] = {min = 2000, max = 3000},
        },
        Class = "B",
        Vehicles = { 'gauntlet4', 'sultan', 'everon', 'buffalo2', 'jester', 'massacro', 'ninef' }
    },
    [3] = {
        Name = "Experienced Thief",
        RequiredPoints = 50,
        PointsMultiplier = { success = 1, fail = 1 },
        Reward = { 
            ['money'] = {min = 3000, max = 5000},
            ['bread'] = {count = 1}, 
        },
        Class = "A",
        Vehicles = { 'caracara2', 'elegy', 'sultan2', 'novak', 'banshee2', 'dubsta2', 'sentinel', 'calico', 'vstr', 'jester3' }
    },
    [4] = {
        Name = "Thief",
        RequiredPoints = 75,
        PointsMultiplier = { success = 1, fail = 1 },
        Reward = { 
            ['water'] = {count = 2}, 
        },
        Class = "A+",
        Vehicles = { 'rebla', 'vigero2', 'euros', 'toros', 'growler', 'vectre', 'cypherwb' }
    }
}


Config.Locations = {
    {
        areaPosition = vec3(203.6693, -760.6760, 47770),
        vehPositions = {
            vec4(206.8897, -764.8753, 47.0769, 201.4307),
        }
    },
}

Config.CarReturnLocation = { 
   vec3(199.4125, -741.7271, 47.0760)
}

function SendNotification(message, typ, duration, id)
    if type(id) == "number" then
        TriggerClientEvent('ox_lib:notify', id, {
            description = message,
            duration = duration or 500,
            position = 'top',
            type = typ or 'success'
        })
    else
        lib.notify({
            description = message,
            duration = duration or 500,
            position = 'top',
            type = typ or 'success'
        })
    end
end


function GetThiefLevel(points)
    local level = nil
    for i = #Config.Levels, 1, -1 do
        if points >= Config.Levels[i].RequiredPoints then
            level = Config.Levels[i]
            break
        end
    end
    return level or Config.Levels[1]
end