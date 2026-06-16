# LivingWorldFramework (LWF) - Developer Guide

`LivingWorldFramework` is a centralized coordination API and scheduling framework for Project Zomboid Build 42 mods. It acts as an authoritative mediator between game globals (like `SandboxVars` and `ClimateManager`) and custom event mods to ensure multiple environmental or zombie-altering events can coexist and execute without conflicting or clobbering each other.

## Published Steam Workshop Items

* **Living World Framework (Core)**: [Steam Workshop Page](https://steamcommunity.com/sharedfiles/filedetails/?id=3740241984)
* **The Fog Descend**: [Steam Workshop Page](https://steamcommunity.com/sharedfiles/filedetails/?id=3740242544)
* **Cold Snap (Reference Mod)**: [Steam Workshop Page](https://steamcommunity.com/sharedfiles/filedetails/?id=3740249961)

---

## Key Capabilities

1. **Priority Preemptive Scheduling**: Allows high-priority exclusive events to gracefully preempt and pause lower-priority events.
2. **Sandbox Modifier Stacking**: Replaces destructive `SandboxVars` global assignment with a priority-sorted stack. When an event stops, the variable falls back to the next highest-priority active event, or cleanly restores the vanilla sandbox settings if the stack is empty.
3. **Climate Override Blending**: Combines weather and atmosphere floats (e.g., fog density, overcast clouds, desaturation) by taking the maximum density override of all active events to prevent visual fighting.
4. **Coalesced Zombie Updates**: Throttles expensive cell-wide zombie reload loops (`DoZombieStats()`) to a single consolidated loop per tick, eliminating frame spikes when multiple mods update attributes simultaneously.

---

## 1. Registering an Event

Create a shared file in your mod's directory (e.g. `media/lua/shared/MyCustomEvent.lua`) to register your event structure.

```lua
LivingWorldFramework = LivingWorldFramework or {}

local eventDef = {
    id = "MyCustomStorm",
    name = "The Great Storm",
    priority = 10,                 -- Higher priority wins on conflicts/preemption
    exclusivity = "Exclusive",      -- "Exclusive" or "Coexist"
}

LivingWorldFramework.RegisterEvent(eventDef)
```

### Event Configuration Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `id` | `string` | *Required* | A unique identifier for your event. |
| `name` | `string` | `id` | A descriptive name for the event. |
| `priority` | `number` | `0` | Determines event hierarchy during overlaps and preemption checks. |
| `exclusivity` | `string` | `"Exclusive"` | `Exclusive`: Only one exclusive event can run. A higher priority event triggers preemption of the active lower priority event. <br>`Coexist`: Multiple coexisting events can run alongside exclusive and other coexisting events. |

---

## 2. Server Event Implementation

Implement your event lifecycle callbacks in a server file (e.g. `media/lua/server/MyCustomEvent_Server.lua`).

```lua
if isClient() and not isServer() then return end

LivingWorldFramework = LivingWorldFramework or {}
local eventDef = LivingWorldFramework.events["MyCustomStorm"]
if not eventDef then return end

-- ClimateFloat indices (confirmed from vanilla ISAdmPanelClimate.lua)
local FLOAT_DESATURATION = 0
local FLOAT_FOG_INTENSITY = 5
local FLOAT_CLOUD_INTENSITY = 8

-- Determines if the event should naturally start via the scheduler
eventDef.canTrigger = function(gameTime, state)
    local nightsSurvived = gameTime:getNightsSurvived()
    local lastDay = state.lastTriggeredDay or 0
    return (nightsSurvived - lastDay) >= 7 -- Trigger every 7 days
end

-- Returns how long the event runs (in hours)
eventDef.getDuration = function()
    return 12 -- 12 hour storm
end

-- Event triggered: Apply modifications
eventDef.onStart = function(state)
    state.lastTriggeredDay = getGameTime():getNightsSurvived()
    print("MyCustomStorm is starting!")
    
    local priority = eventDef.priority or 0

    -- 1. Push Sandbox modifications (automatically stacked and sorted)
    -- Speed: 1=Sprinters, 2=Fast Shamblers, 3=Shamblers
    LivingWorldFramework.PushModifier("MyCustomStorm", "ZombieLore.Speed", 1, priority)
    LivingWorldFramework.PushModifier("MyCustomStorm", "ZombieLore.Sight", 1, priority) -- Eagle Sight

    -- 2. Set Climate overrides (automatically max-blended with other events)
    LivingWorldFramework.SetClimateOverride("MyCustomStorm", FLOAT_CLOUD_INTENSITY, 1.0) -- Full storm clouds
    LivingWorldFramework.SetClimateOverride("MyCustomStorm", FLOAT_DESATURATION, 0.70)    -- Bleak visual tone

    -- 3. Queue a coalesced zombie refresh across the active loaded cell
    LivingWorldFramework.RequestZombieRefresh()
end

-- Tick callback: Called every in-game hour
eventDef.onUpdate = function(state, dt)
    -- Safe way to keep zombies refreshed if new chunks/zombies load
    LivingWorldFramework.RequestZombieRefresh()
end

-- Event finished or preempted: Clean up modifications
eventDef.onStop = function(state)
    print("MyCustomStorm is stopping!")

    -- 1. Pop sandbox modifiers (falls back to next active event or vanilla values)
    LivingWorldFramework.PopModifier("MyCustomStorm", "ZombieLore.Speed")
    LivingWorldFramework.PopModifier("MyCustomStorm", "ZombieLore.Sight")

    -- 2. Clear climate overrides
    LivingWorldFramework.ClearClimateOverride("MyCustomStorm", FLOAT_CLOUD_INTENSITY)
    LivingWorldFramework.ClearClimateOverride("MyCustomStorm", FLOAT_DESATURATION)

    -- 3. Queue final zombie refresh to restore vanilla stats
    LivingWorldFramework.RequestZombieRefresh()
end
```

---

## 3. Core API Reference

### Stacking API

```lua
LivingWorldFramework.PushModifier(eventId, path, value, priority)
```
Pushes a Sandbox variable value onto the stack.
* `eventId`: (string) Your registered event ID.
* `path`: (string) Dot-separated path to Sandbox option (e.g. `"ZombieLore.Speed"`).
* `value`: (any) The value to set (e.g. `1` for sprinters).
* `priority`: (number) Sorting priority (typically matching your event priority).

```lua
LivingWorldFramework.PopModifier(eventId, path)
```
Removes your event's modifier for the specified sandbox option path. Re-evaluates active modifiers or restores the true vanilla value if the stack is now empty.

---

### Climate API

```lua
LivingWorldFramework.SetClimateOverride(eventId, floatId, value)
```
Applies an admin climate float override.
* `eventId`: (string) Your registered event ID.
* `floatId`: (number) ClimateManager float index. Common indices:
  * `0`: Desaturation (Color desaturation level, `0.0` - `1.0`)
  * `5`: Fog Intensity (`0.0` - `1.0`)
  * `8`: Cloud Intensity (`0.0` - `1.0`)
* `value`: (number) Override value. LWF evaluates all active overrides on this float index and applies the **maximum** value.

```lua
LivingWorldFramework.ClearClimateOverride(eventId, floatId)
```
Removes your override value for the climate float index. Relinquishes admin control of the float index once all active overrides for it are cleared.

---

### Performance API

```lua
LivingWorldFramework.RequestZombieRefresh()
```
Flags the framework to execute a cell-wide zombie refresh. LWF coalesces all update requests made during the tick into a **single, unified cell iteration** at the end of the update frame, preventing severe framerate spikes.

---

## 4. Predetermined Scheduling & Forecast Warnings

To maximize CPU efficiency and allow for immersive, multi-day weather forecast alerts on the Emergency Broadcast System (AEBS) radio channel, LWF uses a **predetermined schedule model**. 

Instead of rolling probabilities and checks every hour, the next start day, hour, and duration are pre-calculated and stored in persistent `ModData` immediately upon the completion (or registration) of an event.

### 4.1 How Scheduling Works

1. **Trigger Time Predetermination**:
   When an event stops, LWF rolls the cooldown days (using `MinCooldown`/`MaxCooldown`). If the event uses a `TriggerChance` less than 1.0 (e.g., a daily 20% trigger probability), LWF simulates forward daily probability rolls in a loop until a success occurs, adding a day of delay for each simulated failure. This predetermines the target start day instantly.
2. **Start Hour & Duration**:
   LWF rolls the start hour (satisfying `OnlyNight`/`OnlyDay` constraints) and pre-rolls the duration of the next active run.
3. **Execution**:
   LWF compiles these into a single absolute timestamp:
   `state.scheduledStartTotalHours = state.scheduledStartDay * 24 + state.scheduledStartHour`
   Hourly checks perform a cheap comparison: `currentTotalHours >= state.scheduledStartTotalHours`. While waiting, this consumes virtually zero CPU time.
4. **Condition Buffering**:
   Once the scheduled start time is reached, if conditions are blocked (e.g., `OnlyRain` is set but it is not raining, or a higher priority exclusive event is running), the event buffers. It remains scheduled and checks again each hour until conditions clear, rather than canceling or rolling again.

### 4.2 Scheduling Defaults in Event Definitions

Add default scheduling and radio properties directly inside your shared event registration:

```lua
local eventDef = {
    id = "TheFogDescend",
    name = "The Fog Descend",
    
    -- Default scheduling limits (overridden by server configurations/Mod Options)
    defaultMinTimeUntilFirstTrigger = 5,
    defaultMaxTimeUntilFirstTrigger = 5,
    defaultMinDuration = 24,
    defaultMaxDuration = 24,
    defaultMinCooldown = 5,
    defaultMaxCooldown = 5,
    defaultTriggerChance = 0.2,
    
    -- Radio Broadcast Forecast Configuration
    radioWarning = {
        leadHours = 24, -- Start broadcasting warnings 24 hours (1 day) before the scheduled start
        message = "~~ WEATHER ALERT ~~ REGIONAL DENSE FOG ADVISORY. EXTREME VISIBILITY REDUCTION INCOMING.",
        color = { r = 1.0, g = 0.3, b = 0.3 }
    },
    defaultShowRadioWarnings = true,
    defaultShowCharacterVoice = false,
    
    -- Expose scheduling options to native Mod Options menu
    exposeTimeUntilFirstTrigger = true,
    exposeDuration = true,
    exposeCooldown = true,
    exposeTriggerChance = true,
    exposeTimeOfDay = false,
}
```

### 4.3 Inspecting Scheduled State

Event scripts or extensions can query the following persistent variables in their `state` tables:
* `state.scheduledStartDay`: (number) The target in-game day (nights survived) for the next run.
* `state.scheduledStartHour`: (number) The target hour for the next run (0-23).
* `state.scheduledStartTotalHours`: (number) The absolute hour timestamp for the next run (`scheduledStartDay * 24 + scheduledStartHour`).
* `state.activeDuration`: (number) The pre-rolled duration of the next run in hours.
* `state.actualEndTotalHours`: (number) The absolute hour timestamp when the currently active run will finish (`triggerTotalHours + activeDuration`).
