-- Project Zomboid Lua environment mock for unit testing

-- Mock Global Functions
isClient = function() return false end
isServer = function() return false end
isDebugEnabled = function() return true end

local mockRandFloatVal = nil
ZombRandFloat = function(min, max)
    if mockRandFloatVal then return mockRandFloatVal end
    return math.random() * (max - min) + min
end

local mockVehicle = nil
local mockPlayerObj = {
    Say = function(self, text) print("  [MOCK SAY] " .. tostring(text)) end,
    getVehicle = function(self) return mockVehicle end
}
getPlayer = function(id)
    return mockPlayerObj
end
getOnlinePlayers = function()
    local list = {
        size = function() return 1 end,
        get = function(self, idx) return nil end
    }
    return list
end
sendClientCommand = function(module, command, args)
    if module == "vehicle" and command == "shutOff" then
        if mockVehicle then
            mockVehicle:shutOff()
        end
    end
    if Events.OnClientCommand and Events.OnClientCommand.callback then
        local mockPlayer = {
            getUsername = function() return "LocalHost" end,
            getAccessLevel = function() return "Admin" end
        }
        Events.OnClientCommand.callback(module, command, mockPlayer, args)
    end
end

sendServerCommand = function(module, command, args)
    if Events.OnServerCommand and Events.OnServerCommand.callback then
        Events.OnServerCommand.callback(module, command, args)
    end
end


-- Mock Events
local function createMockEvent()
    local ev = { listeners = {} }
    ev.Add = function(func)
        table.insert(ev.listeners, func)
    end
    ev.callback = function(...)
        for _, listener in ipairs(ev.listeners) do
            listener(...)
        end
    end
    return ev
end

Events = {
    OnInitWorld = createMockEvent(),
    OnGameStart = createMockEvent(),
    EveryHours = createMockEvent(),
    EveryOneMinute = createMockEvent(),
    OnClientCommand = createMockEvent(),
    OnServerCommand = createMockEvent(),
    OnFillWorldObjectContextMenu = createMockEvent(),
    OnLoadRadioScripts = createMockEvent()
}

-- Mock Radio Classes
RadioLine = {}
RadioLine.new = function(text, r, g, b)
    return { text = text, r = r, g = g, b = b }
end

RadioBroadCast = {}
RadioBroadCast.new = function(id, a, b)
    local bc = { id = id, lines = {} }
    bc.AddRadioLine = function(self, line)
        table.insert(self.lines, line)
    end
    return bc
end

-- Mock WeatherChannel
WeatherChannel = {
    CreateBroadcast = function(gameTime)
        return RadioBroadCast.new("MOCK_AEBS", -1, -1)
    end
}

-- Mock SandboxOptions Java class
local mockOptions = {}
local mockOptionMeta = {
    getType = function(self) return self.type end,
    setValue = function(self, val) self.val = val end,
    parse = function(self, str) self.val = tonumber(str) or str end,
    getValue = function(self) return self.val end
}
mockOptionMeta.__index = mockOptionMeta

local function createMockOption(name, type, defaultVal)
    local opt = { name = name, type = type, val = defaultVal }
    setmetatable(opt, mockOptionMeta)
    mockOptions[name] = opt
    return opt
end

createMockOption("ZombieLore.Speed", "integer", 2)
createMockOption("ZombieLore.Sight", "integer", 2)
createMockOption("ZombieLore.Hearing", "integer", 2)
createMockOption("ZombieLore.Cognition", "integer", 2)

local mockSandboxOptionsInstance = {
    getOptionByName = function(self, name)
        return mockOptions[name]
    end,
    getOptionValue = function(self, name)
        return mockOptions[name] and mockOptions[name]:getValue()
    end
}

getSandboxOptions = function()
    return mockSandboxOptionsInstance
end

-- Mock SandboxVars
SandboxVars = {
    ZombieLore = {
        Speed = 2,
        Sight = 2,
        Hearing = 2,
        Cognition = 2
    },
    TheFogDescend = {
        TriggerInterval = 5,
        Duration = 24,
        FogIntensity = 0.90,
        MakeSprinters = true,
        MakeAggressive = true
    }
}

-- Mock ModData
local mockModData = {}
ModData = {
    getOrCreate = function(name)
        mockModData[name] = mockModData[name] or {}
        return mockModData[name]
    end,
    get = function(name)
        return mockModData[name]
    end,
    getTableNames = function()
        local keys = {}
        for k, _ in pairs(mockModData) do
            table.insert(keys, k)
        end
        return keys
    end
}

-- Mock GameTime
local currentNightsSurvived = 0
local currentHour = 12
local mockGameTime = {
    getNightsSurvived = function() return currentNightsSurvived end,
    setNightsSurvived = function(self, val) currentNightsSurvived = val end,
    getHour = function() return currentHour end,
    setHour = function(self, val) currentHour = val end
}
getGameTime = function()
    return mockGameTime
end

-- Mock ClimateManager
local function createMockFloat()
    return {
        enabled = false,
        val = 0.0,
        calculateVal = 0.0,
        setEnableAdmin = function(self, b) self.enabled = b end,
        isEnableAdmin = function(self) return self.enabled end,
        setAdminValue = function(self, v) self.val = v end,
        getAdminValue = function(self) return self.val end,
        get = function(self)
            if self.enabled then return self.val end
            return self.calculateVal
        end
    }
end

local floats = {
    [0] = createMockFloat(), -- desaturation
    [4] = createMockFloat(), -- temperature
    [5] = createMockFloat(), -- fog
    [8] = createMockFloat()  -- clouds
}

local mockClimateManager = {
    raining = false,
    snowing = false,
    isRaining = function(self) return self.raining end,
    isSnowing = function(self) return self.snowing end,
    setRaining = function(self, b) self.raining = b end,
    setSnowing = function(self, b) self.snowing = b end,
    getClimateFloat = function(self, idx)
        floats[idx] = floats[idx] or createMockFloat()
        return floats[idx]
    end,
    transmitClimateParts = function(self) end
}
getClimateManager = function()
    return mockClimateManager
end

-- Mock Zombie and Cell
local activeZombies = {}
local mockZombie = {
    new = function()
        local z = {}
        z.statsRefreshed = 0
        z.speedType = 2 -- default to fast shambler
        z.modData = {}
        z.getModData = function(self) return self.modData end
        z.getSpeedType = function(self) return self.speedType end
        z.DoZombieStats = function(self) self.statsRefreshed = self.statsRefreshed + 1 end
        z.doSprinter = function(self) self.speedType = 1 end
        z.doFastShambler = function(self) self.speedType = 2 end
        z.doShambler = function(self) self.speedType = 3 end
        z.doFakeShambler = function(self) self.speedType = 4 end
        return z
    end
}

local mockCell = {
    getZombieList = function()
        local list = {
            size = function() return #activeZombies end,
            get = function(self, idx) return activeZombies[idx + 1] end
        }
        return list
    end
}
getCell = function()
    return mockCell
end

local mockSoundCalls = {}
getSoundManager = function()
    return {
        PlaySound = function(self, name, loop, volume)
            print("  [MOCK SOUND] PlaySound: " .. tostring(name) .. ", loop: " .. tostring(loop) .. ", volume: " .. tostring(volume))
            table.insert(mockSoundCalls, { name = name, loop = loop, volume = volume })
            return 12345
        end
    }
end

-- Utility to manage test state
TestHelpers = {
    clearZombies = function() activeZombies = {} end,
    addZombie = function()
        local z = mockZombie.new()
        table.insert(activeZombies, z)
        return z
    end,
    getActiveZombies = function() return activeZombies end,
    getClimateFloatState = function(idx) return floats[idx] end,
    resetModData = function()
        mockModData = {}
        mockVehicle = nil
        mockRandFloatVal = nil
        if LivingWorldFramework and LivingWorldFramework.DebugResetState then
            LivingWorldFramework.DebugResetState()
        end
    end,
    getSoundCalls = function() return mockSoundCalls end,
    clearSoundCalls = function() mockSoundCalls = {} end,
    setMockVehicle = function(vehicle) mockVehicle = vehicle end,
    setMockRandomFloat = function(val) mockRandFloatVal = val end,
    createMockVehicle = function()
        local v = {
            driver = nil,
            engineRunning = false,
            stalledCount = 0
        }
        v.getDriver = function(self) return v.driver end
        v.isEngineRunning = function(self) return v.engineRunning end
        v.shutOff = function(self)
            v.engineRunning = false
            v.stalledCount = v.stalledCount + 1
            print("  [MOCK VEHICLE] shutOff called!")
        end
        return v
    end
}

-- Mock PZAPI ModOptions API
PZAPI = PZAPI or {}
PZAPI.ModOptions = PZAPI.ModOptions or {}
PZAPI.ModOptions.Data = {}
PZAPI.ModOptions.Dict = {}

local MockOption = {}
function MockOption:new(id, value)
    local o = { id = id, value = value }
    setmetatable(o, self)
    self.__index = self
    return o
end
function MockOption:getValue()
    return self.value
end
function MockOption:setValue(val)
    self.value = val
end

local MockOptionsGroup = {}
function MockOptionsGroup:new(id)
    local o = { id = id, options = {} }
    setmetatable(o, self)
    self.__index = self
    return o
end
function MockOptionsGroup:getOption(optionId)
    return self.options[optionId]
end
function MockOptionsGroup:addTickBox(id, name, val, tooltip)
    self.options[id] = MockOption:new(id, val)
end
function MockOptionsGroup:addSlider(id, name, min, max, step, val, tooltip)
    self.options[id] = MockOption:new(id, val)
end
function MockOptionsGroup:addTextEntry(id, name, val, tooltip)
    self.options[id] = MockOption:new(id, val)
end
function MockOptionsGroup:addButton(id, name, tooltip, onclickfunc, target, arg1, arg2, arg3, arg4)
    self.options[id] = { type = "button", name = name, onclick = onclickfunc, target = target, args = { arg1, arg2, arg3, arg4 } }
end
function MockOptionsGroup:addSeparator() end
function MockOptionsGroup:addTitle(name) end

function PZAPI.ModOptions:create(modOptionsID, name)
    local g = MockOptionsGroup:new(modOptionsID)
    PZAPI.ModOptions.Dict[modOptionsID] = g
    table.insert(PZAPI.ModOptions.Data, g)
    return g
end

function PZAPI.ModOptions:getOptions(modOptionsID)
    return PZAPI.ModOptions.Dict[modOptionsID]
end

function PZAPI.ModOptions:load() end
function PZAPI.ModOptions:save() end

