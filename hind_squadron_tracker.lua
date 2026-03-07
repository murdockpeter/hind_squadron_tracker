----------------------------------------------------------------------
-- Hind Squadron Persistent State (MVP) + Airframe Slot Enforcement
--
-- Tracks:
--  - 4 airframes
--  - 6 pilots
--  - Supply points (ammo/fuel abstraction)
--  - Damage states: OK, Minor, Major, Destroyed
--  - Fatigue states: Fresh, Tired, Exhausted
--
-- Adds:
--  - Aligns mission client slots to airframes by Group Name:
--      HIND-01, HIND-02, HIND-03, HIND-04
--  - Enforces availability:
--      If airframe Damage is Major or Destroyed, and a player spawns into it,
--      the group is destroyed and a message is shown.
--
-- Requirements:
--  - Load Moose.lua FIRST (via DO SCRIPT FILE)
--  - Then load this file (via DO SCRIPT FILE)
--
-- Mission Editor:
--  - Place 4x Mi-24P groups with Skill=Client
--  - Name the GROUPS exactly: HIND-01..HIND-04
----------------------------------------------------------------------

HIND_SQUADRON = {}

-- Debug: confirm script loads at mission start.
trigger.action.outText("HIND script loaded", 10)

----------------------------------------------------------------------
-- ENUMS / CONSTANTS
----------------------------------------------------------------------

HIND_SQUADRON.DAMAGE = {
  OK = "OK",
  MINOR = "Minor",
  MAJOR = "Major",
  DESTROYED = "Destroyed",
}

HIND_SQUADRON.DAMAGE_COST = {
  Minor = 1,
  Major = 2,
  Destroyed = 0,
  OK = 0,
}

HIND_SQUADRON.FATIGUE = {
  FRESH = "Fresh",
  TIRED = "Tired",
  EXHAUSTED = "Exhausted",
}

HIND_SQUADRON.PILOT_STATUS = {
  ALIVE = "Alive",
  DEAD = "Dead",
}

-- Persistence (Saved Games\DCS by default when lfs is available)
HIND_SQUADRON.StateFileName = "HindSquadronState.lua"
HIND_SQUADRON.StateFilePath = nil

-- Optional pilot roster override (Saved Games\DCS by default when lfs is available)
HIND_SQUADRON.PilotRosterFileName = "HindSquadronPilots.lua"
HIND_SQUADRON.PilotRosterFilePath = nil

----------------------------------------------------------------------
-- INITIAL STATE
----------------------------------------------------------------------

HIND_SQUADRON.DefaultState = {
  Turn = 1,

  -- Abstract “ammo/fuel” into a single campaign resource.
  SupplyPoints = 20,

  -- 4 Airframes: IDs must match DCS GROUP NAMES for slot alignment/enforcement.
  Airframes = {
    { Id = "HIND-01", Damage = "OK", Notes = "" },
    { Id = "HIND-02", Damage = "OK", Notes = "" },
    { Id = "HIND-03", Damage = "OK", Notes = "" },
    { Id = "HIND-04", Damage = "OK", Notes = "" },
  },

  -- 6 Pilots
  Pilots = {
    { Id = "PILOT-01", Name = "Viper",  Fatigue = "Fresh", Status = "Alive", Notes = "" },
    { Id = "PILOT-02", Name = "Bear",   Fatigue = "Fresh", Status = "Alive", Notes = "" },
    { Id = "PILOT-03", Name = "Saber",  Fatigue = "Fresh", Status = "Alive", Notes = "" },
    { Id = "PILOT-04", Name = "Cobalt", Fatigue = "Fresh", Status = "Alive", Notes = "" },
    { Id = "PILOT-05", Name = "Rook",   Fatigue = "Fresh", Status = "Alive", Notes = "" },
    { Id = "PILOT-06", Name = "Mako",   Fatigue = "Fresh", Status = "Alive", Notes = "" },
  },
}

HIND_SQUADRON.State = {}

----------------------------------------------------------------------
-- UTILS
----------------------------------------------------------------------

local function _deepCopy(obj)
  if type(obj) ~= "table" then return obj end
  local res = {}
  for k, v in pairs(obj) do
    res[_deepCopy(k)] = _deepCopy(v)
  end
  return res
end

local function _mergeDefaults(defaults, data)
  if type(defaults) ~= "table" then
    if data ~= nil then return data end
    return defaults
  end

  local result = {}
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      result[k] = _mergeDefaults(v, type(data) == "table" and data[k] or nil)
    else
      if type(data) == "table" and data[k] ~= nil then
        result[k] = data[k]
      else
        result[k] = v
      end
    end
  end

  if type(data) == "table" then
    for k, v in pairs(data) do
      if result[k] == nil then
        result[k] = v
      end
    end
  end

  return result
end

local function _serializeLua(value)
  local t = type(value)
  if t == "number" then
    return tostring(value)
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "table" then
    local parts = {"{"}
    for k, v in pairs(value) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. _serializeLua(k) .. "]"
      end
      parts[#parts + 1] = key .. "=" .. _serializeLua(v) .. ","
    end
    parts[#parts + 1] = "}"
    return table.concat(parts)
  else
    return "nil"
  end
end

local function _isInSet(value, setTable)
  for _, v in pairs(setTable) do
    if v == value then return true end
  end
  return false
end

local function _findById(list, id)
  for i, item in ipairs(list) do
    if item.Id == id then return item, i end
  end
  return nil, nil
end

local function _findPilotByName(list, name)
  if not name then return nil end
  local lname = string.lower(name)
  for _, item in ipairs(list) do
    if string.lower(item.Name) == lname or string.lower(item.Id) == lname then
      return item
    end
  end
  return nil
end

local function _clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

----------------------------------------------------------------------
-- PERSISTENCE
--
-- Requires io + lfs to be de-sanitized in MissionScripting.lua.
-- Uses MOOSE UTILS.SaveToFile/LoadFromFile with default path.
----------------------------------------------------------------------

function HIND_SQUADRON:_GetStateFile()
  return self.StateFilePath, self.StateFileName
end

function HIND_SQUADRON:_WarnPersistOnce(msg)
  if self._PersistWarned then return end
  self._PersistWarned = true
  env.info("HIND_SQUADRON: " .. msg)
end

function HIND_SQUADRON:SaveState()
  if not UTILS or not UTILS.SaveToFile then
    self:_WarnPersistOnce("MOOSE UTILS not available; persistence disabled.")
    return false
  end

  local path, filename = self:_GetStateFile()
  local payload = "return " .. _serializeLua(self.State)
  local ok = UTILS.SaveToFile(path, filename, payload)
  if not ok then
    self:_WarnPersistOnce("Save failed. Ensure io and lfs are desanitized.")
  end
  return ok
end

function HIND_SQUADRON:LoadState()
  if not UTILS or not UTILS.CheckFileExists or not UTILS.LoadFromFile then
    self:_WarnPersistOnce("MOOSE UTILS not available; persistence disabled.")
    return false
  end

  local path, filename = self:_GetStateFile()
  if not UTILS.CheckFileExists(path, filename) then
    return false
  end

  local ok, lines = UTILS.LoadFromFile(path, filename)
  if not ok or not lines then
    self:_WarnPersistOnce("Load failed. Ensure io and lfs are desanitized.")
    return false
  end

  local chunk = table.concat(lines, "\n")
  local loader = loadstring or load
  if not loader then
    self:_WarnPersistOnce("Load failed: no Lua loader available.")
    return false
  end

  local f, err = loader(chunk)
  if not f then
    self:_WarnPersistOnce("Load failed: " .. tostring(err))
    return false
  end

  local data = f()
  if type(data) ~= "table" then
    self:_WarnPersistOnce("Load failed: state file is not a table.")
    return false
  end

  self.State = _mergeDefaults(self.DefaultState, data)
  return true
end

function HIND_SQUADRON:_GetPilotRosterFile()
  return self.PilotRosterFilePath, self.PilotRosterFileName
end

function HIND_SQUADRON:_NormalizePilotRoster(data)
  if type(data) ~= "table" then return nil end

  if type(data.Pilots) == "table" then
    data = data.Pilots
  end

  local roster = {}

  -- Array form: { "Name1", "Name2", ... } or { {Id=..., Name=...}, ... }
  if data[1] ~= nil then
    for i, v in ipairs(data) do
      if type(v) == "string" then
        roster[#roster + 1] = { Id = string.format("PILOT-%02d", i), Name = v }
      elseif type(v) == "table" then
        local id = v.Id or string.format("PILOT-%02d", i)
        local name = v.Name or v[1]
        if type(name) == "string" then
          roster[#roster + 1] = { Id = id, Name = name }
        end
      end
    end
    return roster
  end

  -- Map form: { PILOT-01 = "Name", PILOT-02 = "Name" }
  for k, v in pairs(data) do
    if type(k) == "string" and type(v) == "string" then
      roster[#roster + 1] = { Id = k, Name = v }
    end
  end

  if #roster == 0 then return nil end
  return roster
end

function HIND_SQUADRON:LoadPilotRoster()
  if not UTILS or not UTILS.CheckFileExists or not UTILS.LoadFromFile then
    self:_WarnPersistOnce("MOOSE UTILS not available; pilot roster override disabled.")
    return nil
  end

  local path, filename = self:_GetPilotRosterFile()
  if not UTILS.CheckFileExists(path, filename) then
    return nil
  end

  local ok, lines = UTILS.LoadFromFile(path, filename)
  if not ok or not lines then
    self:_WarnPersistOnce("Pilot roster load failed. Ensure io and lfs are desanitized.")
    return nil
  end

  local chunk = table.concat(lines, "\n")
  local loader = loadstring or load
  if not loader then
    self:_WarnPersistOnce("Pilot roster load failed: no Lua loader available.")
    return nil
  end

  local f, err = loader(chunk)
  if not f then
    self:_WarnPersistOnce("Pilot roster load failed: " .. tostring(err))
    return nil
  end

  local data = f()
  return self:_NormalizePilotRoster(data)
end

function HIND_SQUADRON:ApplyPilotRoster(targetPilots, roster)
  if type(targetPilots) ~= "table" or type(roster) ~= "table" then return false end
  local changed = false
  for i, r in ipairs(roster) do
    if r and r.Name then
      local p = nil
      if r.Id then
        p = _findById(targetPilots, r.Id)
      end
      if not p and targetPilots[i] then
        p = targetPilots[i]
      end
      if p and p.Name ~= r.Name then
        p.Name = r.Name
        changed = true
      end
    end
  end
  return changed
end

----------------------------------------------------------------------
-- CORE: AIRFRAMES
----------------------------------------------------------------------

function HIND_SQUADRON:GetAirframe(id)
  return _findById(self.State.Airframes, id)
end

function HIND_SQUADRON:SetAirframeDamage(id, damage, suppressSave)
  if not _isInSet(damage, self.DAMAGE) then
    env.info(("HIND_SQUADRON: invalid damage '%s'"):format(tostring(damage)))
    return false
  end

  local af = self:GetAirframe(id)
  if not af then
    env.info(("HIND_SQUADRON: airframe not found '%s'"):format(tostring(id)))
    return false
  end

  af.Damage = damage
  if not suppressSave then self:SaveState() end
  return true
end

function HIND_SQUADRON:IsAirframeFlyable(id)
  local af = self:GetAirframe(id)
  if not af then return false end
  return (af.Damage ~= self.DAMAGE.DESTROYED and af.Damage ~= self.DAMAGE.MAJOR)
end

function HIND_SQUADRON:_WorseDamage(current, incoming)
  local order = {
    [self.DAMAGE.OK] = 0,
    [self.DAMAGE.MINOR] = 1,
    [self.DAMAGE.MAJOR] = 2,
    [self.DAMAGE.DESTROYED] = 3,
  }
  return order[incoming] > (order[current] or 0)
end

----------------------------------------------------------------------
-- CORE: PILOTS
----------------------------------------------------------------------

function HIND_SQUADRON:GetPilot(id)
  return _findById(self.State.Pilots, id)
end

function HIND_SQUADRON:SetPilotFatigue(id, fatigue, suppressSave)
  if not _isInSet(fatigue, self.FATIGUE) then
    env.info(("HIND_SQUADRON: invalid fatigue '%s'"):format(tostring(fatigue)))
    return false
  end

  local p = self:GetPilot(id)
  if not p then
    env.info(("HIND_SQUADRON: pilot not found '%s'"):format(tostring(id)))
    return false
  end

  p.Fatigue = fatigue
  if not suppressSave then self:SaveState() end
  return true
end

function HIND_SQUADRON:SetPilotStatus(id, status, suppressSave)
  if not _isInSet(status, self.PILOT_STATUS) then
    env.info(("HIND_SQUADRON: invalid pilot status '%s'"):format(tostring(status)))
    return false
  end

  local p = self:GetPilot(id)
  if not p then
    env.info(("HIND_SQUADRON: pilot not found '%s'"):format(tostring(id)))
    return false
  end

  p.Status = status
  if not suppressSave then self:SaveState() end
  return true
end

function HIND_SQUADRON:SetPilotDeadByPlayerName(playerName, suppressSave)
  local p = _findPilotByName(self.State.Pilots, playerName)
  if not p then
    env.info(("HIND_SQUADRON: no pilot match for player '%s'"):format(tostring(playerName)))
    return false
  end
  if p.Status == self.PILOT_STATUS.DEAD then return false end
  return self:SetPilotStatus(p.Id, self.PILOT_STATUS.DEAD, suppressSave)
end

function HIND_SQUADRON:SetPilotAlive(id, suppressSave)
  return self:SetPilotStatus(id, self.PILOT_STATUS.ALIVE, suppressSave)
end

-- Simple fatigue progression for “a sortie was flown”
function HIND_SQUADRON:ApplySortieFatigue(pilotId, suppressSave)
  local p = self:GetPilot(pilotId)
  if not p then return false end

  if p.Fatigue == self.FATIGUE.FRESH then
    p.Fatigue = self.FATIGUE.TIRED
  elseif p.Fatigue == self.FATIGUE.TIRED then
    p.Fatigue = self.FATIGUE.EXHAUSTED
  end
  if not suppressSave then self:SaveState() end
  return true
end

function HIND_SQUADRON:ApplySortieFatigueByPlayerName(playerName, suppressSave)
  local p = _findPilotByName(self.State.Pilots, playerName)
  if not p then
    env.info(("HIND_SQUADRON: no pilot match for player '%s'"):format(tostring(playerName)))
    return false
  end
  return self:ApplySortieFatigue(p.Id, suppressSave)
end

-- Simple recovery when advancing turns (sleep/rotation)
function HIND_SQUADRON:RecoverPilotFatigueAll(suppressSave)
  for _, p in ipairs(self.State.Pilots) do
    if p.Fatigue == self.FATIGUE.EXHAUSTED then
      p.Fatigue = self.FATIGUE.TIRED
    elseif p.Fatigue == self.FATIGUE.TIRED then
      p.Fatigue = self.FATIGUE.FRESH
    end
  end
  if not suppressSave then self:SaveState() end
end

----------------------------------------------------------------------
-- CORE: SUPPLY
----------------------------------------------------------------------

function HIND_SQUADRON:AddSupply(points, suppressSave)
  self.State.SupplyPoints = _clamp(self.State.SupplyPoints + points, 0, 999)
  if not suppressSave then self:SaveState() end
end

function HIND_SQUADRON:SpendSupply(points, suppressSave)
  points = math.max(0, points)
  if self.State.SupplyPoints < points then return false end
  self.State.SupplyPoints = self.State.SupplyPoints - points
  if not suppressSave then self:SaveState() end
  return true
end

----------------------------------------------------------------------
-- TURN MANAGEMENT
----------------------------------------------------------------------

-- Call at the end of a campaign “turn”
function HIND_SQUADRON:AdvanceTurn()
  self.State.Turn = self.State.Turn + 1

  -- MVP: fatigue recovery happens between turns.
  self:RecoverPilotFatigueAll(true)

  -- MVP: repair damaged airframes using supply points.
  for _, af in ipairs(self.State.Airframes) do
    if af.Damage == self.DAMAGE.MINOR or af.Damage == self.DAMAGE.MAJOR then
      local cost = self.DAMAGE_COST[af.Damage] or 0
      if self.State.SupplyPoints >= cost then
        self:SpendSupply(cost, true)
        af.Damage = self.DAMAGE.OK
      end
    end
  end

  -- MVP: small resupply drip each turn (tune to taste)
  self:AddSupply(2, true)

  self:SaveState()

  self:Announce(("Turn advanced to %d. Pilots recovered, +2 Supply."):format(self.State.Turn), 10)
end

----------------------------------------------------------------------
-- REPORTING / UI TEXT
----------------------------------------------------------------------

function HIND_SQUADRON:BuildStatusText()
  local s = self.State
  local lines = {}

  table.insert(lines, "HIND SQUADRON STATUS")
  table.insert(lines, ("Turn: %d"):format(s.Turn))
  table.insert(lines, ("Supply Points: %d"):format(s.SupplyPoints))
  table.insert(lines, "")
  table.insert(lines, "Airframes:")
  for _, af in ipairs(s.Airframes) do
    local fly = self:IsAirframeFlyable(af.Id) and "Flyable" or "Down"
    table.insert(lines, ("  %s  | Damage: %-9s | %s"):format(af.Id, af.Damage, fly))
  end
  table.insert(lines, "")
  table.insert(lines, "Pilots:")
  for _, p in ipairs(s.Pilots) do
    local status = p.Status or self.PILOT_STATUS.ALIVE
    local name = p.Name
    if status == self.PILOT_STATUS.DEAD then
      name = name .. " (Dead)"
    end
    table.insert(lines, ("  %s (%s) | Fatigue: %-9s"):format(p.Id, name, p.Fatigue))
  end

  return table.concat(lines, "\n")
end

function HIND_SQUADRON:Announce(text, seconds)
  seconds = seconds or 10
  if MESSAGE then
    MESSAGE:New(text, seconds):ToAll()
  else
    trigger.action.outText(text, seconds)
  end
end

----------------------------------------------------------------------
-- ENFORCEMENT: Prevent players from using unavailable airframes
--
-- When a unit spawns (BIRTH), if its GROUP NAME matches a tracked airframe
-- (HIND-01..HIND-04) and that airframe is "Down" (Major/Destroyed),
-- the group is destroyed immediately and a message is shown.
----------------------------------------------------------------------

HIND_SQUADRON._DcsEventHandler = {}

function HIND_SQUADRON._DcsEventHandler:onEvent(event)
  if not event or not event.id then return end
  if not event.initiator then return end

  local unit = event.initiator
  if not unit.getGroup then return end

  local group = unit:getGroup()
  if not group or not group.getName then return end

  local groupName = group:getName()
  if not groupName then return end

  -- Only enforce/track for our tracked Hinds (group name must match airframe Id)
  local af = HIND_SQUADRON:GetAirframe(groupName)
  if not af then return end

  if event.id == world.event.S_EVENT_BIRTH then
    local down = (af.Damage == HIND_SQUADRON.DAMAGE.DESTROYED) or (af.Damage == HIND_SQUADRON.DAMAGE.MAJOR)
    if down then
      trigger.action.outText(
        ("CAMPAIGN: %s is %s and is unavailable this turn."):format(groupName, af.Damage),
        10
      )
      group:destroy()
    end
    return
  end

  if event.id == world.event.S_EVENT_LAND then
    local playerName = unit.getPlayerName and unit:getPlayerName()
    if playerName then
      HIND_SQUADRON:ApplySortieFatigueByPlayerName(playerName)
    end
    return
  end

  if event.id == world.event.S_EVENT_DEAD
    or event.id == world.event.S_EVENT_CRASH
    or event.id == world.event.S_EVENT_COLLISION
    or event.id == world.event.S_EVENT_PILOT_DEAD
  then
    local playerName = unit.getPlayerName and unit:getPlayerName()
    if playerName then
      HIND_SQUADRON:SetPilotDeadByPlayerName(playerName)
    end
    if HIND_SQUADRON:_WorseDamage(af.Damage, HIND_SQUADRON.DAMAGE.DESTROYED) then
      HIND_SQUADRON:SetAirframeDamage(groupName, HIND_SQUADRON.DAMAGE.DESTROYED)
    end
    return
  end

  if event.id == world.event.S_EVENT_HIT or event.id == world.event.S_EVENT_DAMAGE then
    local life = unit:getLife()
    local life0 = unit:getLife0()
    if life and life0 and life0 > 0 then
      local ratio = life / life0
      local incoming = (ratio <= 0.5) and HIND_SQUADRON.DAMAGE.MAJOR or HIND_SQUADRON.DAMAGE.MINOR
      if HIND_SQUADRON:_WorseDamage(af.Damage, incoming) then
        HIND_SQUADRON:SetAirframeDamage(groupName, incoming)
      end
    else
      if HIND_SQUADRON:_WorseDamage(af.Damage, HIND_SQUADRON.DAMAGE.MINOR) then
        HIND_SQUADRON:SetAirframeDamage(groupName, HIND_SQUADRON.DAMAGE.MINOR)
      end
    end
    return
  end
end

function HIND_SQUADRON:EnableAirframeEnforcement()
  world.addEventHandler(self._DcsEventHandler)
end

----------------------------------------------------------------------
-- SIMPLE F10 MENU (MOOSE)
----------------------------------------------------------------------

function HIND_SQUADRON:InitMenu()
  if not MENU_MISSION then
    trigger.action.outText("HIND_SQUADRON: MOOSE MENU_* not found. Load Moose.lua first.", 15)
    return
  end

  self.MenuRoot = MENU_MISSION:New("Hind Squadron (Campaign)")

  MENU_MISSION_COMMAND:New("Show Squadron Status", self.MenuRoot, function()
    self:Announce(self:BuildStatusText(), 20)
  end)

  MENU_MISSION_COMMAND:New("Advance Turn (Between Sorties)", self.MenuRoot, function()
    self:AdvanceTurn()
  end)

  -- Quick test helpers (safe to delete later)
  MENU_MISSION_COMMAND:New("Spend 3 Supply (Test)", self.MenuRoot, function()
    local ok = self:SpendSupply(3)
    self:Announce(ok and "Spent 3 Supply." or "Not enough Supply!", 8)
  end)

  MENU_MISSION_COMMAND:New("Apply Sortie Fatigue to PILOT-01 (Test)", self.MenuRoot, function()
    self:ApplySortieFatigue("PILOT-01")
    self:Announce("Applied sortie fatigue to PILOT-01.", 8)
  end)

  MENU_MISSION_COMMAND:New("Revive PILOT-01 (Test)", self.MenuRoot, function()
    self:SetPilotAlive("PILOT-01")
    self:Announce("Set PILOT-01 status to Alive.", 8)
  end)

  MENU_MISSION_COMMAND:New("Set HIND-01 Damage -> Minor (Test)", self.MenuRoot, function()
    self:SetAirframeDamage("HIND-01", self.DAMAGE.MINOR)
    self:Announce("Set HIND-01 damage to Minor.", 8)
  end)

  MENU_MISSION_COMMAND:New("Set HIND-01 Damage -> Major (Test)", self.MenuRoot, function()
    self:SetAirframeDamage("HIND-01", self.DAMAGE.MAJOR)
    self:Announce("Set HIND-01 damage to Major (Down). Try spawning it.", 10)
  end)

  MENU_MISSION_COMMAND:New("Set HIND-01 Damage -> Destroyed (Test)", self.MenuRoot, function()
    self:SetAirframeDamage("HIND-01", self.DAMAGE.DESTROYED)
    self:Announce("Set HIND-01 damage to Destroyed (Down). Try spawning it.", 10)
  end)

  MENU_MISSION_COMMAND:New("Set HIND-01 Damage -> OK (Test)", self.MenuRoot, function()
    self:SetAirframeDamage("HIND-01", self.DAMAGE.OK)
    self:Announce("Set HIND-01 damage back to OK.", 8)
  end)
end

----------------------------------------------------------------------
-- BOOTSTRAP
----------------------------------------------------------------------

function HIND_SQUADRON:Start()
  local roster = self:LoadPilotRoster()
  if roster then
    self:ApplyPilotRoster(self.DefaultState.Pilots, roster)
  end
  self.State = _deepCopy(self.DefaultState)
  local loaded = self:LoadState()
  if roster then
    if self:ApplyPilotRoster(self.State.Pilots, roster) then
      self:SaveState()
    end
  end
  if loaded then
    local path, filename = self:_GetStateFile()
    local loc = filename
    if path then
      loc = path .. "\\" .. filename
    elseif lfs then
      loc = lfs.writedir() .. "\\" .. filename
    end
    self:Announce("Hind Squadron Campaign State loaded from disk: " .. loc, 10)
  end
  self:EnableAirframeEnforcement()
  self:InitMenu()
  self:Announce("Hind Squadron Campaign State initialized. Use F10 menu: Hind Squadron (Campaign).", 12)
end

-- Call this once after loading the file:
HIND_SQUADRON:Start()
