LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}

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
        { id = "PlaySiren", name = "Play Siren Alarm", type = "boolean", default = false, tooltip = "Play a warning siren when the fog begins." },
        { id = "FogIntensity", name = "Target Fog Intensity Limit", type = "double", min = 0.0, max = 1.0, step = 0.05, default = 0.90, tooltip = "The maximum target fog density limit. If the weather is naturally foggier, the foggier weather is kept.", hidden = true },
        { id = "MakeSprinters", name = "Zombies Are Sprinters", type = "boolean", default = true, tooltip = "Temporarily accelerates zombies to sprinters during the fog (if their vanilla speed setting is slower).", hidden = true },
        { id = "MakeAggressive", name = "Zombies Are Aggressive", type = "boolean", default = true, tooltip = "Temporarily enhances zombie sight, hearing, and cognition during the fog (if their vanilla settings are poorer).", hidden = true }
    }
}

LivingWorldFramework.RegisterEvent(eventDef)
