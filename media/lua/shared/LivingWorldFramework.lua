LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}
LivingWorldFramework.ServerConfigs = LivingWorldFramework.ServerConfigs or {}

-- Shared configuration options schema for the framework itself
LivingWorldFramework.configOptions = {
    { id = "EnableDebug", name = "Enable Debug Mode", type = "boolean", default = false, tooltip = "Enable detailed logging for events and overrides" }
}

-- Safe random number generators compatible with Project Zomboid (Kahlua VM does not support math.random)
function LivingWorldFramework.Random(min, max)
    local g = _G or getfenv()
    if g.ZombRand then
        if min > max then min, max = max, min end
        return g.ZombRand(min, max + 1)
    else
        return math.random(min, max)
    end
end

function LivingWorldFramework.RandomFloat()
    local g = _G or getfenv()
    if g.ZombRandFloat then
        return g.ZombRandFloat(0, 1)
    else
        return math.random()
    end
end


-- Centralized retrieval function for options
function LivingWorldFramework.GetConfig(eventId, optionId)
    -- 1. If we are running in an environment where PZAPI is available, read from native ModOptions
    local isCli = false
    if isClient then isCli = isClient() end
    local isSer = false
    if isServer then isSer = isServer() end
    local isSP = not isCli and not isSer
    local g = _G or getfenv()
    if (isCli or isSP) and g.PZAPI and g.PZAPI.ModOptions then
        local group = g.PZAPI.ModOptions:getOptions(eventId)
        if group then
            local opt = group:getOption(optionId)
            if opt then
                local val = opt:getValue()
                -- If it's an enum, translate index (number) to string value
                local schema = nil
                if eventId == "LivingWorldFramework" then
                    schema = LivingWorldFramework.configOptions
                else
                    local eventDef = LivingWorldFramework.events[eventId]
                    if eventDef then
                        schema = eventDef.configOptions
                    end
                end
                if schema then
                    for _, sOpt in ipairs(schema) do
                        if sOpt.id == optionId and sOpt.type == "enum" and type(val) == "number" and sOpt.options then
                            return sOpt.options[val] or val
                        end
                    end
                end
                return val
            end
        end
    end

    -- 2. Read from synced configs on the server (or singleplayer server context)
    if LivingWorldFramework.ServerConfigs[eventId] and LivingWorldFramework.ServerConfigs[eventId][optionId] ~= nil then
        return LivingWorldFramework.ServerConfigs[eventId][optionId]
    end

    -- 3. Fallback: retrieve default value from the registered options schema
    local schema = nil
    if eventId == "LivingWorldFramework" then
        schema = LivingWorldFramework.configOptions
    else
        local eventDef = LivingWorldFramework.events[eventId]
        if eventDef then
            schema = eventDef.configOptions
        end
    end

    if schema then
        for _, opt in ipairs(schema) do
            if opt.id == optionId then
                return opt.default
            end
        end
    end

    return nil
end


-- Internal State Caching
local originalSandboxVars = {}
local modifiers = {}
local climateOverrides = {}
LivingWorldFramework.zombieRefreshRequested = false

-- Helper to check if a table is empty without using next (which may be nil in some environments)
local function isTableEmpty(t)
    if not t then return true end
    for _ in pairs(t) do
        return false
    end
    return true
end

-- Helper to split strings by dots
local function splitPath(path)
    local parts = {}
    for part in string.gmatch(path, "[^.]+") do
        table.insert(parts, part)
    end
    return parts
end

-- Helper to get nested SandboxVars value
local function getSandboxVar(path)
    local parts = splitPath(path)
    local val = SandboxVars
    for _, part in ipairs(parts) do
        if val then
            val = val[part]
        else
            break
        end
    end
    return val
end

-- Helper to set nested SandboxVars value and sync to Java SandboxOptions
local function setSandboxVar(path, value)
    local parts = splitPath(path)
    local current = SandboxVars
    for i = 1, #parts - 1 do
        current = current[parts[i]]
        if not current then return end
    end
    current[parts[#parts]] = value

    -- Also sync to the Java SandboxOptions instance so the game engine sees it!
    local getSandboxOptions = _G.getSandboxOptions or getSandboxOptions
    if getSandboxOptions then
        local success, opts = pcall(getSandboxOptions)
        if success and opts then
            local option = opts:getOptionByName(path)
            if option then
                if option:getType() == "integer" or option:getType() == "double" then
                    option:parse(tostring(value))
                else
                    option:setValue(value)
                end
                print("[LivingWorldFramework] Synced " .. path .. " to Java SandboxOptions: " .. tostring(value))
            end
        end
    end

    -- In multiplayer, broadcast the updated SandboxVar to all clients
    local g = _G or getfenv()
    if g.isServer and g.isServer() and g.sendServerCommand then
        g.sendServerCommand("LivingWorldFramework", "syncSandboxVar", { path = path, value = value })
    end
end

-- Refreshes the resolved sandbox option state from the current stack
LivingWorldFramework.sandboxResolvers = LivingWorldFramework.sandboxResolvers or {}

function LivingWorldFramework.RegisterSandboxResolver(path, resolverFunc)
    LivingWorldFramework.sandboxResolvers[path] = resolverFunc
    print("[LivingWorldFramework] Registered sandbox resolver for: " .. path)
end

-- Refreshes the resolved sandbox option state from the current stack
-- Refreshes the resolved sandbox option state from the current stack
local sandboxOptionBounds = {
    ["ZombieLore.Speed"] = { min = 1, max = 4 },
    ["ZombieLore.Sight"] = { min = 1, max = 3 },
    ["ZombieLore.Hearing"] = { min = 1, max = 3 },
    ["ZombieLore.Cognition"] = { min = 1, max = 3 }
}

-- Refreshes the resolved sandbox option state from the current stack
local function applySandboxStack(path)
    local stack = modifiers[path]
    if not stack or #stack == 0 then
        -- Restore original cached value
        if originalSandboxVars[path] ~= nil then
            setSandboxVar(path, originalSandboxVars[path])
            print("[LivingWorldFramework] Restored " .. path .. " to vanilla value: " .. tostring(originalSandboxVars[path]))
        end
        return
    end

    local resolvedValue = nil
    local resolver = LivingWorldFramework.sandboxResolvers[path]
    if resolver then
        local success, val = pcall(resolver, stack, originalSandboxVars[path])
        if success then
            resolvedValue = val
        else
            print("[LivingWorldFramework] ERROR in sandbox resolver for " .. path .. ": " .. tostring(val))
        end
    end

    if resolvedValue == nil then
        -- Sort stack by priority descending (highest priority first)
        table.sort(stack, function(a, b)
            return a.priority > b.priority
        end)
        resolvedValue = stack[1].value
        print(string.format("[LivingWorldFramework] Applied highest priority modifier to %s: %s (Priority: %d, Event: %s)", 
            path, tostring(resolvedValue), stack[1].priority, stack[1].eventId))
    else
        print(string.format("[LivingWorldFramework] Applied resolved modifier to %s: %s", path, tostring(resolvedValue)))
    end

    -- Clamp value to valid game ranges to prevent values outside B42/B41 boundaries
    local bounds = sandboxOptionBounds[path]
    if bounds and type(resolvedValue) == "number" then
        local originalResolved = resolvedValue
        if resolvedValue < bounds.min then
            resolvedValue = bounds.min
        elseif resolvedValue > bounds.max then
            resolvedValue = bounds.max
        end
        if resolvedValue ~= originalResolved then
            print(string.format("[LivingWorldFramework] Clamped %s from %s to valid game bounds [%d, %d]", 
                path, tostring(originalResolved), bounds.min, bounds.max))
        end
    end

    setSandboxVar(path, resolvedValue)
end

-- Default sandbox resolvers
LivingWorldFramework.RegisterSandboxResolver("ZombieLore.Speed", function(stack, originalValue)
    local baseVal = originalValue or 2
    if baseVal < 1 then baseVal = 1 elseif baseVal > 4 then baseVal = 4 end

    if #stack == 1 then
        return stack[1].value
    end
    local sum = 0
    local count = 0
    for _, item in ipairs(stack) do
        if type(item.value) == "number" then
            local val = item.value
            if val < 1 then val = 1 elseif val > 4 then val = 4 end
            sum = sum + val
            count = count + 1
        end
    end
    if count > 0 then
        -- Average speeds and round to nearest integer
        return math.floor((sum / count) + 0.5)
    end
    return baseVal
end)

-- Climate float merge strategies
local climateMergeStrategies = {
    [4] = "min",  -- FLOAT_TEMPERATURE: lowest temperature wins (coldest)
    [9] = "min",  -- FLOAT_AMBIENT: lowest ambient light wins (darkest)
    [11] = "min", -- FLOAT_DAYLIGHT_STRENGTH: lowest daylight strength wins (darkest)
}

-- Refreshes ClimateManager float overrides
local function applyClimateOverrides(floatId)
    local overrides = climateOverrides[floatId]
    local clim = getClimateManager()
    if not clim then return end

    local climFloat = clim:getClimateFloat(floatId)
    if not climFloat then return end

    if not overrides or isTableEmpty(overrides) then
        -- No overrides active, release admin override control
        climFloat:setEnableAdmin(false)
        print("[LivingWorldFramework] Released ClimateFloat admin override for index " .. tostring(floatId))
        return
    end

    local strategy = climateMergeStrategies[floatId] or "max"
    
    -- Start with base calculated weather value as initial baseline
    local baseVal = climFloat.calculateVal
    if baseVal == nil then
        baseVal = 0.0
    end

    local resolvedVal = baseVal

    if floatId == 4 then -- FLOAT_TEMPERATURE
        -- For temperature, overrides are treated as negative offsets (temperature drops)
        local minOffset = 0.0
        for eventId, val in pairs(overrides) do
            if val < minOffset then
                minOffset = val
            end
        end
        resolvedVal = baseVal + minOffset
        climFloat:setEnableAdmin(true)
        climFloat:setAdminValue(resolvedVal)
        print(string.format("[LivingWorldFramework] Set ClimateFloat 4 (Temperature) with offset %s: %s (base: %s)", 
            tostring(minOffset), tostring(resolvedVal), tostring(baseVal)))
        return
    end

    for eventId, val in pairs(overrides) do
        if strategy == "min" then
            if val < resolvedVal then
                resolvedVal = val
            end
        else -- default "max"
            if val > resolvedVal then
                resolvedVal = val
            end
        end
    end

    if resolvedVal ~= nil then
        climFloat:setEnableAdmin(true)
        climFloat:setAdminValue(resolvedVal)
        print(string.format("[LivingWorldFramework] Set ClimateFloat %d override (%s): %s", floatId, strategy, tostring(resolvedVal)))
    end
end

-- Register a new world event with the framework.
function LivingWorldFramework.RegisterEvent(eventDef)
    if not eventDef or not eventDef.id then
        print("[LivingWorldFramework] ERROR: Cannot register event without an 'id' field.")
        return
    end
    -- Set default priority (0) if not specified
    eventDef.priority = eventDef.priority or 0
    eventDef.exclusivity = eventDef.exclusivity or "Exclusive"
    
    eventDef.configOptions = eventDef.configOptions or {}
    
    local function addOptionIfMissing(optionDef)
        for _, opt in ipairs(eventDef.configOptions) do
            if opt.id == optionDef.id then
                return
            end
        end
        table.insert(eventDef.configOptions, optionDef)
    end

    -- Check expose flags or define defaults
    local expFirstTrigger = not not eventDef.exposeTimeUntilFirstTrigger
    local expDuration = not not eventDef.exposeDuration
    local expCooldown = not not eventDef.exposeCooldown
    local expTriggerChance = not not eventDef.exposeTriggerChance
    local expWeather = not not eventDef.exposeWeather
    local expTimeOfDay = not not eventDef.exposeTimeOfDay
    local expMinNights = not not eventDef.exposeMinNightsSurvived

    -- Add options
    addOptionIfMissing({
        id = "MinTimeUntilFirstTrigger",
        name = "Min Time Until First Trigger (Days)",
        type = "integer",
        min = 0,
        max = 365,
        default = eventDef.defaultMinTimeUntilFirstTrigger or 0,
        tooltip = "Minimum number of days before the event can trigger for the first time.",
        hidden = not expFirstTrigger
    })
    addOptionIfMissing({
        id = "MaxTimeUntilFirstTrigger",
        name = "Max Time Until First Trigger (Days)",
        type = "integer",
        min = 0,
        max = 365,
        default = eventDef.defaultMaxTimeUntilFirstTrigger or 0,
        tooltip = "Maximum number of days before the event can trigger for the first time.",
        hidden = not expFirstTrigger
    })
    addOptionIfMissing({
        id = "MinDuration",
        name = "Min Duration (Hours)",
        type = "integer",
        min = 1,
        max = 168,
        default = eventDef.defaultMinDuration or 1,
        tooltip = "Minimum duration of the event in hours.",
        hidden = not expDuration
    })
    addOptionIfMissing({
        id = "MaxDuration",
        name = "Max Duration (Hours)",
        type = "integer",
        min = 1,
        max = 168,
        default = eventDef.defaultMaxDuration or 24,
        tooltip = "Maximum duration of the event in hours.",
        hidden = not expDuration
    })
    addOptionIfMissing({
        id = "MinCooldown",
        name = "Min Cooldown (Days)",
        type = "integer",
        min = 1,
        max = 100,
        default = eventDef.defaultMinCooldown or 1,
        tooltip = "Minimum days between occurrences.",
        hidden = not expCooldown
    })
    addOptionIfMissing({
        id = "MaxCooldown",
        name = "Max Cooldown (Days)",
        type = "integer",
        min = 1,
        max = 100,
        default = eventDef.defaultMaxCooldown or 30,
        tooltip = "Maximum days between occurrences.",
        hidden = not expCooldown
    })
    addOptionIfMissing({
        id = "TriggerChance",
        name = "Daily Trigger Probability",
        type = "double",
        min = 0.0,
        max = 1.0,
        step = 0.05,
        default = eventDef.defaultTriggerChance or 1.0,
        tooltip = "The probability checked once per day when the event is eligible to trigger (e.g. 0.20 = 20% chance per day). If the daily roll fails, the trigger check is postponed to tomorrow.",
        hidden = not expTriggerChance
    })
    addOptionIfMissing({
        id = "OnlyRain",
        name = "Only Trigger in Rain",
        type = "boolean",
        default = eventDef.defaultOnlyRain or false,
        tooltip = "If checked, the event only triggers when it is raining.",
        hidden = not expWeather
    })
    addOptionIfMissing({
        id = "OnlySnow",
        name = "Only Trigger in Snow",
        type = "boolean",
        default = eventDef.defaultOnlySnow or false,
        tooltip = "If checked, the event only triggers when it is snowing.",
        hidden = not expWeather
    })
    addOptionIfMissing({
        id = "OnlyNight",
        name = "Only Trigger at Night",
        type = "boolean",
        default = eventDef.defaultOnlyNight or false,
        tooltip = "If checked, the event only triggers during night hours (20:00 to 06:00).",
        hidden = not expTimeOfDay
    })
    addOptionIfMissing({
        id = "OnlyDay",
        name = "Only Trigger during Day",
        type = "boolean",
        default = eventDef.defaultOnlyDay or false,
        tooltip = "If checked, the event only triggers during daytime hours (06:00 to 20:00).",
        hidden = not expTimeOfDay
    })
    addOptionIfMissing({
        id = "MinNightsSurvived",
        name = "Min Days Survived Required",
        type = "integer",
        min = 0,
        max = 365,
        default = eventDef.defaultMinNightsSurvived or 0,
        tooltip = "Minimum number of days player must survive before event can trigger.",
        hidden = not expMinNights
    })

    if eventDef.radioWarning then
        addOptionIfMissing({
            id = "ShowRadioWarnings",
            name = "Enable Radio Warnings",
            type = "boolean",
            default = eventDef.defaultShowRadioWarnings ~= false,
            tooltip = "Whether warnings for this event are injected into the automated weather forecast channel."
        })
    end

    if eventDef.characterVoiceStart or eventDef.characterVoiceStop then
        addOptionIfMissing({
            id = "ShowCharacterVoice",
            name = "Enable Character Voice",
            type = "boolean",
            default = eventDef.defaultShowCharacterVoice == true,
            tooltip = "Whether the player character reacts out loud in chat when the event starts and ends."
        })
    end

    LivingWorldFramework.events[eventDef.id] = eventDef
    print(string.format("[LivingWorldFramework] Registered event: %s (Priority: %d, Exclusivity: %s)", 
        eventDef.id, eventDef.priority, eventDef.exclusivity))
end

-- Registers/Pushes a sandbox variable override onto the stack
function LivingWorldFramework.PushModifier(eventId, path, value, priority)
    priority = priority or 0
    
    -- Cache original sandbox value if not already cached
    if originalSandboxVars[path] == nil then
        local currentVal = getSandboxVar(path)
        originalSandboxVars[path] = currentVal
        print(string.format("[LivingWorldFramework] Cached vanilla value for %s: %s", path, tostring(currentVal)))
    end

    -- Remove any pre-existing entry for this eventId to prevent duplicates
    LivingWorldFramework.PopModifier(eventId, path, true) -- silences prints during update

    modifiers[path] = modifiers[path] or {}
    table.insert(modifiers[path], {
        eventId = eventId,
        value = value,
        priority = priority
    })

    applySandboxStack(path)
end

-- Removes/Pops a sandbox override modifier from the stack
function LivingWorldFramework.PopModifier(eventId, path, silent)
    local stack = modifiers[path]
    if not stack then return end

    for i = #stack, 1, -1 do
        if stack[i].eventId == eventId then
            table.remove(stack, i)
        end
    end

    if #stack == 0 then
        modifiers[path] = nil
    end

    if not silent then
        applySandboxStack(path)
    end
end

-- Registers a climate float override
function LivingWorldFramework.SetClimateOverride(eventId, floatId, value)
    climateOverrides[floatId] = climateOverrides[floatId] or {}
    climateOverrides[floatId][eventId] = value
    applyClimateOverrides(floatId)
end

-- Removes a climate override
function LivingWorldFramework.ClearClimateOverride(eventId, floatId)
    if climateOverrides[floatId] then
        climateOverrides[floatId][eventId] = nil
        if isTableEmpty(climateOverrides[floatId]) then
            climateOverrides[floatId] = nil
        end
    end
    applyClimateOverrides(floatId)
end

-- Queues a loaded cell zombie stats refresh at the end of the update tick
function LivingWorldFramework.RequestZombieRefresh()
    LivingWorldFramework.zombieRefreshRequested = true
end

-- Triggers an event on the server/singleplayer console
function LivingWorldFramework.DebugTriggerEvent(eventId)
    if not eventId then
        print("[LivingWorldFramework] DebugTriggerEvent: Missing eventId argument.")
        return
    end
    
    if isClient() then
        sendClientCommand("LivingWorldFramework", "debugTrigger", { eventId = eventId })
        print("[LivingWorldFramework] Sent debug trigger command for: " .. tostring(eventId))
    else
        if LivingWorldFramework.ServerTriggerEvent then
            LivingWorldFramework.ServerTriggerEvent(eventId)
        else
            print("[LivingWorldFramework] ERROR: ServerTriggerEvent is not initialized.")
        end
    end
end

-- Immediately stops the active event
function LivingWorldFramework.DebugStopActiveEvent()
    if isClient() then
        sendClientCommand("LivingWorldFramework", "debugStop", {})
        print("[LivingWorldFramework] Sent debug stop command.")
    else
        if LivingWorldFramework.ServerStopActiveEvent then
            LivingWorldFramework.ServerStopActiveEvent()
        end
    end
end

-- Resets the framework active mutator and climate override state (for testing)
function LivingWorldFramework.DebugResetState()
    print("[LivingWorldFramework] Resetting active modifiers and climate overrides...")
    
    -- 1. Restore all original sandbox values
    for path, vanillaVal in pairs(originalSandboxVars) do
        setSandboxVar(path, vanillaVal)
    end
    
    -- 2. Release all climate admin controls
    local clim = getClimateManager()
    if clim then
        for floatId, _ in pairs(climateOverrides) do
            local climFloat = clim:getClimateFloat(floatId)
            if climFloat then
                climFloat:setEnableAdmin(false)
            end
        end
    end
    
    -- 3. Clear tables
    for k in pairs(originalSandboxVars) do originalSandboxVars[k] = nil end
    for k in pairs(modifiers) do modifiers[k] = nil end
    for k in pairs(climateOverrides) do climateOverrides[k] = nil end
    LivingWorldFramework.zombieRefreshRequested = false
    LivingWorldFramework.ServerConfigs = {}
end
