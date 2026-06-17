if isClient() and not isServer() then return end -- Only load on server or singleplayer host

LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}

-- Helper to announce event message in character voice (using Say)
function LivingWorldFramework.AnnounceEvent(text)
    local g = _G or getfenv()
    local isSer = g.isServer and g.isServer()
    if isSer then
        local players = g.getOnlinePlayers and g.getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                if p then p:Say(text) end
            end
        end
    else
        local p = g.getPlayer and g.getPlayer(0)
        if p then p:Say(text) end
    end
end

-- Helper to roll active event duration
function LivingWorldFramework.RollEventDuration(eventDef, state)
    local minDur = LivingWorldFramework.GetConfig(eventDef.id, "MinDuration")
    local maxDur = LivingWorldFramework.GetConfig(eventDef.id, "MaxDuration")
    if not minDur or not maxDur then
        error("[LivingWorldFramework] RollEventDuration failed: MinDuration or MaxDuration configuration is nil!")
    end
    if minDur > maxDur then minDur, maxDur = maxDur, minDur end
    state.activeDuration = LivingWorldFramework.Random(minDur, maxDur)
    print(string.format("[LivingWorldFramework] Event '%s' rolled active duration: %d hours", eventDef.id, state.activeDuration))
end

-- Helper to predetermine and schedule the next start day, hour, and duration for an event
function LivingWorldFramework.ScheduleNextEvent(eventDef, state, currentDay, isFirstTime)
    local minDays, maxDays
    if isFirstTime then
        minDays = LivingWorldFramework.GetConfig(eventDef.id, "MinTimeUntilFirstTrigger")
        maxDays = LivingWorldFramework.GetConfig(eventDef.id, "MaxTimeUntilFirstTrigger")
    else
        minDays = LivingWorldFramework.GetConfig(eventDef.id, "MinCooldown")
        maxDays = LivingWorldFramework.GetConfig(eventDef.id, "MaxCooldown")
    end
    if not minDays or not maxDays then
        error("[LivingWorldFramework] ScheduleNextEvent failed: trigger/cooldown configuration is nil!")
    end
    if minDays > maxDays then minDays, maxDays = maxDays, minDays end
    local delay = LivingWorldFramework.Random(minDays, maxDays)

    -- Simulate forward daily trigger chance rolls to find the scheduled start day
    local chance = LivingWorldFramework.GetConfig(eventDef.id, "TriggerChance")
    if not chance then
        error("[LivingWorldFramework] ScheduleNextEvent failed: TriggerChance configuration is nil!")
    end
    local extraDays = 0
    if chance < 1.0 and chance > 0 then
        while true do
            if LivingWorldFramework.RandomFloat() <= chance then
                break
            else
                extraDays = extraDays + 1
            end
        end
    end

    state.scheduledStartDay = currentDay + delay + extraDays

    -- Roll start hour based on time of day restrictions
    local onlyNight = LivingWorldFramework.GetConfig(eventDef.id, "OnlyNight")
    local onlyDay = LivingWorldFramework.GetConfig(eventDef.id, "OnlyDay")
    local startHour = 12
    if onlyNight then
        startHour = 20
    elseif onlyDay then
        startHour = 8
    else
        startHour = LivingWorldFramework.Random(8, 22)
    end
    state.scheduledStartHour = startHour
    state.scheduledStartTotalHours = state.scheduledStartDay * 24 + state.scheduledStartHour

    -- Roll the active duration for the next run
    local minDur = LivingWorldFramework.GetConfig(eventDef.id, "MinDuration")
    local maxDur = LivingWorldFramework.GetConfig(eventDef.id, "MaxDuration")
    if not minDur or not maxDur then
        error("[LivingWorldFramework] ScheduleNextEvent failed: MinDuration or MaxDuration configuration is nil!")
    end
    if minDur > maxDur then minDur, maxDur = maxDur, minDur end
    state.activeDuration = LivingWorldFramework.Random(minDur, maxDur)

    -- Reset dynamic runtime flags
    state.rollSucceeded = true

    print(string.format("[LivingWorldFramework] Scheduled %s run for '%s': Day %d at %d:00 (Total hours: %d, Duration: %d hours)",
        isFirstTime and "first" or "next", eventDef.id, state.scheduledStartDay, state.scheduledStartHour, state.scheduledStartTotalHours, state.activeDuration))
end

-- Default automated trigger condition check
function LivingWorldFramework.DefaultCanTrigger(eventDef, gameTime, state)
    local nightsSurvived = gameTime:getNightsSurvived()
    local debugEnabled = LivingWorldFramework.GetConfig("LivingWorldFramework", "EnableDebug")

    -- Check if we survived enough days overall since start of world
    local minNightsRequired = LivingWorldFramework.GetConfig(eventDef.id, "MinNightsSurvived")
    if not minNightsRequired then
        error("[LivingWorldFramework] DefaultCanTrigger failed: MinNightsSurvived configuration is nil!")
    end
    if nightsSurvived < minNightsRequired then
        if debugEnabled then
            print(string.format("[LivingWorldFramework] Event '%s' trigger check failed: nights survived (%d) < min required (%d)",
                eventDef.id, nightsSurvived, minNightsRequired))
        end
        return false
    end

    -- Weather restrictions
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

    -- Time of day restrictions
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

    return true
end

-- Initialize persistent ModData
local function initModData()
    local modData = ModData.getOrCreate("LivingWorldFramework")
    modData.activeEventId = modData.activeEventId or nil
    modData.coexistingEvents = modData.coexistingEvents or {}
    modData.eventStates = modData.eventStates or {}
    modData.globalHours = modData.globalHours or 0
    modData.serverConfigs = modData.serverConfigs or {}
    LivingWorldFramework.ServerConfigs = modData.serverConfigs
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
    state.hasTriggeredOnce = true

    -- Roll/resolve duration for this run
    local duration = state.activeDuration
    if eventDef.getDuration then
        local success, val = pcall(eventDef.getDuration)
        if success then duration = val end
    end
    state.activeDuration = duration or 24

    local gameTime = getGameTime()
    local currentTotalHours = gameTime:getNightsSurvived() * 24 + gameTime:getHour()
    state.actualEndTotalHours = currentTotalHours + state.activeDuration

    if eventDef.onStart then
        local success, err = pcall(eventDef.onStart, state)
        if not success then
            print("[LivingWorldFramework] ERROR running onStart for event '" .. eventId .. "': " .. tostring(err))
        end
    end

    -- Framework-managed character voice reaction on start
    local showVoice = LivingWorldFramework.GetConfig(eventId, "ShowCharacterVoice")
    if showVoice and eventDef.characterVoiceStart then
        LivingWorldFramework.AnnounceEvent(eventDef.characterVoiceStart)
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

    -- Framework-managed character voice reaction on stop
    if eventDef then
        local showVoice = LivingWorldFramework.GetConfig(eventId, "ShowCharacterVoice")
        if showVoice and eventDef.characterVoiceStop then
            LivingWorldFramework.AnnounceEvent(eventDef.characterVoiceStop)
        end
    end

    if eventDef and state then
        state.scheduledStartHour = nil
        state.scheduledStartDay = nil
        state.scheduledStartTotalHours = nil
        state.actualEndTotalHours = nil
        local nightsSurvived = getGameTime():getNightsSurvived()
        LivingWorldFramework.ScheduleNextEvent(eventDef, state, nightsSurvived, false)
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

        local gameTime = getGameTime()
        local currentTotalHours = gameTime:getNightsSurvived() * 24 + gameTime:getHour()

        -- Defensively restore/initialize target end time if missing
        if not state.actualEndTotalHours then
            state.actualEndTotalHours = currentTotalHours + (state.activeDuration or 24)
        end

        if currentTotalHours >= state.actualEndTotalHours then
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

    local gameTime = getGameTime()
    local currentDay = gameTime:getNightsSurvived()
    local currentHour = gameTime:getHour()
    local currentTotalHours = currentDay * 24 + currentHour

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
    local exclusiveTriggered = false
    for id, eventDef in pairs(LivingWorldFramework.events) do
        -- Skip check if event is already running
        local isRunning = (modData.activeEventId == id) or modData.coexistingEvents[id]
        
        if not isRunning then
            local skipExclusive = exclusiveTriggered and (eventDef.exclusivity == "Exclusive")
            if not skipExclusive then
                modData.eventStates[id] = modData.eventStates[id] or {}
                local state = modData.eventStates[id]
                
                -- Check if scheduled start time is reached
                if state.scheduledStartTotalHours and currentTotalHours >= state.scheduledStartTotalHours then
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
    end

    -- 4. Apply frame-end zombie refresh if any events requested it
    LivingWorldFramework.CheckAndExecuteZombieRefresh()
end

-- Handles incoming client commands for debugging triggers
local function onClientCommand(module, command, player, args)
    if module ~= "LivingWorldFramework" then return end
    
    print("[LivingWorldFramework] Received client command: " .. tostring(command) .. " from " .. tostring(player:getUsername()))

    local modData = initModData()
    local isSinglePlayer = not isServer() or (isServer() and not isClient() and (not getOnlinePlayers() or getOnlinePlayers():size() <= 1))
    local access = player:getAccessLevel()

    if command == "debugTrigger" then
        if isSinglePlayer or access == "Admin" then
            LivingWorldFramework.ServerTriggerEvent(args.eventId)
        else
            print("[LivingWorldFramework] Refused debugTrigger command from non-admin: " .. player:getUsername())
        end
    elseif command == "debugStop" then
        if isSinglePlayer or access == "Admin" then
            LivingWorldFramework.ServerStopEvent(args.eventId or modData.activeEventId)
        else
            print("[LivingWorldFramework] Refused debugStop command from non-admin: " .. player:getUsername())
        end
    elseif command == "syncConfig" then
        -- Only allow full Admin in multiplayer to overwrite/sync configs
        if isSinglePlayer or access == "Admin" then
            -- Re-evaluate and reschedule non-running events if their scheduling configurations have actually changed
            local gameTime = getGameTime()
            local currentDay = gameTime:getNightsSurvived()
            local schedulingKeys = {
                "MinTimeUntilFirstTrigger",
                "MaxTimeUntilFirstTrigger",
                "MinCooldown",
                "MaxCooldown",
                "TriggerChance"
            }

            local eventsToReschedule = {}
            for id, eventDef in pairs(LivingWorldFramework.events) do
                local isRunning = (modData.activeEventId == id) or modData.coexistingEvents[id]
                if not isRunning then
                    local eventConfigs = args.configs[id]
                    if eventConfigs then
                        for _, key in ipairs(schedulingKeys) do
                            if eventConfigs[key] ~= nil then
                                local currentVal = LivingWorldFramework.GetConfig(id, key)
                                if eventConfigs[key] ~= currentVal then
                                    eventsToReschedule[id] = true
                                    break
                                end
                            end
                        end
                    end
                end
            end

            modData.serverConfigs = args.configs
            LivingWorldFramework.ServerConfigs = modData.serverConfigs
            print("[LivingWorldFramework] Server synced and saved mod configurations from Admin client: " .. player:getUsername())

            for id, _ in pairs(eventsToReschedule) do
                local eventDef = LivingWorldFramework.events[id]
                local state = modData.eventStates[id] or {}
                modData.eventStates[id] = state
                local isFirstTime = not state.hasTriggeredOnce
                LivingWorldFramework.ScheduleNextEvent(eventDef, state, currentDay, isFirstTime)
            end
        else
            print("[LivingWorldFramework] Ignored config sync from non-admin client: " .. player:getUsername() .. " (Access: " .. tostring(access) .. ")")
        end
    end
end

-- Restores active events on load
local function onGameStart()
    local modData = initModData()
    local gameTime = getGameTime()
    local currentDay = gameTime:getNightsSurvived()
    local currentTotalHours = currentDay * 24 + gameTime:getHour()
    
    -- Initialize scheduling variables for all events
    for id, eventDef in pairs(LivingWorldFramework.events) do
        modData.eventStates[id] = modData.eventStates[id] or {}
        local state = modData.eventStates[id]
        if state.scheduledStartTotalHours == nil then
            LivingWorldFramework.ScheduleNextEvent(eventDef, state, currentDay, true)
        end
    end
    
    -- Restore primary exclusive event
    if modData.activeEventId then
        local activeId = modData.activeEventId
        print("[LivingWorldFramework] Active exclusive event '" .. activeId .. "' restored.")
        local eventDef = LivingWorldFramework.events[activeId]
        local state = modData.eventStates[activeId]
        if state then
            if not state.actualEndTotalHours then
                state.actualEndTotalHours = currentTotalHours + (state.activeDuration or 24)
            end
        end
        if eventDef and eventDef.onStart then
            pcall(eventDef.onStart, state)
        end
    end

    -- Restore coexisting events
    for activeId, _ in pairs(modData.coexistingEvents) do
        print("[LivingWorldFramework] Active coexisting event '" .. activeId .. "' restored.")
        local eventDef = LivingWorldFramework.events[activeId]
        local state = modData.eventStates[activeId]
        if state then
            if not state.actualEndTotalHours then
                state.actualEndTotalHours = currentTotalHours + (state.activeDuration or 24)
            end
        end
        if eventDef and eventDef.onStart then
            pcall(eventDef.onStart, state)
        end
    end

    LivingWorldFramework.CheckAndExecuteZombieRefresh()
end

-- Injects event warnings into the automated emergency broadcast forecast
function LivingWorldFramework.InjectRadioWarnings(bc, gameTime)
    local modData = initModData()
    if not modData or not modData.eventStates then return end

    local currentDay = gameTime:getNightsSurvived()
    local currentHour = gameTime:getHour()
    local currentTotalHours = currentDay * 24 + currentHour

    for id, eventDef in pairs(LivingWorldFramework.events) do
        local state = modData.eventStates[id]
        if state and eventDef.radioWarning then
            local showWarnings = LivingWorldFramework.GetConfig(id, "ShowRadioWarnings")
            if showWarnings then
                local lead = eventDef.radioWarning.leadHours or 4
                
                local readyToWarn = false
                if state.scheduledStartTotalHours then
                    local hoursRemaining = state.scheduledStartTotalHours - currentTotalHours
                    if hoursRemaining > 0 and hoursRemaining <= lead then
                        readyToWarn = true
                    end
                end

                if readyToWarn then
                    local msg = eventDef.radioWarning.message
                    if type(msg) == "function" then
                        local success, res = pcall(msg, state)
                        if success then msg = res else msg = nil end
                    end

                    if msg then
                        local color = eventDef.radioWarning.color or { r = 1.0, g = 1.0, b = 1.0 }
                        -- Add dynamic warning line to the radio broadcast
                        local comp = function(str) return str end -- mimics computerize formatting
                        bc:AddRadioLine(RadioLine.new(comp(msg), color.r, color.g, color.b))
                        print(string.format("[LivingWorldFramework] Injected radio warning for event '%s': %s", id, msg))
                    end
                end
            end
        end
    end
end

-- Hook the vanilla Automated Emergency Broadcast System (AEBS) Lua forecaster
local function hookWeatherChannel()
    if not WeatherChannel or not WeatherChannel.CreateBroadcast then
        print("[LivingWorldFramework] WeatherChannel or CreateBroadcast not found. Radio hook skipped.")
        return
    end

    local originalCreateBroadcast = WeatherChannel.CreateBroadcast
    WeatherChannel.CreateBroadcast = function(gameTime)
        -- Call vanilla broadcast generator
        local bc = originalCreateBroadcast(gameTime)
        if bc then
            -- Inject our framework warnings
            LivingWorldFramework.InjectRadioWarnings(bc, gameTime)
        end
        return bc
    end
    print("[LivingWorldFramework] Hooked WeatherChannel AEBS broadcast successfully.")
end

-- Initialize events
Events.OnInitWorld.Add(initModData)
Events.OnGameStart.Add(onGameStart)
Events.EveryHours.Add(everyHours)
Events.OnClientCommand.Add(onClientCommand)
Events.OnLoadRadioScripts.Add(hookWeatherChannel)
