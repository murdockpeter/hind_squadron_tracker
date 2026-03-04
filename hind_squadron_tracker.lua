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

HIND_SQUADRON.FATIGUE = {
  FRESH = "Fresh",
  TIRED = "Tired",
  EXHAUSTED = "Exhausted",
}

----------------------------------------------------------------------
-- INITIAL STATE
----------------------------------------------------------------------

HIND_SQUADRON.State = {
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
    { Id = "PILOT-01", Name = "Viper",  Fatigue = "Fresh", Notes = "" },
    { Id = "PILOT-02", Name = "Bear",   Fatigue = "Fresh", Notes = "" },
    { Id = "PILOT-03", Name = "Saber",  Fatigue = "Fresh", Notes = "" },
    { Id = "PILOT-04", Name = "Cobalt", Fatigue = "Fresh", Notes = "" },
    { Id = "PILOT-05", Name = "Rook",   Fatigue = "Fresh", Notes = "" },
    { Id = "PILOT-06", Name = "Mako",   Fatigue = "Fresh", Notes = "" },
  },
}

----------------------------------------------------------------------
-- UTILS
----------------------------------------------------------------------

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

local function _clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

----------------------------------------------------------------------
-- CORE: AIRFRAMES
----------------------------------------------------------------------

function HIND_SQUADRON:GetAirframe(id)
  return _findById(self.State.Airframes, id)
end

function HIND_SQUADRON:SetAirframeDamage(id, damage)
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
  return true
end

function HIND_SQUADRON:IsAirframeFlyable(id)
  local af = self:GetAirframe(id)
  if not af then return false end
  return (af.Damage ~= self.DAMAGE.DESTROYED and af.Damage ~= self.DAMAGE.MAJOR)
end

----------------------------------------------------------------------
-- CORE: PILOTS
----------------------------------------------------------------------

function HIND_SQUADRON:GetPilot(id)
  return _findById(self.State.Pilots, id)
end

function HIND_SQUADRON:SetPilotFatigue(id, fatigue)
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
  return true
end

-- Simple fatigue progression for “a sortie was flown”
function HIND_SQUADRON:ApplySortieFatigue(pilotId)
  local p = self:GetPilot(pilotId)
  if not p then return false end

  if p.Fatigue == self.FATIGUE.FRESH then
    p.Fatigue = self.FATIGUE.TIRED
  elseif p.Fatigue == self.FATIGUE.TIRED then
    p.Fatigue = self.FATIGUE.EXHAUSTED
  end
  return true
end

-- Simple recovery when advancing turns (sleep/rotation)
function HIND_SQUADRON:RecoverPilotFatigueAll()
  for _, p in ipairs(self.State.Pilots) do
    if p.Fatigue == self.FATIGUE.EXHAUSTED then
      p.Fatigue = self.FATIGUE.TIRED
    elseif p.Fatigue == self.FATIGUE.TIRED then
      p.Fatigue = self.FATIGUE.FRESH
    end
  end
end

----------------------------------------------------------------------
-- CORE: SUPPLY
----------------------------------------------------------------------

function HIND_SQUADRON:AddSupply(points)
  self.State.SupplyPoints = _clamp(self.State.SupplyPoints + points, 0, 999)
end

function HIND_SQUADRON:SpendSupply(points)
  points = math.max(0, points)
  if self.State.SupplyPoints < points then return false end
  self.State.SupplyPoints = self.State.SupplyPoints - points
  return true
end

----------------------------------------------------------------------
-- TURN MANAGEMENT
----------------------------------------------------------------------

-- Call at the end of a campaign “turn”
function HIND_SQUADRON:AdvanceTurn()
  self.State.Turn = self.State.Turn + 1

  -- MVP: fatigue recovery happens between turns.
  self:RecoverPilotFatigueAll()

  -- MVP: small resupply drip each turn (tune to taste)
  self:AddSupply(2)

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
    table.insert(lines, ("  %s (%s) | Fatigue: %-9s"):format(p.Id, p.Name, p.Fatigue))
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
  if event.id ~= world.event.S_EVENT_BIRTH then return end
  if not event.initiator then return end

  local unit = event.initiator
  if not Unit.isExist(unit) then return end

  local group = unit:getGroup()
  if not group then return end

  local groupName = group:getName()
  if not groupName then return end

  -- Only enforce for our tracked Hinds (group name must match airframe Id)
  local af = HIND_SQUADRON:GetAirframe(groupName)
  if not af then return end

  local down = (af.Damage == HIND_SQUADRON.DAMAGE.DESTROYED) or (af.Damage == HIND_SQUADRON.DAMAGE.MAJOR)
  if down then
    trigger.action.outText(
      ("CAMPAIGN: %s is %s and is unavailable this turn."):format(groupName, af.Damage),
      10
    )
    group:destroy()
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
  self:EnableAirframeEnforcement()
  self:InitMenu()
  self:Announce("Hind Squadron Campaign State initialized. Use F10 menu: Hind Squadron (Campaign).", 12)
end

-- Call this once after loading the file:
HIND_SQUADRON:Start()
