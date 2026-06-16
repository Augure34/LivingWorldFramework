LivingWorldFramework = LivingWorldFramework or {}

local function registerPZAPIOptions()
    if not PZAPI or not PZAPI.ModOptions then
        print("[LivingWorldFramework] Warning: PZAPI.ModOptions is not found on client.")
        return
    end

    print("[LivingWorldFramework] Registering mod configurations with native PZAPI.ModOptions...")

    -- 1. Register framework settings
    if LivingWorldFramework.configOptions then
        local lwfGroup = PZAPI.ModOptions:create("LivingWorldFramework", "Living World Framework")
        for _, opt in ipairs(LivingWorldFramework.configOptions) do
            if opt.type == "boolean" then
                lwfGroup:addTickBox(opt.id, opt.name, opt.default, opt.tooltip)
            elseif opt.type == "integer" or opt.type == "double" then
                local step = opt.step or (opt.type == "integer" and 1 or 0.1)
                lwfGroup:addSlider(opt.id, opt.name, opt.min, opt.max, step, opt.default, opt.tooltip)
            elseif opt.type == "string" then
                lwfGroup:addTextEntry(opt.id, opt.name, opt.default, opt.tooltip)
            end
        end
    end

    -- 2. Register each mod's settings
    for eventId, eventDef in pairs(LivingWorldFramework.events) do
        if eventDef.configOptions then
            local group = PZAPI.ModOptions:create(eventId, eventDef.name or eventId)
            for _, opt in ipairs(eventDef.configOptions) do
                local optionObj = nil
                if not opt.hidden then
                    if opt.type == "title" then
                        group:addTitle(opt.name)
                    elseif opt.type == "separator" then
                        group:addSeparator()
                    elseif opt.type == "boolean" then
                        optionObj = group:addTickBox(opt.id, opt.name, opt.default, opt.tooltip)
                    elseif opt.type == "integer" or opt.type == "double" then
                        local step = opt.step or (opt.type == "integer" and 1 or 0.1)
                        optionObj = group:addSlider(opt.id, opt.name, opt.min, opt.max, step, opt.default, opt.tooltip)
                    elseif opt.type == "string" then
                        optionObj = group:addTextEntry(opt.id, opt.name, opt.default, opt.tooltip)
                    elseif opt.type == "enum" then
                        optionObj = group:addComboBox(opt.id, opt.name, opt.tooltip)
                        if optionObj and opt.options then
                            local defaultVal = opt.default or (opt.options[opt.defaultIndex or 1])
                            for _, val in ipairs(opt.options) do
                                optionObj:addItem(val, val == defaultVal)
                            end

                            local nativeSetValue = optionObj.setValue
                            optionObj.setValue = function(self, val)
                                local targetIndex = val
                                if type(val) == "string" then
                                    for idx, sVal in ipairs(opt.options) do
                                        if sVal == val then
                                            targetIndex = idx
                                            break
                                        end
                                    end
                                end
                                if type(targetIndex) == "number" then
                                    nativeSetValue(self, targetIndex)
                                    if self.onChange then
                                        self.onChange(targetIndex)
                                    end
                                end
                            end
                        end
                    end
                end
                
                if optionObj and opt.onChange then
                    optionObj.onChange = function(self, value)
                        local actualVal = value
                        if actualVal == nil and type(self) ~= "table" then
                            actualVal = self
                        end
                        local resolvedVal = actualVal
                        if opt.type == "enum" and type(actualVal) == "number" and opt.options then
                            resolvedVal = opt.options[actualVal] or actualVal
                        end
                        opt.onChange(group, resolvedVal)
                    end
                end
            end
        end
    end

    -- 3. Load values from ModOptions.ini
    PZAPI.ModOptions:load()
end

-- Helper to collect all configuration values
local function collectConfigurations()
    local configs = {}

    -- Collect framework configs
    configs["LivingWorldFramework"] = {}
    if LivingWorldFramework.configOptions then
        for _, opt in ipairs(LivingWorldFramework.configOptions) do
            if opt.id then
                configs["LivingWorldFramework"][opt.id] = LivingWorldFramework.GetConfig("LivingWorldFramework", opt.id)
            end
        end
    end

    -- Collect event configs
    for eventId, eventDef in pairs(LivingWorldFramework.events) do
        if eventDef.configOptions then
            configs[eventId] = {}
            for _, opt in ipairs(eventDef.configOptions) do
                if opt.id then
                    configs[eventId][opt.id] = LivingWorldFramework.GetConfig(eventId, opt.id)
                end
            end
        end
    end

    return configs
end

-- Sync configurations to the server context
local function syncConfigurations()
    local configs = collectConfigurations()
    sendClientCommand("LivingWorldFramework", "syncConfig", { configs = configs })
    print("[LivingWorldFramework] Sent synced configuration settings to the server.")
end

-- Register ModOptions early in OnInitWorld
Events.OnInitWorld.Add(registerPZAPIOptions)

-- Sync options on Game Start
Events.OnGameStart.Add(syncConfigurations)

-- Add context menu trigger options when game is in debug mode
local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    local isDebug = false
    if isDebugEnabled and isDebugEnabled() then
        isDebug = true
    elseif getCore and getCore():getDebug() then
        isDebug = true
    end
    if not isDebug then return end
    
    local g = _G or getfenv()
    if not g.ISContextMenu then return end

    local lwfMenu = context:addOption("Living World Framework Debug")
    local subMenu = g.ISContextMenu:getNew(context)
    context:addSubMenu(lwfMenu, subMenu)

    -- Submenu for triggering events
    local triggerOption = subMenu:addOption("Trigger Event")
    local triggerSubMenu = g.ISContextMenu:getNew(subMenu)
    subMenu:addSubMenu(triggerOption, triggerSubMenu)

    for eventId, eventDef in pairs(LivingWorldFramework.events) do
        triggerSubMenu:addOption(eventDef.name or eventId, nil, function()
            LivingWorldFramework.DebugTriggerEvent(eventId)
        end)
    end

    -- Option to stop the active event
    subMenu:addOption("Stop Active Event", nil, function()
        LivingWorldFramework.DebugStopActiveEvent()
    end)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

