LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}

local eventDef = {
    id = "ColdSnap",
    name = "Cold Snap",
    exclusivity = "Coexist",

    -- Scheduling defaults
    defaultMinTimeUntilFirstTrigger = 7,
    defaultMaxTimeUntilFirstTrigger = 7,
    defaultMinDuration = 12,
    defaultMaxDuration = 12,
    defaultMinCooldown = 7,
    defaultMaxCooldown = 7,
    defaultTriggerChance = 0.2,

    characterVoiceStart = "A freezing wind blows... A severe cold snap is starting!",
    characterVoiceStop = "The freezing wind dies down. The cold snap has ended.",
    defaultShowRadioWarnings = true,
    defaultShowCharacterVoice = true,

    -- Expose scheduling to options menu
    exposeTimeUntilFirstTrigger = true,
    exposeDuration = true,
    exposeCooldown = true,
    exposeTriggerChance = true,
    exposeTimeOfDay = false,

    configOptions = {
        { id = "TemperatureDrop", name = "Temperature Drop (°C)", type = "double", min = 0.0, max = 50.0, step = 1.0, default = 15.0, tooltip = "The temperature drop offset applied during the cold snap (e.g. 15.0 drops the temperature by 15°C relative to natural weather)." },
        { id = "MakeShamblers", name = "Zombies Are Shamblers", type = "boolean", default = true, tooltip = "Slows zombies down to shamblers during the cold snap (if their vanilla speed setting is faster).", hidden = true }
    }
}

LivingWorldFramework.RegisterEvent(eventDef)
