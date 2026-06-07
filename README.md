# LivingWorldFramework (LWF) - Developer Guide

`LivingWorldFramework` is a centralized coordination API and scheduling framework for Project Zomboid Build 42 mods. It acts as an authoritative mediator between game globals (like `SandboxVars` and `ClimateManager`) and custom event mods to ensure multiple environmental or zombie-altering events can coexist and execute without conflicting or clobbering each other.

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
