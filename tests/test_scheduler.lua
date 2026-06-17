-- Unit Test Suite for LivingWorldFramework and TheFogDescend

-- Set up package path to include the current workspace directory
package.path = package.path .. ";./?.lua"

-- Save original math.random
local originalMathRandom = math.random
local mockRandomFloat = nil
local mockRandomInt = nil
local mockRandomFloatsQueue = {}

math.random = function(a, b)
    if not a and not b then
        if #mockRandomFloatsQueue > 0 then
            return table.remove(mockRandomFloatsQueue, 1)
        end
        if mockRandomFloat then return mockRandomFloat end
        return originalMathRandom()
    end
    if mockRandomInt then return mockRandomInt end
    return originalMathRandom(a, b)
end

-- Load mock environment
require("tests/mocks/zomboid_mock")

-- Load Core Framework files
require("LivingWorldFramework/media/lua/shared/LivingWorldFramework")
require("LivingWorldFramework/media/lua/server/LivingWorldFramework_Server")
require("LivingWorldFramework/media/lua/client/LivingWorldFramework_Client")

-- Load TheFogDescend Mod files
require("TheFogDescend/media/lua/shared/TheFogDescend")
require("TheFogDescend/media/lua/server/TheFogDescend_Server")
require("TheFogDescend/media/lua/client/TheFogDescend_Client")

-- Load ColdSnap Mod files
require("ColdSnap/media/lua/shared/ColdSnap")
require("ColdSnap/media/lua/server/ColdSnap_Server")

-- Simple Assert Helper
local function assertEquals(actual, expected, name)
    if actual ~= expected then
        print(string.format("  [FAIL] %s: Expected %s, got %s", name, tostring(expected), tostring(actual)))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", name))
    end
end

local function assertTrue(condition, name)
    assertEquals(not not condition, true, name)
end

local function assertFalse(condition, name)
    assertEquals(not not condition, false, name)
end

-- Initialize World
getGameTime():setNightsSurvived(0)
Events.OnInitWorld.callback()
Events.OnLoadRadioScripts.callback()

-- Force options for deterministic scheduling behavior during tests
local fogOpts = PZAPI.ModOptions:getOptions("TheFogDescend")
if fogOpts then
    if fogOpts:getOption("TriggerChance") then fogOpts:getOption("TriggerChance"):setValue(1.0) end
    if fogOpts:getOption("MinTimeUntilFirstTrigger") then fogOpts:getOption("MinTimeUntilFirstTrigger"):setValue(5) end
    if fogOpts:getOption("MaxTimeUntilFirstTrigger") then fogOpts:getOption("MaxTimeUntilFirstTrigger"):setValue(5) end
    if fogOpts:getOption("MinDuration") then fogOpts:getOption("MinDuration"):setValue(24) end
    if fogOpts:getOption("MaxDuration") then fogOpts:getOption("MaxDuration"):setValue(24) end
    if fogOpts:getOption("MinCooldown") then fogOpts:getOption("MinCooldown"):setValue(5) end
    if fogOpts:getOption("MaxCooldown") then fogOpts:getOption("MaxCooldown"):setValue(5) end
end
local csOpts = PZAPI.ModOptions:getOptions("ColdSnap")
if csOpts and csOpts:getOption("TriggerChance") then
    csOpts:getOption("TriggerChance"):setValue(1.0)
end

Events.OnGameStart.callback()


print("-------------------------------------------------")
print("TEST 1: Event Registration & Schema Generation")
print("-------------------------------------------------")
local event = LivingWorldFramework.events["TheFogDescend"]
assertTrue(event ~= nil, "Event 'TheFogDescend' is registered")
assertEquals(event.id, "TheFogDescend", "Event has correct ID")

-- Verify scheduling configs were automatically generated
local function hasOption(id)
    for _, opt in ipairs(event.configOptions) do
        if opt.id == id then return true, opt end
    end
    return false, nil
end

assertTrue(hasOption("MinTimeUntilFirstTrigger"), "Option MinTimeUntilFirstTrigger generated")
assertTrue(hasOption("MaxTimeUntilFirstTrigger"), "Option MaxTimeUntilFirstTrigger generated")
assertTrue(hasOption("MinDuration"), "Option MinDuration generated")
assertTrue(hasOption("MaxDuration"), "Option MaxDuration generated")
assertTrue(hasOption("MinCooldown"), "Option MinCooldown generated")
assertTrue(hasOption("MaxCooldown"), "Option MaxCooldown generated")
assertTrue(hasOption("TriggerChance"), "Option TriggerChance generated")
assertTrue(hasOption("OnlyRain"), "Option OnlyRain generated")
assertTrue(hasOption("OnlyNight"), "Option OnlyNight generated")

local ok, minTimeOpt = hasOption("MinTimeUntilFirstTrigger")
assertEquals(minTimeOpt.default, 5, "MinTimeUntilFirstTrigger default value is 5")
assertEquals(minTimeOpt.hidden, false, "MinTimeUntilFirstTrigger is exposed (not hidden)")

local modData = ModData.get("LivingWorldFramework")
-- Note: ModData is populated after OnInitWorld/OnGameStart which uses defaults (5)
assertEquals(modData.eventStates["TheFogDescend"].scheduledStartDay, 5, "First trigger day target scheduled to 5")

print("-------------------------------------------------")
print("TEST 2: Scheduler - Below First Trigger Day (Should Not Trigger)")
print("-------------------------------------------------")
getGameTime():setNightsSurvived(2)
Events.EveryHours.callback() -- Run hourly check

assertEquals(modData.activeEventId, nil, "No event triggered at day 2")
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Zombies remain at normal speed (2)")

print("-------------------------------------------------")
print("TEST 3: Scheduler - Trigger on First Trigger Day")
print("-------------------------------------------------")
getGameTime():setNightsSurvived(5)
local modData = ModData.get("LivingWorldFramework")
local fogState = modData.eventStates["TheFogDescend"]
local currentHour = getGameTime():getHour()
fogState.scheduledStartDay = 5
fogState.scheduledStartHour = currentHour
fogState.scheduledStartTotalHours = 5 * 24 + currentHour
TestHelpers.clearZombies()
local z1 = TestHelpers.addZombie()

assertEquals(z1.statsRefreshed, 0, "Zombie 1 stats not refreshed yet")

Events.EveryHours.callback() -- Hourly check should trigger event

assertEquals(modData.activeEventId, "TheFogDescend", "TheFogDescend triggered at day 5")
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Zombie speed set to sprinters (1)")
assertEquals(z1.statsRefreshed, 1, "Zombie 1 stats immediately refreshed")
assertEquals(modData.eventStates["TheFogDescend"].activeDuration, 24, "Active duration rolled to 24 hours")

local fogState = TestHelpers.getClimateFloatState(5) -- FLOAT_FOG_INTENSITY
assertTrue(fogState.enabled, "Fog override is enabled")
assertEquals(fogState.val, 0.90, "Fog intensity is 0.90")

print("-------------------------------------------------")
print("TEST 4: Duration Ticking and Cooldown Rolling")
print("-------------------------------------------------")
-- -- Event runs for 24 hours. Let's tick 23 times (event should still be active).
local gt = getGameTime()
local startHour = gt:getHour()
local startDay = gt:getNightsSurvived()
for i = 1, 23 do
    local currentTotal = startDay * 24 + startHour + i
    gt:setNightsSurvived(math.floor(currentTotal / 24))
    gt:setHour(currentTotal % 24)
    Events.EveryHours.callback()
end
assertEquals(modData.activeEventId, "TheFogDescend", "Event remains active at hour 23")
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Zombies are still sprinters")

-- Tick 24th hour (event should finish and restore settings).
local currentTotal = startDay * 24 + startHour + 24
gt:setNightsSurvived(math.floor(currentTotal / 24))
gt:setHour(currentTotal % 24)
Events.EveryHours.callback()
assertEquals(modData.activeEventId, nil, "Event stopped after 24 hours")
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Zombies speed restored to normal (2)")
assertEquals(modData.eventStates["TheFogDescend"].scheduledStartDay, 11, "Next trigger day target set to 11 (current 6 + cooldown 5)")
assertFalse(fogState.enabled, "Fog override is disabled")

print("-------------------------------------------------")
print("TEST 5: Debug Trigger Override")
print("-------------------------------------------------")
-- Reset state
TestHelpers.resetModData()
Events.OnInitWorld.callback()
getGameTime():setNightsSurvived(1)
Events.OnGameStart.callback()
modData = ModData.get("LivingWorldFramework")

-- Trigger event via debug command
LivingWorldFramework.DebugTriggerEvent("TheFogDescend")

assertEquals(modData.activeEventId, "TheFogDescend", "Event forced active by debug trigger")
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Zombies are sprinters")
assertTrue(fogState.enabled, "Fog override enabled")

-- Stop event via debug command
LivingWorldFramework.DebugStopActiveEvent()

assertEquals(modData.activeEventId, nil, "Event stopped by debug command")
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Zombies speed restored")
assertFalse(fogState.enabled, "Fog override disabled")

print("-------------------------------------------------")
print("TEST 6: Sandbox Modifier Stacking & Climate Blending")
print("-------------------------------------------------")
-- Register two coexisting events
local eventA = {
    id = "EventA",
    priority = 2,
    exclusivity = "Coexist",
    onStart = function(state)
        LivingWorldFramework.PushModifier("EventA", "ZombieLore.Sight", 3, 2)
        LivingWorldFramework.SetClimateOverride("EventA", 5, 0.4)
    end,
    onStop = function(state)
        LivingWorldFramework.PopModifier("EventA", "ZombieLore.Sight")
        LivingWorldFramework.ClearClimateOverride("EventA", 5)
    end
}
local eventB = {
    id = "EventB",
    priority = 5,
    exclusivity = "Coexist",
    onStart = function(state)
        LivingWorldFramework.PushModifier("EventB", "ZombieLore.Sight", 1, 5)
        LivingWorldFramework.SetClimateOverride("EventB", 5, 0.8)
    end,
    onStop = function(state)
        LivingWorldFramework.PopModifier("EventB", "ZombieLore.Sight")
        LivingWorldFramework.ClearClimateOverride("EventB", 5)
    end
}
LivingWorldFramework.RegisterEvent(eventA)
LivingWorldFramework.RegisterEvent(eventB)

-- Trigger eventA
LivingWorldFramework.ServerTriggerEvent("EventA")
assertEquals(SandboxVars.ZombieLore.Sight, 3, "SandboxVars.ZombieLore.Sight set to 3 by EventA")
local overrideFog = TestHelpers.getClimateFloatState(5)
assertTrue(overrideFog.enabled, "Climate float 5 enabled")
assertEquals(overrideFog.val, 0.4, "Climate float 5 override is 0.4")

-- Trigger eventB (higher priority)
LivingWorldFramework.ServerTriggerEvent("EventB")
assertEquals(SandboxVars.ZombieLore.Sight, 1, "SandboxVars.ZombieLore.Sight set to 1 by EventB (higher priority)")
assertEquals(overrideFog.val, 0.8, "Climate float 5 override is max-blended to 0.8")

-- Stop eventB
LivingWorldFramework.ServerStopEvent("EventB")
assertEquals(SandboxVars.ZombieLore.Sight, 3, "SandboxVars.ZombieLore.Sight fell back to EventA (3)")
assertEquals(overrideFog.val, 0.4, "Climate float 5 override fell back to EventA (0.4)")

-- Stop eventA
LivingWorldFramework.ServerStopEvent("EventA")
assertEquals(SandboxVars.ZombieLore.Sight, 2, "SandboxVars.ZombieLore.Sight restored to vanilla (2)")
assertFalse(overrideFog.enabled, "Climate float 5 override disabled")

print("-------------------------------------------------")
print("TEST 7: Priority Preemption (Exclusive Events)")
print("-------------------------------------------------")
-- Register two exclusive events
local eventLow = {
    id = "EventLow",
    priority = 1,
    exclusivity = "Exclusive",
    onStart = function(state)
        LivingWorldFramework.PushModifier("EventLow", "ZombieLore.Speed", 3, 1)
    end,
    onStop = function(state)
        LivingWorldFramework.PopModifier("EventLow", "ZombieLore.Speed")
    end
}
local eventHigh = {
    id = "EventHigh",
    priority = 10,
    exclusivity = "Exclusive",
    onStart = function(state)
        LivingWorldFramework.PushModifier("EventHigh", "ZombieLore.Speed", 1, 10)
    end,
    onStop = function(state)
        LivingWorldFramework.PopModifier("EventHigh", "ZombieLore.Speed")
    end
}
LivingWorldFramework.RegisterEvent(eventLow)
LivingWorldFramework.RegisterEvent(eventHigh)

-- Trigger EventLow
assertTrue(LivingWorldFramework.ServerTriggerEvent("EventLow"), "Trigger EventLow succeeds")
assertEquals(modData.activeEventId, "EventLow", "EventLow is active")
assertEquals(SandboxVars.ZombieLore.Speed, 3, "Speed is 3")

-- Trigger EventHigh while EventLow is active (should preempt EventLow)
assertTrue(LivingWorldFramework.ServerTriggerEvent("EventHigh"), "Trigger EventHigh succeeds (preemption)")
assertEquals(modData.activeEventId, "EventHigh", "EventHigh preempted EventLow")
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Speed set to 1 by EventHigh")

-- Try to trigger EventLow while EventHigh is active (should fail/reject)
assertFalse(LivingWorldFramework.ServerTriggerEvent("EventLow"), "Trigger EventLow fails (lower priority)")
assertEquals(modData.activeEventId, "EventHigh", "EventHigh remains active")

-- Stop EventHigh
LivingWorldFramework.ServerStopEvent("EventHigh")
assertEquals(modData.activeEventId, nil, "No active exclusive event")
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Speed restored to vanilla (2)")

print("-------------------------------------------------")
print("TEST 8: Native Mod Options & Client-Server Syncing")
print("-------------------------------------------------")
-- 1. Simulate client updating their options in the UI
local fogOptions = PZAPI.ModOptions:getOptions("TheFogDescend")
assertTrue(fogOptions ~= nil, "Mod options group for 'TheFogDescend' exists")

local durationOpt = fogOptions:getOption("MaxDuration")
assertTrue(durationOpt ~= nil, "MaxDuration option exists in UI")
durationOpt:setValue(48) -- Set max duration to 48 hours instead of default 24

-- MakeSprinters is now hidden from UI config

-- 2. Trigger Client-Server synchronization via game start event callback
Events.OnGameStart.callback()

-- 3. Assert server context has received and cached the synced values
local syncedMaxDuration = LivingWorldFramework.GetConfig("TheFogDescend", "MaxDuration")
assertEquals(syncedMaxDuration, 48, "Server GetConfig returns updated MaxDuration (48)")
-- 4. Test privilege restriction on server: simulate non-admin player syncing
local originalIsServer = isServer
isServer = function() return true end -- Mock running on multiplayer server

local originalIsClient = isClient
isClient = function() return false end -- Mock server context

local originalGetOnlinePlayers = getOnlinePlayers
getOnlinePlayers = function()
    return {
        size = function() return 2 end, -- Mock 2 players online (multiplayer)
        get = function(self, idx) return nil end
    }
end

-- Clear server configs
local sModData = ModData.getOrCreate("LivingWorldFramework")
sModData.serverConfigs = {}
LivingWorldFramework.ServerConfigs = sModData.serverConfigs

-- Send sync config command from a non-admin client
local nonAdminPlayer = {
    getUsername = function() return "Griefer" end,
    getAccessLevel = function() return "None" end -- Regular player
}
local badConfigs = {
    TheFogDescend = { MaxDuration = 999 }
}

-- Invoke server command handler directly
Events.OnClientCommand.callback("LivingWorldFramework", "syncConfig", nonAdminPlayer, { configs = badConfigs })

-- Assert the bad config was rejected and server falls back to schema default (72)
local durationAfterRejection = LivingWorldFramework.GetConfig("TheFogDescend", "MaxDuration")
assertEquals(durationAfterRejection, 24, "Server config sync from non-admin was ignored (defaults to 24)")

-- Restore mock environment functions
isServer = originalIsServer
isClient = originalIsClient
getOnlinePlayers = originalGetOnlinePlayers

print("-------------------------------------------------")
print("TEST 9: Weather Restrictions (OnlyRain / OnlySnow)")
print("-------------------------------------------------")
local weatherEvent = {
    id = "WeatherEvent",
    exclusivity = "Coexist",
    exposeWeather = true,
    defaultOnlyRain = true,
    defaultOnlySnow = false
}
LivingWorldFramework.RegisterEvent(weatherEvent)

-- Initialize it
TestHelpers.resetModData()
getGameTime():setNightsSurvived(0)
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

local serverModData = ModData.get("LivingWorldFramework")
local wState = serverModData.eventStates["WeatherEvent"]
wState.scheduledStartDay = 2
wState.scheduledStartHour = getGameTime():getHour()
wState.scheduledStartTotalHours = 2 * 24 + wState.scheduledStartHour
getGameTime():setNightsSurvived(2)

-- Weather is clear
getClimateManager():setRaining(false)
Events.EveryHours.callback()
assertFalse(serverModData.coexistingEvents["WeatherEvent"], "WeatherEvent does not trigger when clear and OnlyRain = true")

-- Weather is raining
getClimateManager():setRaining(true)
Events.EveryHours.callback()
assertTrue(serverModData.coexistingEvents["WeatherEvent"] or false, "WeatherEvent triggers when raining and OnlyRain = true")

-- Stop it
LivingWorldFramework.ServerStopEvent("WeatherEvent")
assertFalse(serverModData.coexistingEvents["WeatherEvent"], "WeatherEvent is stopped")

print("-------------------------------------------------")
print("TEST 10: Time of Day Restrictions (OnlyNight / OnlyDay)")
print("-------------------------------------------------")
local nightEvent = {
    id = "NightEvent",
    exclusivity = "Coexist",
    exposeTimeOfDay = true,
    defaultOnlyNight = true,
    defaultOnlyDay = false
}
LivingWorldFramework.RegisterEvent(nightEvent)

-- Initialize it
TestHelpers.resetModData()
getGameTime():setNightsSurvived(0)
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

local serverModData = ModData.get("LivingWorldFramework")
local nightState = serverModData.eventStates["NightEvent"]
nightState.scheduledStartDay = 2
nightState.scheduledStartHour = 22 -- night only
nightState.scheduledStartTotalHours = 2 * 24 + 22
getGameTime():setNightsSurvived(2)

-- Set hour to midday (12:00)
getGameTime():setHour(12)
Events.EveryHours.callback()
assertFalse(serverModData.coexistingEvents["NightEvent"], "NightEvent does not trigger during the day")

-- Set hour to night (22:00)
getGameTime():setHour(22)
Events.EveryHours.callback()
assertTrue(serverModData.coexistingEvents["NightEvent"] or false, "NightEvent triggers during the night")

-- Stop it
LivingWorldFramework.ServerStopEvent("NightEvent")

print("-------------------------------------------------")
print("TEST 11: Daily Probability Chance Check")
print("-------------------------------------------------")
local chanceEvent = {
    id = "ChanceEvent",
    exclusivity = "Coexist",
    exposeTriggerChance = true,
    defaultTriggerChance = 0.5,
    exposeTimeUntilFirstTrigger = true,
    defaultMinTimeUntilFirstTrigger = 2,
    defaultMaxTimeUntilFirstTrigger = 2
}
LivingWorldFramework.RegisterEvent(chanceEvent)

-- Initialize it and run OnGameStart once to initialize all other events
TestHelpers.resetModData()
getGameTime():setNightsSurvived(0)
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

-- Force chanceEvent defaults
local chanceEventDef = LivingWorldFramework.events["ChanceEvent"]
chanceEventDef.defaultMinTimeUntilFirstTrigger = 2
chanceEventDef.defaultMaxTimeUntilFirstTrigger = 2
chanceEventDef.defaultTriggerChance = 0.5

-- Clear ChanceEvent state so it is scheduled fresh
local serverModData = ModData.get("LivingWorldFramework")
serverModData.eventStates["ChanceEvent"] = nil

-- Set up random floats queue: first roll (0.8) fails, second (0.1) succeeds.
-- This should add 1 extra day to the schedule, targeting day 3 instead of 2.
mockRandomFloatsQueue = { 0.8, 0.1 }
Events.OnGameStart.callback()

local serverModData = ModData.get("LivingWorldFramework")
local cState = serverModData.eventStates["ChanceEvent"]
assertEquals(cState.scheduledStartDay, 3, "ChanceEvent scheduled for day 3 after failing one daily probability roll")

-- Check at day 2: shouldn't trigger
getGameTime():setNightsSurvived(2)
getGameTime():setHour(cState.scheduledStartHour)
Events.EveryHours.callback()
assertFalse(serverModData.coexistingEvents["ChanceEvent"], "ChanceEvent does not trigger on day 2")

-- Move to day 3: should trigger
getGameTime():setNightsSurvived(3)
Events.EveryHours.callback()
assertTrue(serverModData.coexistingEvents["ChanceEvent"] or false, "ChanceEvent triggers on day 3 once scheduled start day is reached")

-- Stop it
LivingWorldFramework.ServerStopEvent("ChanceEvent")

-- Clean up random mocks
mockRandomFloatsQueue = {}
mockRandomFloat = nil
mockRandomInt = nil

print("-------------------------------------------------")
print("TEST 12: Overlapping Event Speed Blending & Climate Merging")
print("-------------------------------------------------")
-- Reset state
TestHelpers.resetModData()
Events.OnInitWorld.callback()
getGameTime():setNightsSurvived(1)
Events.OnGameStart.callback()
modData = ModData.get("LivingWorldFramework")

-- Ensure vanilla speed is 2
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Vanilla speed is 2")

-- 1. Trigger TheFogDescend alone (requests sprinters = 1)
LivingWorldFramework.ServerTriggerEvent("TheFogDescend")
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Speed set to sprinters (1) by TheFogDescend")
local tempFloat = TestHelpers.getClimateFloatState(4)
assertFalse(tempFloat.enabled, "Temperature override is not enabled yet")

-- 2. Trigger ColdSnap concurrently (requests shamblers = 3, temperature = -15)
LivingWorldFramework.ServerTriggerEvent("ColdSnap")
-- The speed resolver should blend them: average of 1 and 3 is 2 (Fast Shamblers)
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Speed blended to fast shamblers (2) when both events overlap")
assertTrue(tempFloat.enabled, "Temperature override is enabled")
assertEquals(tempFloat.val, -15.0, "Temperature set to -15.0 by ColdSnap min-blending")

-- 3. Stop TheFogDescend (leaving only ColdSnap active)
LivingWorldFramework.ServerStopEvent("TheFogDescend")
assertEquals(SandboxVars.ZombieLore.Speed, 3, "Speed falls back to shamblers (3) after TheFogDescend stops")
assertTrue(tempFloat.enabled, "Temperature override remains enabled")
assertEquals(tempFloat.val, -15.0, "Temperature remains -15.0")

-- 4. Stop ColdSnap
LivingWorldFramework.ServerStopEvent("ColdSnap")
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Speed restored to vanilla (2)")
assertFalse(tempFloat.enabled, "Temperature override is disabled")

print("-------------------------------------------------")
print("TEST 13: Bound-Limits for Climate Temperatures & Zombie Speeds")
print("-------------------------------------------------")
TestHelpers.resetModData()

-- A. Climate Temperature Limits Check
local tempFloatObj = TestHelpers.getClimateFloatState(4)

-- 1. ColdSnap is set to -15.0 drop offset. Natural temperature is -30.0.
tempFloatObj.calculateVal = -30.0
LivingWorldFramework.ServerTriggerEvent("ColdSnap")
assertTrue(tempFloatObj.enabled, "ColdSnap is active")
assertEquals(tempFloatObj.val, -45.0, "Natural -30.0 is dropped by 15.0, resulting in -45.0")

-- 2. ColdSnap is active. Natural temperature shifts to 10.0.
tempFloatObj.calculateVal = 10.0
LivingWorldFramework.ClearClimateOverride("ColdSnap", 4) -- trigger recalculation
LivingWorldFramework.SetClimateOverride("ColdSnap", 4, -15.0)
assertEquals(tempFloatObj.val, -5.0, "ColdSnap (-15.0 offset) applied to natural 10.0, resulting in -5.0")

LivingWorldFramework.ServerStopEvent("ColdSnap")

-- B. Zombie Speed Limits Check
-- 1. Player plays with max speed zombies (Sprinters = 1)
TestHelpers.resetModData() -- clear overrides and caches first
SandboxVars.ZombieLore.Speed = 1 -- then set the base speed to 1

-- Trigger event that increases speed to sprinters (1)
LivingWorldFramework.PushModifier("EventA", "ZombieLore.Speed", 1)
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Speed remains at sprinters (1)")

-- Trigger event that pushes speed out of bounds to 0 (faster than sprinters)
LivingWorldFramework.PushModifier("EventB", "ZombieLore.Speed", 0)
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Speed is clamped to sprinters (1) boundary")

-- End the events
LivingWorldFramework.PopModifier("EventA", "ZombieLore.Speed")
LivingWorldFramework.PopModifier("EventB", "ZombieLore.Speed")
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Speed remains sprinters (1) after events end")

-- 2. Player plays with normal fast shamblers (2)
TestHelpers.resetModData() -- clear overrides and caches first
SandboxVars.ZombieLore.Speed = 2 -- then set the base speed to 2

-- Trigger event that pushes speed out of bounds to 5 (slower than shamblers)
LivingWorldFramework.PushModifier("EventC", "ZombieLore.Speed", 5)
assertEquals(SandboxVars.ZombieLore.Speed, 4, "Speed is clamped to fake shamblers (4) boundary")

-- End the event
LivingWorldFramework.PopModifier("EventC", "ZombieLore.Speed")
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Speed restored to vanilla (2)")

print("-------------------------------------------------")
print("TEST 14: Debug Trigger Check Logging")
print("-------------------------------------------------")
TestHelpers.resetModData()
Events.OnInitWorld.callback()

-- Mock EnableDebug config for LivingWorldFramework on both server and client (PZAPI)
LivingWorldFramework.ServerConfigs["LivingWorldFramework"] = { EnableDebug = true }
local lwfOptions = PZAPI.ModOptions:getOptions("LivingWorldFramework")
if lwfOptions then
    local opt = lwfOptions:getOption("EnableDebug")
    if opt then opt:setValue(true) end
end

-- Let's set ColdSnap to be scheduled now, but fail rain restriction
local sModData = ModData.get("LivingWorldFramework")
sModData.eventStates["ColdSnap"] = sModData.eventStates["ColdSnap"] or {}
local csState = sModData.eventStates["ColdSnap"]
csState.scheduledStartDay = 1
csState.scheduledStartHour = 12
csState.scheduledStartTotalHours = 1 * 24 + 12

-- Force ColdSnap to require rain
LivingWorldFramework.ServerConfigs["ColdSnap"] = { OnlyRain = true }

-- Set current time to scheduled time (Day 1, 12:00)
getGameTime():setNightsSurvived(1)
getGameTime():setHour(12)

-- Weather is clear (should fail rain restriction)
getClimateManager():setRaining(false)

local printLog = {}
local originalPrint = print
print = function(str)
    table.insert(printLog, str)
    originalPrint(str)
end

-- Run hourly check, which calls DefaultCanTrigger for ColdSnap
Events.EveryHours.callback()

print = originalPrint

-- Assert that the printLog contains the check failure message
local foundLog = false
for _, log in ipairs(printLog) do
    if string.find(log, "ColdSnap") and string.find(log, "trigger check failed: only triggers in rain") then
        foundLog = true
        break
    end
end
assertTrue(foundLog, "Debug print log captured for trigger check failure when debug is enabled")

-- Verify it doesn't log when debug is disabled
TestHelpers.resetModData()
Events.OnInitWorld.callback()
LivingWorldFramework.ServerConfigs["LivingWorldFramework"] = { EnableDebug = false }
lwfOptions = PZAPI.ModOptions:getOptions("LivingWorldFramework")
if lwfOptions then
    local opt = lwfOptions:getOption("EnableDebug")
    if opt then opt:setValue(false) end
end

-- Re-setup event state
sModData = ModData.get("LivingWorldFramework")
sModData.eventStates["ColdSnap"] = sModData.eventStates["ColdSnap"] or {}
csState = sModData.eventStates["ColdSnap"]
csState.scheduledStartDay = 1
csState.scheduledStartHour = 12
csState.scheduledStartTotalHours = 1 * 24 + 12
LivingWorldFramework.ServerConfigs["ColdSnap"] = { OnlyRain = true }
getGameTime():setNightsSurvived(1)
getGameTime():setHour(12)
getClimateManager():setRaining(false)

printLog = {}
print = function(str)
    table.insert(printLog, str)
end

Events.EveryHours.callback()

print = originalPrint

foundLog = false
for _, log in ipairs(printLog) do
    if string.find(log, "ColdSnap") and string.find(log, "trigger check failed: only triggers in rain") then
        foundLog = true
        break
    end
end
assertFalse(foundLog, "No debug print log captured when debug is disabled")

print("-------------------------------------------------")
print("TEST 15: Silent Hill Siren Triggering")
print("-------------------------------------------------")
TestHelpers.resetModData()
TestHelpers.clearSoundCalls()

-- 1. Singleplayer Siren Triggering (isServer() = false)
local originalIsServer = isServer
isServer = function() return false end

-- Enable PlaySiren and trigger:
    local fogOpts = PZAPI.ModOptions:getOptions("TheFogDescend")
    if fogOpts and fogOpts:getOption("PlaySiren") then
        fogOpts:getOption("PlaySiren"):setValue(true)
    end
    LivingWorldFramework.ServerConfigs["TheFogDescend"] = { PlaySiren = true }
    LivingWorldFramework.ServerTriggerEvent("TheFogDescend")

    soundCalls = TestHelpers.getSoundCalls()
    assertEquals(#soundCalls, 1, "One sound call triggered in singleplayer when PlaySiren is true")
    assertEquals(soundCalls[1].name, "TheFogDescend_Siren", "Played the correct siren sound in singleplayer")
    assertEquals(soundCalls[1].loop, false, "Sound loop is false")
    assertEquals(soundCalls[1].volume, 1.0, "Sound volume is 1.0")

    LivingWorldFramework.ServerStopEvent("TheFogDescend")
    if fogOpts and fogOpts:getOption("PlaySiren") then
        fogOpts:getOption("PlaySiren"):setValue(false)
    end
    LivingWorldFramework.ServerConfigs["TheFogDescend"] = nil

-- 2. Multiplayer Siren Triggering (isServer() = true)
TestHelpers.resetModData()
TestHelpers.clearSoundCalls()
isServer = function() return true end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = { PlaySiren = true }

LivingWorldFramework.ServerTriggerEvent("TheFogDescend")

soundCalls = TestHelpers.getSoundCalls()
assertEquals(#soundCalls, 1, "One sound call triggered in multiplayer via server-to-client command")
assertEquals(soundCalls[1].name, "TheFogDescend_Siren", "Played the correct siren sound in multiplayer")

-- Clean up
isServer = originalIsServer
LivingWorldFramework.ServerConfigs["TheFogDescend"] = nil
LivingWorldFramework.ServerStopEvent("TheFogDescend")

print("-------------------------------------------------")
print("TEST 16: Vehicle Malfunctions in Fog")
print("-------------------------------------------------")
TestHelpers.resetModData()

-- Setup mock vehicle
local mockVehicle = TestHelpers.createMockVehicle()
mockVehicle.driver = getPlayer()
mockVehicle.engineRunning = true
TestHelpers.setMockVehicle(mockVehicle)

-- 1. No malfunction when event is NOT active
Events.EveryOneMinute.callback()
assertEquals(mockVehicle.engineRunning, true, "Engine still running (event inactive)")
assertEquals(mockVehicle.stalledCount, 0, "No stall triggered (event inactive)")

-- 2. Singleplayer malfunction when event is active and roll succeeds
isServer = function() return false end
LivingWorldFramework.ServerTriggerEvent("TheFogDescend")

-- Test high roll (0.50 >= 0.02) - should NOT stall
TestHelpers.setMockRandomFloat(0.50)
Events.EveryOneMinute.callback()
assertEquals(mockVehicle.engineRunning, true, "Engine still running (high random roll)")
assertEquals(mockVehicle.stalledCount, 0, "No stall triggered (high random roll)")

-- Test low roll (0.01 < 0.02) - SHOULD stall
TestHelpers.setMockRandomFloat(0.01)
Events.EveryOneMinute.callback()
assertEquals(mockVehicle.engineRunning, false, "Engine stopped (low random roll in singleplayer)")
assertEquals(mockVehicle.stalledCount, 1, "Stalled count is 1")

-- Re-enable engine
mockVehicle.engineRunning = true

-- 3. Multiplayer malfunction when event is active and roll succeeds
isServer = function() return true end

-- In multiplayer, EveryOneMinute on server broadcasts to clients.
-- Our mock sendServerCommand routes to client OnServerCommand which performs the roll.
-- Test high roll (0.50 >= 0.02)
TestHelpers.setMockRandomFloat(0.50)
Events.EveryOneMinute.callback()
assertEquals(mockVehicle.engineRunning, true, "Engine still running (MP high random roll)")

-- Test low roll (0.01 < 0.02)
TestHelpers.setMockRandomFloat(0.01)
Events.EveryOneMinute.callback()
assertEquals(mockVehicle.engineRunning, false, "Engine stopped (MP low random roll via client-command)")
assertEquals(mockVehicle.stalledCount, 2, "Stalled count is 2")

-- Clean up
isServer = originalIsServer
LivingWorldFramework.ServerStopEvent("TheFogDescend")

print("-------------------------------------------------")
print("TEST 17: AEBS Radio Warnings")
print("-------------------------------------------------")
TestHelpers.resetModData()
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

-- Simulate scheduling TheFogDescend for Day 1, Hour 20:00 (Total hours: 44)
local mData = ModData.get("LivingWorldFramework")
mData.eventStates["TheFogDescend"].scheduledStartDay = 1
mData.eventStates["TheFogDescend"].scheduledStartHour = 20
mData.eventStates["TheFogDescend"].scheduledStartTotalHours = 44

-- Current day is 0, hour is 19 (25 hours remaining, outside leadHours=24)
getGameTime():setNightsSurvived(0)
getGameTime():setHour(19)
local bc = WeatherChannel.CreateBroadcast(getGameTime())
local foundWarning = false
for _, line in ipairs(bc.lines) do
    if string.find(string.lower(line.text), "fog") then
        foundWarning = true
    end
end
assertFalse(foundWarning, "No warning injected at hour 19 (25 hours remaining)")

-- Current day is 0, hour is 20 (24 hours remaining, inside leadHours=24)
getGameTime():setHour(20)
local bcWarn = WeatherChannel.CreateBroadcast(getGameTime())
local foundWarning2 = false
for _, line in ipairs(bcWarn.lines) do
    if string.find(string.lower(line.text), "fog") then
        foundWarning2 = true
        assertEquals(line.r, 1.0, "Warning line is red (R=1)")
        assertEquals(line.g, 0.3, "Warning line has correct G")
        assertEquals(line.b, 0.3, "Warning line has correct B")
    end
end
assertTrue(foundWarning2, "Warning successfully injected at hour 20 (24 hours remaining)")

-- Disable ShowRadioWarnings for TheFogDescend
local fogOpts = PZAPI.ModOptions:getOptions("TheFogDescend")
if fogOpts and fogOpts:getOption("ShowRadioWarnings") then
    fogOpts:getOption("ShowRadioWarnings"):setValue(false)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = { ShowRadioWarnings = false }
local bcWarnOff = WeatherChannel.CreateBroadcast(getGameTime())
local foundWarning3 = false
for _, line in ipairs(bcWarnOff.lines) do
    if string.find(string.lower(line.text), "fog") then
        foundWarning3 = true
    end
end
assertFalse(foundWarning3, "Warning NOT injected when ShowRadioWarnings is false")
if fogOpts and fogOpts:getOption("ShowRadioWarnings") then
    fogOpts:getOption("ShowRadioWarnings"):setValue(true)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = nil -- restore

print("-------------------------------------------------")
print("TEST 18: Character Voice Alerts & Siren Configs")
print("-------------------------------------------------")
TestHelpers.resetModData()
TestHelpers.clearSoundCalls()
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

-- 1. ColdSnap starting: defaultShowCharacterVoice = true
local sayLog = {}
local origPrint = print
print = function(str)
    table.insert(sayLog, str)
    origPrint(str)
end

LivingWorldFramework.ServerTriggerEvent("ColdSnap")

print = origPrint

local foundSay = false
for _, log in ipairs(sayLog) do
    if string.find(log, "%[MOCK SAY%] A freezing wind blows") then
        foundSay = true
        break
    end
end
assertTrue(foundSay, "ColdSnap plays start announcement by default")

-- 2. ColdSnap starting with ShowCharacterVoice = false
TestHelpers.resetModData()
Events.OnInitWorld.callback()
Events.OnGameStart.callback()
local csOpts = PZAPI.ModOptions:getOptions("ColdSnap")
if csOpts and csOpts:getOption("ShowCharacterVoice") then
    csOpts:getOption("ShowCharacterVoice"):setValue(false)
end
LivingWorldFramework.ServerConfigs["ColdSnap"] = { ShowCharacterVoice = false }

sayLog = {}
print = function(str)
    table.insert(sayLog, str)
end
LivingWorldFramework.ServerTriggerEvent("ColdSnap")
print = origPrint

foundSay = false
for _, log in ipairs(sayLog) do
    if string.find(log, "%[MOCK SAY%] A freezing wind blows") then
        foundSay = true
        break
    end
end
assertFalse(foundSay, "ColdSnap does NOT play start announcement when ShowCharacterVoice is false")

-- 3. TheFogDescend siren: PlaySiren = true by default
TestHelpers.resetModData()
TestHelpers.clearSoundCalls()
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

LivingWorldFramework.ServerTriggerEvent("TheFogDescend")
local soundCalls = TestHelpers.getSoundCalls()
assertEquals(#soundCalls, 1, "Siren alarm sound called by default for TheFogDescend")
assertEquals(soundCalls[1].name, "TheFogDescend_Siren", "Played the correct siren sound by default")

-- 4. TheFogDescend siren: PlaySiren = false
TestHelpers.resetModData()
TestHelpers.clearSoundCalls()
Events.OnInitWorld.callback()
Events.OnGameStart.callback()
local fogOpts = PZAPI.ModOptions:getOptions("TheFogDescend")
if fogOpts and fogOpts:getOption("PlaySiren") then
    fogOpts:getOption("PlaySiren"):setValue(false)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = { PlaySiren = false }

LivingWorldFramework.ServerTriggerEvent("TheFogDescend")
soundCalls = TestHelpers.getSoundCalls()
assertEquals(#soundCalls, 0, "No siren alarm sound played when PlaySiren is false")

print("-------------------------------------------------")
print("TEST 19: Toxic Fog and Gas Mask Mechanics")
print("-------------------------------------------------")
TestHelpers.resetModData()
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

-- Setup mock variables for player
local mockPlayerObj = getPlayer()
local mockModDataVal = { fogToxicity = 0.0 }
local mockWornItems = {}
local mockBodyDamage = {
    health = 100,
    ReduceGeneralHealth = function(self, val) self.health = math.max(0.0, self.health - val) end
}
local mockStats = {
    values = {
        FATIGUE = 0.0,
        ENDURANCE = 1.0,
        PAIN = 0.0,
        POISON = 0.0
    },
    get = function(self, stat)
        return self.values[stat:getId()] or 0.0
    end,
    set = function(self, stat, val)
        self.values[stat:getId()] = val
    end
}
local isGodMode = false
local currentSquareIsOutside = true
local isPlayerAlive = true

mockPlayerObj.isLocalPlayer = function(self) return true end
mockPlayerObj.isAlive = function(self) return isPlayerAlive end
mockPlayerObj.getModData = function(self) return mockModDataVal end
mockPlayerObj.getCurrentSquare = function(self)
    return {
        isOutside = function(self) return currentSquareIsOutside end
    }
end
mockPlayerObj.getWornItems = function(self)
    return {
        size = function(self) return #mockWornItems end,
        get = function(self, idx) return mockWornItems[idx + 1] end
    }
end
mockPlayerObj.getBodyDamage = function(self) return mockBodyDamage end
mockPlayerObj.getStats = function(self) return mockStats end
mockPlayerObj.isGodMod = function(self) return isGodMode end
mockPlayerObj.getX = function(self) return 100 end
mockPlayerObj.getY = function(self) return 100 end
mockPlayerObj.getZ = function(self) return 0 end

-- Initially, event is inactive, player is outside, not wearing mask.
-- Toxicity should remain 0.
TheFogDescend.isEventActive = false
getGameTime():setNightsSurvived(0)
getGameTime():setHour(12)
Events.OnGameStart.callback() -- reset lastHours
Events.OnPlayerUpdate.callback(mockPlayerObj) -- sets lastHours = 12

getGameTime():setHour(13) -- 1 hour later
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockModDataVal.fogToxicity, 0.0, "Toxicity remains 0 when event is inactive")

-- Activate event. Now exposed. Toxicity should build up.
TheFogDescend.isEventActive = true
Events.OnGameStart.callback() -- reset lastHours
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj) -- sets lastHours = 12

-- 1 hour of exposure -> toxicity should be 1/12 ≈ 0.0833
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(math.abs(mockModDataVal.fogToxicity - 0.0833) < 0.001, "Toxicity increases by ~0.0833 after 1 hour of exposure")
assertTrue(mockStats:get(CharacterStat.POISON) > 0, "Poison level increases with toxicity")
assertTrue(mockStats:get(CharacterStat.FATIGUE) > 0, "Fatigue increases with toxicity")
assertTrue(mockStats:get(CharacterStat.ENDURANCE) < 1.0, "Endurance decreases with toxicity")
assertTrue(mockStats:get(CharacterStat.PAIN) > 0, "Pain increases with toxicity")

-- Test safe recovery: 1h exposure should take 2h of safe to reduce to 0
-- Move inside a building
currentSquareIsOutside = false
-- We check after 1 hour of safety (should reduce by 1/24 ≈ 0.0417, leaving 0.0417)
getGameTime():setHour(14)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(math.abs(mockModDataVal.fogToxicity - 0.0417) < 0.001, "Toxicity recovers by ~0.0417 after 1 hour of safety")

-- We check after 2nd hour of safety (should reduce to 0)
getGameTime():setHour(15)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockModDataVal.fogToxicity, 0.0, "Toxicity recovers fully to 0 after 2 hours of safety")
assertEquals(mockStats:get(CharacterStat.POISON), 0.0, "Poison level is cleared when toxicity reaches 0")

-- Move back outside
currentSquareIsOutside = true
Events.OnGameStart.callback() -- reset lastHours
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj) -- sets lastHours = 12

-- Wear a valid vanilla gas mask
local mockMask = {
    getName = function(self) return "Gas Mask" end,
    getFullType = function(self) return "Base.Hat_GasMask" end,
    getType = function(self) return "Hat_GasMask" end,
    getCondition = function(self) return 10 end,
    hasTag = function(self, itemTag) return tostring(itemTag) == "gasmask" end
}
mockWornItems = {
    { getItem = function(self) return mockMask end }
}

-- 1 hour later: toxicity should remain 0
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockModDataVal.fogToxicity, 0.0, "Toxicity remains 0 when wearing a valid gas mask")



-- Tagged B42 gas mask protection
mockWornItems = {}
local taggedMask = {
    getName = function(self) return "Tagged Mask" end,
    getFullType = function(self) return "Modded.TaggedMask" end,
    getType = function(self) return "TaggedMask" end,
    getCondition = function(self) return 8 end,
    getTags = function(self)
        local mockTags = { "gasmask" }
        return {
            size = function(self) return #mockTags end,
            get = function(self, idx) return mockTags[idx + 1] end,
            toArray = function(self) return mockTags end
        }
    end,
    hasTag = function(self, itemTag)
        return tostring(itemTag) == "gasmask"
    end
}
mockWornItems = {
    { getItem = function(self) return taggedMask end }
}

-- Set toxicity to 0.5, then check if it decreases (meaning they are safe under mask protection)
mockModDataVal.fogToxicity = 0.5
Events.OnGameStart.callback() -- reset lastHours
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj) -- sets lastHours = 12

getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(mockModDataVal.fogToxicity < 0.5, "Toxicity decreases when wearing a tagged B42 gas mask (protected)")

-- Broken gas mask (condition = 0)
mockWornItems = {}
local brokenMask = {
    getName = function(self) return "Broken Gas Mask" end,
    getFullType = function(self) return "Base.Hat_GasMask" end,
    getType = function(self) return "Hat_GasMask" end,
    getCondition = function(self) return 0 end,
    hasTag = function(self, itemTag) return tostring(itemTag) == "gasmask" end
}
mockWornItems = {
    { getItem = function(self) return brokenMask end }
}

-- 1 hour later: toxicity should increase (broken mask doesn't protect)
getGameTime():setHour(15)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(mockModDataVal.fogToxicity > 0.0, "Toxicity increases when wearing a broken gas mask")

-- TEST: Wearing both a non-gas mask item (like a Belt) and a valid gas mask
mockWornItems = {
    { getItem = function(self) return { getName = function() return "Belt" end, hasTag = function() return false end, getCondition = function() return 100 end } end },
    { getItem = function(self) return mockMask end }
}
mockModDataVal.fogToxicity = 0.5
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(mockModDataVal.fogToxicity < 0.5, "Toxicity decreases when wearing a Belt and a valid gas mask")

-- TEST: Wearing both a non-gas mask item (like a Belt) and a broken gas mask
mockWornItems = {
    { getItem = function(self) return { getName = function() return "Belt" end, hasTag = function() return false end, getCondition = function() return 100 end } end },
    { getItem = function(self) return brokenMask end }
}
mockModDataVal.fogToxicity = 0.5
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(mockModDataVal.fogToxicity > 0.5, "Toxicity increases when wearing a Belt and a broken gas mask")

-- TEST: Player in God Mode (no mask)
isGodMode = true
mockWornItems = {}
mockModDataVal.fogToxicity = 0.5
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(mockModDataVal.fogToxicity < 0.5, "Toxicity decreases in God Mode even without a mask")
isGodMode = false

-- TEST: Dead player toxicity reset
isPlayerAlive = false
mockModDataVal.fogToxicity = 0.5
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockModDataVal.fogToxicity, 0.0, "Toxicity reset to 0.0 for dead player")
isPlayerAlive = true

-- TEST: ToxicFogEnabled = false (Toxicity should recover even if outside without mask)
local lwfOpts = PZAPI.ModOptions:getOptions("TheFogDescend")
if lwfOpts and lwfOpts:getOption("ToxicFogEnabled") then
    lwfOpts:getOption("ToxicFogEnabled"):setValue(false)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = { ToxicFogEnabled = false, ToxicityDeathHours = 12 }
mockModDataVal.fogToxicity = 0.5
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(mockModDataVal.fogToxicity < 0.5, "Toxicity decreases when ToxicFogEnabled is false")
-- Restore
if lwfOpts and lwfOpts:getOption("ToxicFogEnabled") then
    lwfOpts:getOption("ToxicFogEnabled"):setValue(true)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = nil

-- TEST: ToxicityDeathHours Scaling (Toxicity changes faster or slower depending on DeathHours)
-- Case A: DeathHours = 6 (Faster build-up: +1/6 = 0.1667 per hour, faster recovery: -1/12 = 0.0833 per hour)
if lwfOpts and lwfOpts:getOption("ToxicityDeathHours") then
    lwfOpts:getOption("ToxicityDeathHours"):setValue(6)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = { ToxicFogEnabled = true, ToxicityDeathHours = 6 }

-- Build-up test
mockModDataVal.fogToxicity = 0.0
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(math.abs(mockModDataVal.fogToxicity - 0.1667) < 0.001, "Toxicity increases twice as fast (0.1667) when ToxicityDeathHours is 6")

-- Recovery test (should recover by 1/(6*2) = 1/12 = 0.0833)
currentSquareIsOutside = false
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(math.abs(mockModDataVal.fogToxicity - 0.0833) < 0.001, "Toxicity recovers twice as fast (0.0833) when ToxicityDeathHours is 6")
currentSquareIsOutside = true

-- Case B: DeathHours = 24 (Slower build-up: +1/24 = 0.0417 per hour)
if lwfOpts and lwfOpts:getOption("ToxicityDeathHours") then
    lwfOpts:getOption("ToxicityDeathHours"):setValue(24)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = { ToxicFogEnabled = true, ToxicityDeathHours = 24 }

mockModDataVal.fogToxicity = 0.0
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(math.abs(mockModDataVal.fogToxicity - 0.0417) < 0.001, "Toxicity increases twice as slow (0.0417) when ToxicityDeathHours is 24")

-- Restore
if lwfOpts and lwfOpts:getOption("ToxicityDeathHours") then
    lwfOpts:getOption("ToxicityDeathHours"):setValue(12)
end
LivingWorldFramework.ServerConfigs["TheFogDescend"] = nil

-- TEST: Health damage application at different toxicity levels
-- Case A: fogToxicity <= 0.1 (No damage)
currentSquareIsOutside = false -- Safe inside, toxicity will recover/stay low
mockModDataVal.fogToxicity = 0.05
mockBodyDamage.health = 100.0
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockBodyDamage.health, 100.0, "No health damage applied when toxicity is <= 0.1")
currentSquareIsOutside = true

-- Case B: fogToxicity = 0.5 (Linear scaling damage)
mockModDataVal.fogToxicity = 0.5
mockBodyDamage.health = 100.0
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(mockBodyDamage.health < 100.0, "Health damage applied when toxicity is 0.5")
local updatedToxicity = 0.5 + 1.0 / 12
local scale = (updatedToxicity - 0.1) / 0.9
local expectedDamage = 1.0 * (100.0 / (12 * 0.9)) * scale * 2
assertTrue(math.abs((100.0 - mockBodyDamage.health) - expectedDamage) < 0.01, "Health damage is scaled correctly according to linear formula")

-- Case C: fogToxicity >= 1.0 (Instant death / full reduction)
mockModDataVal.fogToxicity = 1.0
mockBodyDamage.health = 100.0
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockBodyDamage.health, 0.0, "Instant death occurs when toxicity is 1.0")

-- TEST: Coughing effect (chance, player text, sound trigger)
-- Set up global addSound mock
local addSoundCalled = false
local addSoundArgs = {}
_G.addSound = function(player, x, y, z, val1, val2)
    addSoundCalled = true
    addSoundArgs = { player = player, x = x, y = y, z = z, val1 = val1, val2 = val2 }
end

-- Case A: toxicity <= 0.05 (no cough)
mockModDataVal.fogToxicity = 0.01
local originalSay = mockPlayerObj.Say
local sayCalled = false
mockPlayerObj.Say = function(self, text)
    sayCalled = true
end
TestHelpers.setMockRandomFloat(0.0) -- make roll always succeed if checked
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(12.05) -- dt = 0.05, updated toxicity = 0.01 + 0.05/12 = 0.014 <= 0.05
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertFalse(sayCalled, "Player does not cough when toxicity is <= 0.05")
assertFalse(addSoundCalled, "No sound added when toxicity is <= 0.05")

-- Case B: toxicity > 0.05 but roll fails (no cough)
mockModDataVal.fogToxicity = 0.5
sayCalled = false
addSoundCalled = false
-- dt * 1.2 = 1 * 1.2 = 1.2. If roll is 2.0 (>= 1.2), it fails.
TestHelpers.setMockRandomFloat(2.0)
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertFalse(sayCalled, "Player does not cough when random roll is too high")
assertFalse(addSoundCalled, "No sound added when random roll is too high")

-- Case C: toxicity > 0.5 and roll succeeds (cough triggers)
sayCalled = false
addSoundCalled = false
local sayText = ""
mockPlayerObj.Say = function(self, text)
    sayCalled = true
    sayText = text
end
-- dt * 1.2 = 1.2. Random float 0.5 is < 1.2, so it succeeds.
TestHelpers.setMockRandomFloat(0.5)
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(13)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertTrue(sayCalled, "Player coughs when toxicity > 0.05 and random roll succeeds")
assertEquals(sayText, "*Cough* *Wheeze*", "Player says coughing text")
assertTrue(addSoundCalled, "addSound is called when player coughs")
assertEquals(addSoundArgs.x, 100, "addSound correct X coord")
assertEquals(addSoundArgs.val1, 15, "addSound correct volume/radius")

-- Restore mocks
mockPlayerObj.Say = originalSay
_G.addSound = nil
TestHelpers.setMockRandomFloat(nil)


-- TEST: Bypassing toxicity update on negative or extremely large time jumps
mockModDataVal.fogToxicity = 0.5
Events.OnGameStart.callback()
getGameTime():setHour(12)
Events.OnPlayerUpdate.callback(mockPlayerObj)
getGameTime():setHour(12) -- 0 hours advanced (dt <= 0)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockModDataVal.fogToxicity, 0.5, "Toxicity remains unchanged when dt is 0")

getGameTime():setNightsSurvived(getGameTime():getNightsSurvived() + 2) -- Large jump (dt > 24)
Events.OnPlayerUpdate.callback(mockPlayerObj)
assertEquals(mockModDataVal.fogToxicity, 0.5, "Toxicity remains unchanged when dt is greater than 24 hours")

-- Clean up mock values
mockPlayerObj.isLocalPlayer = nil
mockPlayerObj.isAlive = nil
mockPlayerObj.getModData = nil
mockPlayerObj.getCurrentSquare = nil
mockPlayerObj.getWornItems = nil
mockPlayerObj.getBodyDamage = nil
mockPlayerObj.getStats = nil
mockPlayerObj.isGodMod = nil
mockPlayerObj.getX = nil
mockPlayerObj.getY = nil
mockPlayerObj.getZ = nil

print("-------------------------------------------------")
print("TEST 20: Configuration Presets")
print("-------------------------------------------------")
TestHelpers.resetModData()
Events.OnInitWorld.callback()

local group = PZAPI.ModOptions:getOptions("TheFogDescend")
assertTrue(group ~= nil, "TheFogDescend options group registered")

-- 1. Assert default preset is Normal
assertEquals(group:getOption("Preset"):getValue(), 1, "Default preset raw value is index 1")
assertEquals(LivingWorldFramework.GetConfig("TheFogDescend", "Preset"), "Normal", "Default preset resolved is 'Normal'")
assertEquals(group:getOption("MinTimeUntilFirstTrigger"):getValue(), 5, "Default MinTimeUntilFirstTrigger is 5")
assertEquals(group:getOption("ToxicityDeathHours"):getValue(), 12, "Default ToxicityDeathHours is 12")
assertEquals(group:getOption("PlaySiren"):getValue(), true, "Default PlaySiren is true")
assertEquals(group:getOption("MakeSprinters"):getValue(), true, "Default MakeSprinters is true")
assertEquals(group:getOption("MakeAggressive"):getValue(), true, "Default MakeAggressive is true")

-- 2. Select Hardcore preset and verify updates
group:getOption("Preset"):setValue("Hardcore")
assertEquals(group:getOption("Preset"):getValue(), 2, "Preset updated to index 2 (Hardcore)")
assertEquals(LivingWorldFramework.GetConfig("TheFogDescend", "Preset"), "Hardcore", "Preset resolved is 'Hardcore'")
assertEquals(group:getOption("MinTimeUntilFirstTrigger"):getValue(), 2, "Hardcore MinTimeUntilFirstTrigger is 2")
assertEquals(group:getOption("ToxicityDeathHours"):getValue(), 6, "Hardcore ToxicityDeathHours is 6")
assertEquals(group:getOption("PlaySiren"):getValue(), true, "Hardcore PlaySiren is true")
assertEquals(group:getOption("MakeSprinters"):getValue(), true, "Hardcore MakeSprinters is true")

-- 3. Modify a slider manually and check if preset becomes Custom
group:getOption("ToxicityDeathHours"):setValue(8)
assertEquals(group:getOption("Preset"):getValue(), 3, "Modifying slider switches preset raw index to 3")
assertEquals(LivingWorldFramework.GetConfig("TheFogDescend", "Preset"), "Custom", "Modifying slider switches preset resolved to 'Custom'")

-- 4. Modify a tickbox manually and check if preset becomes Custom
group:getOption("Preset"):setValue("Normal")
group:getOption("PlaySiren"):setValue(false)
assertEquals(group:getOption("Preset"):getValue(), 3, "Modifying tickbox switches preset raw index to 3")
assertEquals(LivingWorldFramework.GetConfig("TheFogDescend", "Preset"), "Custom", "Modifying tickbox switches preset resolved to 'Custom'")

-- 5. Modify a zombie option manually and check if preset becomes Custom
group:getOption("Preset"):setValue("Normal")
group:getOption("MakeSprinters"):setValue(false)
assertEquals(group:getOption("Preset"):getValue(), 3, "Modifying zombie option switches preset raw index to 3")
assertEquals(LivingWorldFramework.GetConfig("TheFogDescend", "Preset"), "Custom", "Modifying zombie option switches preset resolved to 'Custom'")

print("-------------------------------------------------")
print("TEST 21: Multiplayer Command Permissions & Sandbox Syncing")
print("-------------------------------------------------")
TestHelpers.resetModData()
local originalIsServer = isServer
isServer = function() return true end -- Mock server context

-- 1. Verify SandboxVars updates are broadcast from server
local serverCommandsSent = {}
local originalSendServerCommand = sendServerCommand
sendServerCommand = function(a, b, c, d)
    if type(a) == "table" then
        table.insert(serverCommandsSent, { player = a, module = b, command = c, args = d })
    else
        table.insert(serverCommandsSent, { module = a, command = b, args = c })
    end
    originalSendServerCommand(a, b, c, d)
end

LivingWorldFramework.PushModifier("TestEvent", "ZombieLore.Speed", 1)

local foundSyncCommand = false
for _, cmd in ipairs(serverCommandsSent) do
    if cmd.module == "LivingWorldFramework" and cmd.command == "syncSandboxVar" and cmd.args.path == "ZombieLore.Speed" and cmd.args.value == 1 then
        foundSyncCommand = true
    end
end
assertTrue(foundSyncCommand, "Server broadcasts SandboxVar update to clients")

-- Clean up server mock variables
sendServerCommand = originalSendServerCommand
isServer = originalIsServer

-- 2. Verify Client applies syncSandboxVar commands to local SandboxVars
SandboxVars.ZombieLore.Speed = 2 -- Reset to Shamblers
Events.OnServerCommand.callback("LivingWorldFramework", "syncSandboxVar", { path = "ZombieLore.Speed", value = 3 })
assertEquals(SandboxVars.ZombieLore.Speed, 3, "Client SandboxVars updated via syncSandboxVar command")

-- 3. Verify Server restricts debugTrigger and debugStop to Admin role
isServer = function() return true end -- Mock server context
local originalIsClient = isClient
isClient = function() return false end
local originalGetOnlinePlayers = getOnlinePlayers
getOnlinePlayers = function()
    return {
        size = function() return 2 end,
        get = function(self, idx) return nil end
    }
end

local nonAdmin = { getUsername = function() return "Griefer" end, getAccessLevel = function() return "None" end }
local admin = { getUsername = function() return "AdminUser" end, getAccessLevel = function() return "Admin" end }

-- Try triggering event with non-admin
TestHelpers.resetModData()
Events.OnClientCommand.callback("LivingWorldFramework", "debugTrigger", nonAdmin, { eventId = "TheFogDescend" })
local serverModData = ModData.get("LivingWorldFramework")
assertFalse(serverModData.activeEventId == "TheFogDescend", "Non-admin player is rejected from triggering event")

-- Try triggering event with admin
Events.OnClientCommand.callback("LivingWorldFramework", "debugTrigger", admin, { eventId = "TheFogDescend" })
assertTrue(serverModData.activeEventId == "TheFogDescend", "Admin player is permitted to trigger event")

-- Try stopping event with non-admin
Events.OnClientCommand.callback("LivingWorldFramework", "debugStop", nonAdmin, {})
assertTrue(serverModData.activeEventId == "TheFogDescend", "Non-admin player is rejected from stopping event")

-- Try stopping event with admin
Events.OnClientCommand.callback("LivingWorldFramework", "debugStop", admin, {})
assertFalse(serverModData.activeEventId == "TheFogDescend", "Admin player is permitted to stop event")

-- Clean up mocks
isServer = originalIsServer
isClient = originalIsClient
getOnlinePlayers = originalGetOnlinePlayers

print("-------------------------------------------------")
print("TEST 22: Event Rescheduling on Configuration Change")
print("-------------------------------------------------")
TestHelpers.resetModData()
local originalIsServer = isServer
isServer = function() return true end -- Mock server context
local originalIsClient = isClient
isClient = function() return false end
local originalGetOnlinePlayers = getOnlinePlayers
getOnlinePlayers = function()
    return {
        size = function() return 2 end,
        get = function(self, idx) return nil end
    }
end

-- Initialize first run schedule
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

local serverModData = ModData.get("LivingWorldFramework")
local state = serverModData.eventStates["TheFogDescend"]
local initialScheduledDay = state.scheduledStartDay
assertTrue(initialScheduledDay ~= nil, "Initial schedule was generated")

-- Sync identical config (should NOT reschedule)
local adminUser = { getUsername = function() return "AdminUser" end, getAccessLevel = function() return "Admin" end }
local identicalConfigs = {
    TheFogDescend = {
        MinTimeUntilFirstTrigger = 5,
        MaxTimeUntilFirstTrigger = 5,
        MinCooldown = 5,
        MaxCooldown = 5,
        TriggerChance = 0.20
    }
}
Events.OnClientCommand.callback("LivingWorldFramework", "syncConfig", adminUser, { configs = identicalConfigs })
assertEquals(state.scheduledStartDay, initialScheduledDay, "Identical configuration does not trigger rescheduling")

-- Sync updated config (should reschedule)
local updatedConfigs = {
    TheFogDescend = {
        MinTimeUntilFirstTrigger = 20,
        MaxTimeUntilFirstTrigger = 30,
        MinCooldown = 20,
        MaxCooldown = 30,
        TriggerChance = 0.50
    }
}
Events.OnClientCommand.callback("LivingWorldFramework", "syncConfig", adminUser, { configs = updatedConfigs })
assertTrue(state.scheduledStartDay >= 20, "Updated scheduling configurations correctly triggers rescheduling")

-- Clean up mocks
isServer = originalIsServer
isClient = originalIsClient
getOnlinePlayers = originalGetOnlinePlayers

print("-------------------------------------------------")
print("ALL TESTS PASSED SUCCESSFULLY!")
print("-------------------------------------------------")

