if isServer() then return end

local function onServerCommand(module, command, args)
    if module == "TheFogDescend" then
        if command == "playSiren" then
            local soundManager = getSoundManager()
            if soundManager then
                soundManager:PlaySound("TheFogDescend_Siren", false, 1.0)
            end
        elseif command == "checkVehicleStall" then
            local player = getPlayer()
            if not player then return end

            local vehicle = player:getVehicle()
            if not vehicle or vehicle:getDriver() ~= player then return end

            if vehicle:isEngineRunning() then
                -- 2% chance of engine stall every minute
                if ZombRandFloat(0.0, 1.0) < 0.02 then
                    sendClientCommand('vehicle', 'shutOff', {})
                    player:Say("The engine sputtered and died in the thick fog...")
                end
            end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
