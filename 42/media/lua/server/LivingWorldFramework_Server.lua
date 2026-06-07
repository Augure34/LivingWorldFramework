if isClient() and not isServer() then return end -- Only load on server or singleplayer host

LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}

-- Helper to roll active event duration
function LivingWorldFramework.RollEventDuration(eventDef, state)
    local minDur = LivingWorldFramework.GetConfig(eventDef.id, "MinDuration") or 1
    local maxDur = LivingWorldFramework.GetConfig(eventDef.id, "MaxDuration") or 24
    if minDur > maxDur then minDur, maxDur = maxDur, minDur end
    state.activeDuration = LivingWorldFramework.Random(minDur, maxDur)
    print(string.format("[LivingWorldFramework] Event '%s' rolled active duration: %d hours", eventDef.id, state.activeDuration))
end

-- Helper to roll next event cooldown day
function LivingWorldFramework.RollEventCooldown(eventDef, state, currentDay)
    local minCool = LivingWorldFramework.GetConfig(eventDef.id, "MinCooldown") or 1
    local maxCool = LivingWorldFramework.GetConfig(eventDef.id, "MaxCooldown") or 30
    if minCool > maxCool then minCool, maxCool = maxCool, minCool end
    local rolled = LivingWorldFramework.Random(minCool, maxCool)
    state.targetNextTriggerDay = currentDay + rolled
    print(string.format("[LivingWorldFramework] Event '%s' stopped. Cooldown rolled: %d days. Target next trigger day: %d",
        eventDef.id, rolled, state.targetNextTriggerDay))
end

-- Default automated trigger condition check
function LivingWorldFramework.DefaultCanTrigger(eventDef, gameTime, state)
    local nightsSurvived = gameTime:getNightsSurvived()
    local debugEnabled = LivingWorldFramework.GetConfig("LivingWorldFramework", "EnableDebug")

    -- 1. Initialize first trigger target day if not set
    if state.targetFirstTriggerDay == nil then
        local minDays = LivingWorldFramework.GetConfig(eventDef.id, "MinTimeUntilFirstTrigger") or 0
        local maxDays = LivingWorldFramework.GetConfig(eventDef.id, "MaxTimeUntilFirstTrigger") or 0
        if minDays > maxDays then minDays, maxDays = maxDays, minDays end
        state.targetFirstTriggerDay = nightsSurvived + LivingWorldFramework.Random(minDays, maxDays)
        print(string.format("[LivingWorldFramework] Event '%s' rolled first trigger target day: %d (current day: %d)",
            eventDef.id, state.targetFirstTriggerDay, nightsSurvived))
    end

    -- Check if we survived enough days overall since start of world
    local minNightsRequired = LivingWorldFramework.GetConfig(eventDef.id, "MinNightsSurvived") or 0
    if nightsSurvived < minNightsRequired then
        if debugEnabled then
            print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: nights survived (%d) < min required (%d)",
                eventDef.id, nightsSurvived, minNightsRequired))
        end
        return false
    end

    -- Check if we are past the first trigger day
    if nightsSurvived < state.targetFirstTriggerDay then
        if debugEnabled then
            print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: nights survived (%d) < first trigger day (%d)",
                eventDef.id, nightsSurvived, state.targetFirstTriggerDay))
        end
        return false
    end

    -- Check if we are past the cooldown day
    if nightsSurvived < (state.targetNextTriggerDay or 0) then
        if debugEnabled then
            print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: nights survived (%d) < cooldown target day (%d)",
                eventDef.id, nightsSurvived, state.targetNextTriggerDay or 0))
        end
        return false
    end

    -- 2. Daily probability roll (rolled once per day when eligible)
    local chance = LivingWorldFramework.GetConfig(eventDef.id, "TriggerChance") or 1.0
    if chance < 1.0 then
        if state.lastRollDay ~= nightsSurvived then
            state.lastRollDay = nightsSurvived
            local rand = LivingWorldFramework.RandomFloat()
            if rand <= chance then
                state.rollSucceeded = true
                print(string.format("[LivingWorldFramework] Event '%s' daily trigger chance roll succeeded (roll: %.3f <= chance: %.3f)",
                    eventDef.id, rand, chance))
            else
                state.rollSucceeded = false
                state.targetNextTriggerDay = nightsSurvived + 1
                print(string.format("[LivingWorldFramework] Event '%s' daily trigger chance roll failed (roll: %.3f > chance: %.3f). Postponing to day %d.",
                    eventDef.id, rand, chance, state.targetNextTriggerDay))
            end
        end
        if not state.rollSucceeded then
            if debugEnabled then
                print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: daily roll did not succeed on day %d",
                    eventDef.id, nightsSurvived))
            end
            return false
        end
    end

    -- 3. Weather restrictions
    local onlyRain = LivingWorldFramework.GetConfig(eventDef.id, "OnlyRain")
    local onlySnow = LivingWorldFramework.GetConfig(eventDef.id, "OnlySnow")
    local clim = getClimateManager()
    if clim then
        if onlyRain and not clim:isRaining() then
            if debugEnabled then
                print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: only triggers in rain", eventDef.id))
            end
            return false
        end
        if onlySnow and not clim:isSnowing() then
            if debugEnabled then
                print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: only triggers in snow", eventDef.id))
            end
            return false
        end
    end

    -- 4. Time of day restrictions
    local onlyNight = LivingWorldFramework.GetConfig(eventDef.id, "OnlyNight")
    local onlyDay = LivingWorldFramework.GetConfig(eventDef.id, "OnlyDay")
    if onlyNight or onlyDay then
        local hour = gameTime:getHour()
        local isNight = (hour < 6 or hour >= 20)
        if onlyNight and not isNight then
            if debugEnabled then
                print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: night only, current hour is %d",
                    eventDef.id, hour))
            end
            return false
        end
        if onlyDay and isNight then
            if debugEnabled then
                print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: day only, current hour is %d",
                    eventDef.id, hour))
            end
            return false
        end
    end

    if debugEnabled then
        print(string.format("[LivingWorldFramework] Event '%s' trigger check succeeded on day %d", eventDef.id, nightsSurvived))
    end
    return true
end

-- Initialize persistent ModData
local function initModData()
    local modData = ModData.getOrCreate("LivingWorldFramework")
    modData.activeEventId = modData.activeEventId or nil
    modData.coexistingEvents = modData.coexistingEvents or {}
    modData.eventStates = modData.eventStates or {}
    modData.globalHours = modData.globalHours or 0
    return modData
end

-- Centralized Zombie refresh runner
function LivingWorldFramework.CheckAndExecuteZombieRefresh()
    if not LivingWorldFramework.zombieRefreshRequested then return end

    print("[LivingWorldFramework] Performing centralized cell zombie refresh...")
    local cell = getCell()
    if cell then
        local zList = cell:getZombieList()
        if zList then
            local speed = SandboxVars.ZombieLore.Speed
            for i = 0, zList:size() - 1 do
                local z = zList:get(i)
                if z then
                    local zModData = z:getModData()
                    local originalSpeed = zModData and zModData.lwfOriginalSpeed

                    if speed == 1 then
                        -- Save original speed type before applying sprinter speed
                        if zModData and originalSpeed == nil and z.getSpeedType then
                            zModData.lwfOriginalSpeed = z:getSpeedType()
                        end
                        if z.doSprinter then z:doSprinter() end
                    else
                        -- We are restoring vanilla settings (event stopped)
                        if originalSpeed then
                            if originalSpeed == 1 then
                                if z.doSprinter then z:doSprinter() end
                            elseif originalSpeed == 2 then
                                if z.doFastShambler then z:doFastShambler() end
                            elseif originalSpeed == 3 then
                                if z.doShambler then z:doShambler() end
                            elseif originalSpeed == 4 then
                                if z.doFakeShambler then z:doFakeShambler() end
                            end
                            if zModData then zModData.lwfOriginalSpeed = nil end
                        else
                            -- Fallback: if no saved speed, use global Sandbox setting
                            if speed == 2 then
                                if z.doFastShambler then z:doFastShambler() end
                            elseif speed == 3 then
                                if z.doShambler then z:doShambler() end
                            end
                        end
                    end
                    z:DoZombieStats()
                end
            end
        end
    end
    LivingWorldFramework.zombieRefreshRequested = false
end

-- Triggers an event on the server
function LivingWorldFramework.ServerTriggerEvent(eventId)
    local eventDef = LivingWorldFramework.events[eventId]
    if not eventDef then
        print("[LivingWorldFramework] Cannot trigger event: '" .. tostring(eventId) .. "' is not registered.")
        return false
    end

    local modData = initModData()
    
    if eventDef.exclusivity == "Exclusive" then
        if modData.activeEventId then
            local currentActive = LivingWorldFramework.events[modData.activeEventId]
            if currentActive then
                -- Preempt current active event if new event has strictly higher priority
                if eventDef.priority > currentActive.priority then
                    print(string.format("[LivingWorldFramework] Preempting event '%s' (Priority: %d) with higher-priority event '%s' (Priority: %d)", 
                        currentActive.id, currentActive.priority, eventDef.id, eventDef.priority))
                    LivingWorldFramework.ServerStopEvent(currentActive.id)
                else
                    print(string.format("[LivingWorldFramework] Rejecting event '%s' (Priority: %d): Exclusive event '%s' (Priority: %d) is already active",
                        eventDef.id, eventDef.priority, currentActive.id, currentActive.priority))
                    return false
                end
            else
                modData.activeEventId = nil
            end
        end
        modData.activeEventId = eventId
    else
        modData.coexistingEvents[eventId] = true
    end

    print("[LivingWorldFramework] Server triggering event: '" .. tostring(eventId) .. "'")
    modData.eventStates[eventId] = modData.eventStates[eventId] or {}
    
    local state = modData.eventStates[eventId]
    state.elapsedHours = 0
    LivingWorldFramework.RollEventDuration(eventDef, state)

    if eventDef.onStart then
        local success, err = pcall(eventDef.onStart, state)
        if not success then
            print("[LivingWorldFramework] ERROR running onStart for event '" .. eventId .. "': " .. tostring(err))
        end
    end

    LivingWorldFramework.CheckAndExecuteZombieRefresh()
    return true
end

-- Stops a specific active event (exclusive or coexisting)
function LivingWorldFramework.ServerStopEvent(eventId)
    local modData = initModData()
    local isActive = false

    if modData.activeEventId == eventId then
        modData.activeEventId = nil
        isActive = true
    elseif modData.coexistingEvents[eventId] then
        modData.coexistingEvents[eventId] = nil
        isActive = true
    end

    if not isActive then return end

    print("[LivingWorldFramework] Server stopping event: '" .. tostring(eventId) .. "'")
    local eventDef = LivingWorldFramework.events[eventId]
    local state = modData.eventStates[eventId]

    if eventDef and eventDef.onStop then
        local success, err = pcall(eventDef.onStop, state)
        if not success then
            print("[LivingWorldFramework] ERROR running onStop for event '" .. eventId .. "': " .. tostring(err))
        end
    end

    if eventDef and state then
        local nightsSurvived = getGameTime():getNightsSurvived()
        LivingWorldFramework.RollEventCooldown(eventDef, state, nightsSurvived)
    end

    LivingWorldFramework.CheckAndExecuteZombieRefresh()
end

-- Stops the primary exclusive active event
function LivingWorldFramework.ServerStopActiveEvent()
    local modData = initModData()
    if modData.activeEventId then
        LivingWorldFramework.ServerStopEvent(modData.activeEventId)
    else
        print("[LivingWorldFramework] No active exclusive event to stop.")
    end
end

-- Helper to update an active event and check duration
local function updateActiveEvent(eventId)
    local eventDef = LivingWorldFramework.events[eventId]
    local modData = initModData()
    local state = modData.eventStates[eventId]
    
    if eventDef then
        state.elapsedHours = (state.elapsedHours or 0) + 1
        
        if eventDef.onUpdate then
            local success, err = pcall(eventDef.onUpdate, state, 1)
            if not success then
                print("[LivingWorldFramework] ERROR running onUpdate for event '" .. eventId .. "': " .. tostring(err))
            end
        end

        local duration = nil
        if eventDef.getDuration then
            local success, val = pcall(eventDef.getDuration)
            if success then duration = val end
        end
        if not duration then
            duration = state.activeDuration or state.duration
        end

        if duration and state.elapsedHours >= duration then
            print("[LivingWorldFramework] Event '" .. eventId .. "' completed duration.")
            LivingWorldFramework.ServerStopEvent(eventId)
        end
    else
        print("[LivingWorldFramework] Active event '" .. eventId .. "' has no definition. Clearing.")
        LivingWorldFramework.ServerStopEvent(eventId)
    end
end

-- Periodic update check (Runs hourly in-game)
local function everyHours()
    local modData = initModData()
    modData.globalHours = (modData.globalHours or 0) + 1

    -- 1. Tick primary active exclusive event
    if modData.activeEventId then
        updateActiveEvent(modData.activeEventId)
    end

    -- 2. Tick coexisting events
    -- (Need to collect keys first since we can modify coexistingEvents during loop)
    local activeCoexist = {}
    for eventId, _ in pairs(modData.coexistingEvents) do
        table.insert(activeCoexist, eventId)
    end
    for _, eventId in ipairs(activeCoexist) do
        updateActiveEvent(eventId)
    end

    -- 3. Check and trigger new scheduled events (if space is available)
    local gameTime = getGameTime()
    local exclusiveTriggered = false
    for id, eventDef in pairs(LivingWorldFramework.events) do
        -- Skip check if event is already running
        local isRunning = (modData.activeEventId == id) or modData.coexistingEvents[id]
        
        if not isRunning then
            local skipExclusive = exclusiveTriggered and (eventDef.exclusivity == "Exclusive")
            if skipExclusive then
                if LivingWorldFramework.GetConfig("LivingWorldFramework", "EnableDebug") then
                    print(string.format("[LivingWorldFramework] Event '%s' trigger check skipped: exclusive event already triggered this hour", id))
                end
            else
                modData.eventStates[id] = modData.eventStates[id] or {}
                local state = modData.eventStates[id]
                
                local canTrigger = false
                if eventDef.canTrigger then
                    local success, res = pcall(eventDef.canTrigger, gameTime, state)
                    if success then
                        canTrigger = res
                    else
                        print("[LivingWorldFramework] ERROR running canTrigger for event '" .. id .. "': " .. tostring(res))
                    end
                else
                    canTrigger = LivingWorldFramework.DefaultCanTrigger(eventDef, gameTime, state)
                end

                if canTrigger then
                    -- Attempt trigger. If exclusive, it can fail if another exclusive event has higher priority.
                    local success = LivingWorldFramework.ServerTriggerEvent(id)
                    if success and eventDef.exclusivity == "Exclusive" then
                        exclusiveTriggered = true
                    end
                end
            end
        end
    end

    -- 4. Apply frame-end zombie refresh if any events requested it
    LivingWorldFramework.CheckAndExecuteZombieRefresh()
end

-- Handles incoming client commands for debugging triggers
local function onClientCommand(module, command, player, args)
    if module ~= "LivingWorldFramework" then return end
    
    print("[LivingWorldFramework] Received client command: " .. tostring(command) .. " from " .. tostring(player:getUsername()))

    local modData = initModData()
    if command == "debugTrigger" then
        LivingWorldFramework.ServerTriggerEvent(args.eventId)
    elseif command == "debugStop" then
        LivingWorldFramework.ServerStopEvent(args.eventId or modData.activeEventId)
    elseif command == "syncConfig" then
        local isSinglePlayer = not isServer() or (isServer() and not isClient() and (not getOnlinePlayers() or getOnlinePlayers():size() <= 1))
        local access = player:getAccessLevel()
        if isSinglePlayer or (access ~= "None" and access ~= "") then
            LivingWorldFramework.ServerConfigs = args.configs
            print("[LivingWorldFramework] Server synced mod configurations from client.")
        else
            print("[LivingWorldFramework] Ignored config sync from non-admin client: " .. player:getUsername())
        end
    end
end

-- Restores active events on load
local function onGameStart()
    local modData = initModData()
    
    -- Initialize scheduling variables for all events
    local currentDay = getGameTime():getNightsSurvived()
    for id, eventDef in pairs(LivingWorldFramework.events) do
        modData.eventStates[id] = modData.eventStates[id] or {}
        local state = modData.eventStates[id]
        if state.targetFirstTriggerDay == nil then
            local minDays = LivingWorldFramework.GetConfig(id, "MinTimeUntilFirstTrigger") or 0
            local maxDays = LivingWorldFramework.GetConfig(id, "MaxTimeUntilFirstTrigger") or 0
            if minDays > maxDays then minDays, maxDays = maxDays, minDays end
            state.targetFirstTriggerDay = currentDay + LivingWorldFramework.Random(minDays, maxDays)
            print(string.format("[LivingWorldFramework] Event '%s' initialized first trigger day: %d (current: %d)",
                id, state.targetFirstTriggerDay, currentDay))
        end
    end
    
    -- Restore primary exclusive event
    if modData.activeEventId then
        local activeId = modData.activeEventId
        print("[LivingWorldFramework] Active exclusive event '" .. activeId .. "' restored.")
        local eventDef = LivingWorldFramework.events[activeId]
        local state = modData.eventStates[activeId]
        if eventDef and eventDef.onStart then
            pcall(eventDef.onStart, state)
        end
    end

    -- Restore coexisting events
    for activeId, _ in pairs(modData.coexistingEvents) do
        print("[LivingWorldFramework] Active coexisting event '" .. activeId .. "' restored.")
        local eventDef = LivingWorldFramework.events[activeId]
        local state = modData.eventStates[activeId]
        if eventDef and eventDef.onStart then
            pcall(eventDef.onStart, state)
        end
    end

    LivingWorldFramework.CheckAndExecuteZombieRefresh()
end

-- Initialize events
Events.OnInitWorld.Add(initModData)
Events.OnGameStart.Add(onGameStart)
Events.EveryHours.Add(everyHours)
Events.OnClientCommand.Add(onClientCommand)
