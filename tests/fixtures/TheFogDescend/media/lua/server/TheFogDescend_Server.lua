if isClient() and not isServer() then return end -- Only load on server or singleplayer host

LivingWorldFramework = LivingWorldFramework or {}
LivingWorldFramework.events = LivingWorldFramework.events or {}

local eventDef = LivingWorldFramework.events["TheFogDescend"]
if not eventDef then
    print("[TheFogDescend] Server script loaded, but event registration was not found in shared script.")
    return
end

local isEventActive = false

-- Indices confirmed from vanilla ISAdmPanelClimate.lua
local FLOAT_DESATURATION = 0
local FLOAT_NIGHT_STRENGTH = 2
local FLOAT_FOG_INTENSITY = 5
local FLOAT_CLOUD_INTENSITY = 8
local FLOAT_AMBIENT = 9
local FLOAT_DAYLIGHT_STRENGTH = 11

-- Define scheduler callbacks

eventDef.onStart = function(state)
    isEventActive = true
    local fogVal = LivingWorldFramework.GetConfig("TheFogDescend", "FogIntensity")
    local makeSprinters = LivingWorldFramework.GetConfig("TheFogDescend", "MakeSprinters")
    local makeAggressive = LivingWorldFramework.GetConfig("TheFogDescend", "MakeAggressive")
    
    print("[TheFogDescend] Event starting. Pushing Sandbox modifiers and Climate overrides via LWF.")

    -- Play Silent Hill Alarm Siren if configured
    if LivingWorldFramework.GetConfig("TheFogDescend", "PlaySiren") then
        if isServer() then
            sendServerCommand("TheFogDescend", "playSiren", {})
        else
            local soundManager = getSoundManager()
            if soundManager then
                soundManager:PlaySound("TheFogDescend_Siren", false, 1.0)
            end
        end
    end

    local priority = eventDef.priority or 0

    -- Push sandbox modifications
    if makeSprinters then
        LivingWorldFramework.PushModifier("TheFogDescend", "ZombieLore.Speed", 1, priority)
    end
    if makeAggressive then
        LivingWorldFramework.PushModifier("TheFogDescend", "ZombieLore.Sight", 1, priority)
        LivingWorldFramework.PushModifier("TheFogDescend", "ZombieLore.Hearing", 1, priority)
        LivingWorldFramework.PushModifier("TheFogDescend", "ZombieLore.Cognition", 1, priority)
    end

    -- Set climate overrides
    LivingWorldFramework.SetClimateOverride("TheFogDescend", FLOAT_FOG_INTENSITY, fogVal)
    LivingWorldFramework.SetClimateOverride("TheFogDescend", FLOAT_CLOUD_INTENSITY, 0.9)
    LivingWorldFramework.SetClimateOverride("TheFogDescend", FLOAT_DESATURATION, 0.5)
    
    -- Make the world darker during the fog
    LivingWorldFramework.SetClimateOverride("TheFogDescend", FLOAT_NIGHT_STRENGTH, 0.8)
    LivingWorldFramework.SetClimateOverride("TheFogDescend", FLOAT_DAYLIGHT_STRENGTH, 0.1)
    LivingWorldFramework.SetClimateOverride("TheFogDescend", FLOAT_AMBIENT, 0.1)

    -- Request zombie stats reload
    LivingWorldFramework.RequestZombieRefresh()
end

eventDef.onUpdate = function(state, dt)
    -- Periodic update of active zombies in cell (handles newly loaded chunks)
    LivingWorldFramework.RequestZombieRefresh()
end

eventDef.onStop = function(state)
    isEventActive = false
    print("[TheFogDescend] Event stopping. Popping modifiers and clearing overrides.")

    -- Pop sandbox modifications
    LivingWorldFramework.PopModifier("TheFogDescend", "ZombieLore.Speed")
    LivingWorldFramework.PopModifier("TheFogDescend", "ZombieLore.Sight")
    LivingWorldFramework.PopModifier("TheFogDescend", "ZombieLore.Hearing")
    LivingWorldFramework.PopModifier("TheFogDescend", "ZombieLore.Cognition")

    -- Clear climate overrides
    LivingWorldFramework.ClearClimateOverride("TheFogDescend", FLOAT_FOG_INTENSITY)
    LivingWorldFramework.ClearClimateOverride("TheFogDescend", FLOAT_CLOUD_INTENSITY)
    LivingWorldFramework.ClearClimateOverride("TheFogDescend", FLOAT_DESATURATION)
    LivingWorldFramework.ClearClimateOverride("TheFogDescend", FLOAT_NIGHT_STRENGTH)
    LivingWorldFramework.ClearClimateOverride("TheFogDescend", FLOAT_DAYLIGHT_STRENGTH)
    LivingWorldFramework.ClearClimateOverride("TheFogDescend", FLOAT_AMBIENT)

    -- Request zombie stats reload
    LivingWorldFramework.RequestZombieRefresh()
end

-- Vehicle Stall Mechanism during active fog (Inspired by 'The Darkness Is Coming')
local function checkVehicleStall()
    local player = getPlayer()
    if not player then return end

    local vehicle = player:getVehicle()
    if not vehicle or vehicle:getDriver() ~= player then return end

    if vehicle:isEngineRunning() then
        -- 2% chance of engine stall every minute
        if ZombRandFloat(0.0, 1.0) < 0.02 then
            vehicle:shutOff()
            player:Say("The engine sputtered and died in the thick fog...")
        end
    end
end

local function onEveryOneMinute()
    if not isEventActive then return end

    if isServer() then
        sendServerCommand("TheFogDescend", "checkVehicleStall", {})
    else
        -- Singleplayer
        checkVehicleStall()
    end
end

Events.EveryOneMinute.Add(onEveryOneMinute)
