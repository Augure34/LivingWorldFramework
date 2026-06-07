if isClient() and not isServer() then return end

LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}

local eventDef = LivingWorldFramework.events["ColdSnap"]
if not eventDef then
    print("[ColdSnap] Server script loaded, but event registration was not found in shared script.")
    return
end

local FLOAT_TEMPERATURE = 4

local function announceEvent(text)
    if isServer() then
        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                if p then p:Say(text) end
            end
        end
    else
        local p = getPlayer(0)
        if p then p:Say(text) end
    end
end

eventDef.onStart = function(state)
    local tempVal = LivingWorldFramework.GetConfig("ColdSnap", "TemperatureDrop")
    local makeShamblers = LivingWorldFramework.GetConfig("ColdSnap", "MakeShamblers")

    print("[ColdSnap] Event starting. Pushing Sandbox modifiers and Climate overrides via LWF.")
    announceEvent("A freezing wind blows... A severe cold snap is starting!")

    local priority = eventDef.priority or 0

    if makeShamblers then
        -- 3 = Shamblers
        LivingWorldFramework.PushModifier("ColdSnap", "ZombieLore.Speed", 3, priority)
    end

    LivingWorldFramework.SetClimateOverride("ColdSnap", FLOAT_TEMPERATURE, -tempVal)
    LivingWorldFramework.RequestZombieRefresh()
end

eventDef.onUpdate = function(state, dt)
    LivingWorldFramework.RequestZombieRefresh()
end

eventDef.onStop = function(state)
    print("[ColdSnap] Event stopping. Popping modifiers and clearing overrides.")
    announceEvent("The freezing wind dies down. The cold snap has ended.")

    LivingWorldFramework.PopModifier("ColdSnap", "ZombieLore.Speed")
    LivingWorldFramework.ClearClimateOverride("ColdSnap", FLOAT_TEMPERATURE)
    LivingWorldFramework.RequestZombieRefresh()
end
