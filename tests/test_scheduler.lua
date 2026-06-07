-- Unit Test Suite for LivingWorldFramework and TheFogDescend

-- Set up package path to include the current workspace directory
package.path = package.path .. ";./?.lua"

-- Save original math.random
local originalMathRandom = math.random
local mockRandomFloat = nil
local mockRandomInt = nil

math.random = function(a, b)
    if not a and not b then
        if mockRandomFloat then return mockRandomFloat end
        return originalMathRandom()
    end
    if mockRandomInt then return mockRandomInt end
    return originalMathRandom(a, b)
end

-- Load mock environment
require("tests/mocks/zomboid_mock")

-- Load Core Framework files
require("LivingWorldFramework/42/media/lua/shared/LivingWorldFramework")
require("LivingWorldFramework/42/media/lua/server/LivingWorldFramework_Server")
require("LivingWorldFramework/42/media/lua/client/LivingWorldFramework_Client")

-- Load TheFogDescend Mod files
require("TheFogDescend/42/media/lua/shared/TheFogDescend")
require("TheFogDescend/42/media/lua/server/TheFogDescend_Server")
require("TheFogDescend/42/media/lua/client/TheFogDescend_Client")

-- Load ColdSnap Mod files
require("ColdSnap/42/media/lua/shared/ColdSnap")
require("ColdSnap/42/media/lua/server/ColdSnap_Server")

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
Events.OnGameStart.callback()

-- Force TriggerChance to 1.0 for test events so scheduling checks are deterministic
local fogOpts = PZAPI.ModOptions:getOptions("TheFogDescend")
if fogOpts and fogOpts:getOption("TriggerChance") then
    fogOpts:getOption("TriggerChance"):setValue(1.0)
end
local csOpts = PZAPI.ModOptions:getOptions("ColdSnap")
if csOpts and csOpts:getOption("TriggerChance") then
    csOpts:getOption("TriggerChance"):setValue(1.0)
end


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
assertEquals(modData.eventStates["TheFogDescend"].targetFirstTriggerDay, 5, "First trigger day target initialized to 5")

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
-- Event runs for 24 hours. Let's tick 23 times (event should still be active).
for i = 1, 23 do
    Events.EveryHours.callback()
end
assertEquals(modData.activeEventId, "TheFogDescend", "Event remains active at hour 23")
assertEquals(SandboxVars.ZombieLore.Speed, 1, "Zombies are still sprinters")

-- Tick 24th hour (event should finish and restore settings).
Events.EveryHours.callback()
assertEquals(modData.activeEventId, nil, "Event stopped after 24 hours")
assertEquals(SandboxVars.ZombieLore.Speed, 2, "Zombies speed restored to normal (2)")
assertEquals(modData.eventStates["TheFogDescend"].targetNextTriggerDay, 10, "Next trigger day target set to 10 (current 5 + cooldown 5)")
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
LivingWorldFramework.ServerConfigs = {}

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

-- Assert the bad config was rejected and server falls back to schema default (24)
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
serverModData.eventStates["WeatherEvent"].targetFirstTriggerDay = 2

-- Set nights survived to 2 (cooldown/first trigger matches)
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
serverModData.eventStates["NightEvent"].targetFirstTriggerDay = 2
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
    defaultTriggerChance = 0.5
}
LivingWorldFramework.RegisterEvent(chanceEvent)

-- Initialize it
TestHelpers.resetModData()
getGameTime():setNightsSurvived(0)
Events.OnInitWorld.callback()
Events.OnGameStart.callback()

local serverModData = ModData.get("LivingWorldFramework")
serverModData.eventStates["ChanceEvent"].targetFirstTriggerDay = 2
getGameTime():setNightsSurvived(2)

-- First roll: fail the chance check (mock random to return 0.8 > 0.5)
mockRandomFloat = 0.8
Events.EveryHours.callback()
assertFalse(serverModData.coexistingEvents["ChanceEvent"], "ChanceEvent does not trigger on failed probability roll")
assertEquals(serverModData.eventStates["ChanceEvent"].targetNextTriggerDay, 3, "Failed roll sets targetNextTriggerDay to tomorrow (day 3)")

-- Verify that we don't roll again on day 2 even if random becomes favorable
mockRandomFloat = 0.1
Events.EveryHours.callback()
assertFalse(serverModData.coexistingEvents["ChanceEvent"], "ChanceEvent still does not trigger on day 2 because lastRollDay = 2")

-- Move to day 3
getGameTime():setNightsSurvived(3)
-- Second roll: succeed the chance check (mock random to return 0.1 <= 0.5)
mockRandomFloat = 0.1
Events.EveryHours.callback()
assertTrue(serverModData.coexistingEvents["ChanceEvent"] or false, "ChanceEvent triggers on day 3 with successful probability roll")

-- Stop it
LivingWorldFramework.ServerStopEvent("ChanceEvent")

-- Clean up random mocks
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

-- Let's set ColdSnap to fail the first trigger check
getGameTime():setNightsSurvived(1)
local sModData = ModData.get("LivingWorldFramework")
sModData.eventStates["ColdSnap"] = { targetFirstTriggerDay = 5 }

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
    if string.find(log, "ColdSnap") and string.find(log, "trigger check failed: nights survived") then
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

sModData = ModData.get("LivingWorldFramework")
sModData.eventStates["ColdSnap"] = { targetFirstTriggerDay = 5 }

printLog = {}
print = function(str)
    table.insert(printLog, str)
end

Events.EveryHours.callback()

print = originalPrint

foundLog = false
for _, log in ipairs(printLog) do
    if string.find(log, "ColdSnap") and string.find(log, "trigger check failed: nights survived") then
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

LivingWorldFramework.ServerTriggerEvent("TheFogDescend")

local soundCalls = TestHelpers.getSoundCalls()
assertEquals(#soundCalls, 1, "One sound call triggered in singleplayer")
assertEquals(soundCalls[1].name, "TheFogDescend_Siren", "Played the correct siren sound in singleplayer")
assertEquals(soundCalls[1].loop, false, "Sound loop is false")
assertEquals(soundCalls[1].volume, 1.0, "Sound volume is 1.0")

LivingWorldFramework.ServerStopEvent("TheFogDescend")

-- 2. Multiplayer Siren Triggering (isServer() = true)
TestHelpers.resetModData()
TestHelpers.clearSoundCalls()
isServer = function() return true end

LivingWorldFramework.ServerTriggerEvent("TheFogDescend")

soundCalls = TestHelpers.getSoundCalls()
assertEquals(#soundCalls, 1, "One sound call triggered in multiplayer via server-to-client command")
assertEquals(soundCalls[1].name, "TheFogDescend_Siren", "Played the correct siren sound in multiplayer")

-- Clean up
isServer = originalIsServer
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
print("ALL TESTS PASSED SUCCESSFULLY!")
print("-------------------------------------------------")
