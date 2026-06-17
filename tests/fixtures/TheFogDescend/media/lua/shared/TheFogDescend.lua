LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}

TheFogDescend = TheFogDescend or {}
TheFogDescend.isApplyingPreset = false
TheFogDescend.isEventActive = false

TheFogDescend.presets = {
    ["Normal"] = {
        MinTimeUntilFirstTrigger = 5,
        MaxTimeUntilFirstTrigger = 5,
        MinDuration = 24,
        MaxDuration = 24,
        MinCooldown = 5,
        MaxCooldown = 5,
        TriggerChance = 0.20,
        PlaySiren = true,
        ShowRadioWarnings = true,
        MakeSprinters = true,
        MakeAggressive = true,
        ToxicFogEnabled = true,
        ToxicityDeathHours = 12
    },
    ["Hardcore"] = {
        MinTimeUntilFirstTrigger = 2,
        MaxTimeUntilFirstTrigger = 30,
        MinDuration = 12,
        MaxDuration = 120,
        MinCooldown = 1,
        MaxCooldown = 30,
        TriggerChance = 0.25,
        PlaySiren = true,
        ShowRadioWarnings = true,
        MakeSprinters = true,
        MakeAggressive = true,
        ToxicFogEnabled = true,
        ToxicityDeathHours = 6
    }
}

local function onFineTuneChange(group, value)
    if TheFogDescend.isApplyingPreset then return end
    local presetObj = group:getOption("Preset")
    if presetObj and presetObj:getValue() ~= "Custom" then
        presetObj:setValue("Custom")
    end
end

local eventDef = {
    id = "TheFogDescend",
    name = "The Fog Descend",
    
    -- Scheduling defaults
    defaultMinTimeUntilFirstTrigger = 5,
    defaultMaxTimeUntilFirstTrigger = 5,
    defaultMinDuration = 24,
    defaultMaxDuration = 24,
    defaultMinCooldown = 5,
    defaultMaxCooldown = 5,
    defaultTriggerChance = 0.2,
    
    radioWarning = {
        leadHours = 24,
        message = "~~ WEATHER ALERT ~~ REGIONAL DENSE FOG ADVISORY. EXTREME ACCUMULATION INCOMING. VISIBILITY REDUCED TO ZERO. TRAVEL STRONGLY DISCOURAGED.",
        color = { r = 1.0, g = 0.3, b = 0.3 }
    },
    defaultShowRadioWarnings = true,
    defaultShowCharacterVoice = false,
    
    -- Expose scheduling to options menu
    exposeTimeUntilFirstTrigger = true,
    exposeDuration = true,
    exposeCooldown = true,
    exposeTriggerChance = true,
    exposeTimeOfDay = false,

    configOptions = {
        { type = "title", name = "Event Presets" },
        { id = "Preset", name = "Configuration Preset", type = "enum", options = { "Normal", "Hardcore", "Custom" }, defaultIndex = 1, tooltip = "Select a preset configuration, or customize settings below.",
          onChange = function(group, value)
              if value == "Custom" then return end
              local presetData = TheFogDescend.presets[value]
              if not presetData then return end

              TheFogDescend.isApplyingPreset = true
              for optId, optVal in pairs(presetData) do
                  local optObj = group:getOption(optId)
                  if optObj then
                      optObj:setValue(optVal)
                  end
              end
              TheFogDescend.isApplyingPreset = false
          end
        },
        { type = "separator" },
        { type = "title", name = "Fine-Tuning Settings" },
        
        { id = "MinTimeUntilFirstTrigger", name = "Min Time Until First Trigger (Days)", type = "integer", min = 0, max = 365, default = 5, tooltip = "Minimum number of days before the event can trigger for the first time.", onChange = onFineTuneChange, hidden = false },
        { id = "MaxTimeUntilFirstTrigger", name = "Max Time Until First Trigger (Days)", type = "integer", min = 0, max = 365, default = 5, tooltip = "Maximum number of days before the event can trigger for the first time.", onChange = onFineTuneChange, hidden = false },
        { id = "MinDuration", name = "Min Duration (Hours)", type = "integer", min = 1, max = 168, default = 24, tooltip = "Minimum duration of the event in hours.", onChange = onFineTuneChange, hidden = false },
        { id = "MaxDuration", name = "Max Duration (Hours)", type = "integer", min = 1, max = 168, default = 24, tooltip = "Maximum duration of the event in hours.", onChange = onFineTuneChange, hidden = false },
        { id = "MinCooldown", name = "Min Cooldown (Days)", type = "integer", min = 1, max = 100, default = 5, tooltip = "Minimum days between occurrences.", onChange = onFineTuneChange, hidden = false },
        { id = "MaxCooldown", name = "Max Cooldown (Days)", type = "integer", min = 1, max = 100, default = 5, tooltip = "Maximum days between occurrences.", onChange = onFineTuneChange, hidden = false },
        { id = "TriggerChance", name = "Daily Trigger Probability", type = "double", min = 0.0, max = 1.0, step = 0.05, default = 0.20, tooltip = "The probability checked once per day.", onChange = onFineTuneChange, hidden = false },

        { id = "PlaySiren", name = "Play Siren Alarm", type = "boolean", default = true, tooltip = "Play a warning siren when the fog begins.", onChange = onFineTuneChange, hidden = false },
        { id = "ShowRadioWarnings", name = "Enable Radio Warnings", type = "boolean", default = true, tooltip = "Whether warnings for this event are injected into the automated weather forecast channel.", onChange = onFineTuneChange, hidden = false },
        
        { id = "FogIntensity", name = "Target Fog Intensity Limit", type = "double", min = 0.0, max = 1.0, step = 0.05, default = 0.90, tooltip = "The maximum target fog density limit. If the weather is naturally foggier, the foggier weather is kept.", hidden = true },
        { id = "MakeSprinters", name = "Zombies Are Sprinters", type = "boolean", default = true, tooltip = "Temporarily accelerates zombies to sprinters during the fog (if their vanilla speed setting is slower).", onChange = onFineTuneChange, hidden = false },
        { id = "MakeAggressive", name = "Zombies Are Aggressive", type = "boolean", default = true, tooltip = "Temporarily enhances zombie sight, hearing, and cognition during the fog (if their vanilla settings are poorer).", onChange = onFineTuneChange, hidden = false },
        { id = "ToxicFogEnabled", name = "Toxic Fog Enabled", type = "boolean", default = true, tooltip = "If enabled, the fog is toxic.", onChange = onFineTuneChange, hidden = false },
        { id = "ToxicityDeathHours", name = "Toxicity Death Time (Hours)", type = "integer", min = 1, max = 72, default = 12, tooltip = "The number of hours of exposure before death.", onChange = onFineTuneChange, hidden = false }
    }
}

LivingWorldFramework.RegisterEvent(eventDef)
