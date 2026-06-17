if isServer() then return end

TheFogDescend = TheFogDescend or {}

-- Cache global functions for speed (hot paths)
local getGameTime = getGameTime
local getPlayer = getPlayer
local getSoundManager = getSoundManager
local sendClientCommand = sendClientCommand
local ZombRandFloat = ZombRandFloat
local math_max = math.max
local math_min = math.min
local math_abs = math.abs

local lastHours = nil

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
        elseif command == "syncState" then
            TheFogDescend.isEventActive = args.isEventActive
        elseif command == "startEvent" then
            TheFogDescend.isEventActive = true
        elseif command == "stopEvent" then
            TheFogDescend.isEventActive = false
        end
    end
end

local function onGameStart()
    lastHours = nil
    if isClient() then
        sendClientCommand("TheFogDescend", "requestState", {})
    end
end



local function onPlayerUpdate(player)
    -- Only run for the local player
    if not player or not player:isLocalPlayer() then return end

    -- Fast-path optimization: exit immediately if the event is inactive and the player is clean
    local modData = player:getModData()
    local currentToxicity = modData.fogToxicity or 0.0
    if not TheFogDescend.isEventActive and currentToxicity <= 0 then
        lastHours = nil
        return
    end

    if not player:isAlive() then
        modData.fogToxicity = 0.0
        lastHours = nil
        return
    end

    local currentHours = getGameTime():getWorldAgeHours()
    if not lastHours or currentHours < lastHours then
        lastHours = currentHours
        return
    end

    local dt = currentHours - lastHours
    lastHours = currentHours

    -- Defensively ignore negative dt or extremely large jumps (e.g. teleporting, debug)
    if dt <= 0 or dt > 24 then
        return
    end

    -- Determine if toxic fog is enabled and active
    local toxicFogEnabled = LivingWorldFramework.GetConfig("TheFogDescend", "ToxicFogEnabled")
    if toxicFogEnabled == nil then
        error("[TheFogDescend] LivingWorldFramework config 'ToxicFogEnabled' is missing or nil!")
    end

    local deathHours = LivingWorldFramework.GetConfig("TheFogDescend", "ToxicityDeathHours")
    if not deathHours or deathHours <= 0 then
        error("[TheFogDescend] LivingWorldFramework config 'ToxicityDeathHours' is missing, nil, or invalid!")
    end

    local isSafe = true
    if toxicFogEnabled and TheFogDescend.isEventActive then
        if player.isGodMod and player:isGodMod() then
            isSafe = true
        else
            -- Check if player is outside of a building
            local square = player:getCurrentSquare()
            local isOutside = not square or square:isOutside()
            
            if isOutside then
                -- Check if wearing a valid gas mask
                local hasMask = false
                local wornItems = player:getWornItems()
                if wornItems then
                    for i = 0, wornItems:size() - 1 do
                        local wornItem = wornItems:get(i)
                        local item = wornItem:getItem()
                        if item and item:hasTag(ItemTag.GAS_MASK) and item:getCondition() > 0 then
                            hasMask = true
                            break
                        end
                    end
                end

                if not hasMask then
                    isSafe = false
                end
            end
        end
    end

    if isSafe then
        -- Reduce toxicity slowly (1h of exposure = 2h of safe)
        -- Recovery rate is half of buildup rate: buildup is 1/deathHours, recovery is 1/(deathHours * 2)
        modData.fogToxicity = math_max(0.0, currentToxicity - dt / (deathHours * 2))
    else
        -- Increase toxicity
        modData.fogToxicity = math_min(1.0, currentToxicity + dt / deathHours)
    end

    -- Apply toxicity effects
    local stats = player:getStats()
    if stats then
        if modData.fogToxicity > 0 then
            -- Set poison level to trigger Sickness/Fever moodle (0 to 100 in PZ)
            local currentPoison = stats:get(CharacterStat.POISON) or 0.0
            stats:set(CharacterStat.POISON, math_max(currentPoison, modData.fogToxicity * 45))

            -- Increase fatigue faster/set minimum fatigue based on toxicity
            local currentFatigue = stats:get(CharacterStat.FATIGUE) or 0.0
            stats:set(CharacterStat.FATIGUE, math_max(currentFatigue, modData.fogToxicity * 0.9))

            -- Decrease endurance
            local currentEndurance = stats:get(CharacterStat.ENDURANCE) or 0.0
            stats:set(CharacterStat.ENDURANCE, math_min(currentEndurance, 1.0 - (modData.fogToxicity * 0.8)))

            -- Increase pain
            local currentPain = stats:get(CharacterStat.PAIN) or 0.0
            stats:set(CharacterStat.PAIN, math_max(currentPain, modData.fogToxicity * 80))

            -- Direct health reduction for precise death timing
            local bodyDamage = player:getBodyDamage()
            if bodyDamage then
                if modData.fogToxicity >= 1.0 then
                    bodyDamage:ReduceGeneralHealth(100.0) -- Instant death
                elseif modData.fogToxicity > 0.1 then
                    -- Scale health damage. At 0.1 toxicity, no damage. Scale linearly up to 1.0.
                    -- To lose 100 health over the remaining 90% of deathHours, the average damage rate is:
                    -- 100 / (deathHours * 0.9) per hour.
                    -- We scale this linearly with toxicity.
                    local scale = (modData.fogToxicity - 0.1) / 0.9
                    local baseDamageRate = 100.0 / (deathHours * 0.9)
                    local healthDamage = dt * baseDamageRate * scale * 2 -- Multiplier of 2 ensures it curves and averages correctly
                    bodyDamage:ReduceGeneralHealth(healthDamage)
                end
            end

            -- Coughing effect (2% chance per minute if exposed and toxicity > 0.05)
            if not isSafe and modData.fogToxicity > 0.05 then
                -- OnPlayerUpdate runs up to 60 times/sec. The probability per call is dt * 60 (1 in-game minute = 1/60 hours)
                -- 2% chance per minute = 0.02 * dt * 60 = dt * 1.2
                if ZombRandFloat(0.0, 1.0) < (dt * 1.2) then
                    player:Say("*Cough* *Wheeze*")
                    local x = player:getX()
                    local y = player:getY()
                    local z = player:getZ()
                    if addSound then
                        addSound(player, x, y, z, 15, 15)
                    end
                end
            end
        else
            -- Clear poison level if toxicity is completely gone
            if stats:get(CharacterStat.POISON) > 0 then
                stats:set(CharacterStat.POISON, 0)
            end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnGameStart.Add(onGameStart)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
