--[[
	Sparkles and interaction icons.

	1. Quest items: the game's own loot sparkle (outlineModeShowLootEffectWhenDisabled)
	   is kept on; graphics presets switch it off, so it is set again after them.
	2. Interaction icons: the game's soft targeting picks the nearest object you can use
	   and shows the action icon above it (gather, open, loot...). The settings that make
	   it do so are switched on, and the player's own values come back when it is off.
	3. Ore, herbs and corpses with loot: golden glints over the object the game picked.
	   Only nameplates know where an object is on the screen, so the game's nameplate for
	   the interaction target is switched on just for those objects (never in combat).

	Written for ForeverHub; the original ForeverLootSparkles (and Lueur) change the same
	settings, so the module stays off while one of them is enabled.
--]]

local _, ns = ...

local Sparkles = ns:NewModule("Sparkles")

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

local UNIT = "softinteract"
local STAR = "Interface\\Cooldown\\star4"
local GLINTS, RADIUS, SIZE, DROP = 6, 40, 30, -42
local CHECK_EVERY = 0.15

local settings
local active -- the module runs (enabled and no conflicting addon)

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Unit calls can error or answer with secret values in instances: both mean "unknown".
local function Ask(func, ...)
	if not func then return nil end
	local ok, value = pcall(func, ...)
	if ok and not Secret(value) then
		return value
	end
end

local function Write(name, value)
	value = tostring(value)
	local ok, current = pcall(GetCVar, name)
	if not ok or current == nil or current == value then return end
	pcall(SetCVar, name, value)
end


--[[ 1. Quest item sparkle ]]--

local LOOT_EFFECT = "outlineModeShowLootEffectWhenDisabled"
-- the game resets the sparkle when one of these changes
local PRESETS = {graphicsquality = true, raidgraphicsquality = true, [LOOT_EFFECT:lower()] = true}

local function ApplyLootEffect()
	if not active or not settings.questLoot then return end
	ns:RunOutOfCombat("sparkles-loot", function() Write(LOOT_EFFECT, 1) end)
end


--[[ 2. Interaction icons (soft targeting) ]]--

-- Settings changed here; the player's values are kept in settings.saved until it is off.
local SOFT_TARGET = {
	SoftTargetInteract = 3, -- the interaction target, always
	SoftTargetIconGameObject = 1, -- action icon above world objects
	SoftTargetInteractRange = 30, -- the game itself stops at about 15 yards
	SoftTargetInteractArc = 2, -- all around, not only in front
	SoftTargetInteractOnlyInRange = 0, -- also objects a few steps away
}
local GATE = "SoftTargetNameplateInteract" -- nameplate on the interaction target

local function Wanted()
	return active and (settings.interactIcons or settings.ore or settings.herbs or settings.corpses)
end

local function ApplySoftTarget()
	ns:RunOutOfCombat("sparkles-soft", function()
		if Wanted() then
			settings.saved = settings.saved or {}
			for name, value in pairs(SOFT_TARGET) do
				if settings.saved[name] == nil then
					settings.saved[name] = GetCVar(name) or false
				end
				Write(name, value)
			end
			if settings.saved[GATE] == nil then
				settings.saved[GATE] = GetCVar(GATE) or false
			end
		elseif settings.saved then
			for name, value in pairs(settings.saved) do
				if value ~= false then Write(name, value) end
			end
			settings.saved = nil
		end
	end)
end


--[[ 3. Glints ]]--

local glow -- the frame with the glints, moved to the nameplate of the object
local plateOf -- nameplate it is on
local gateOpen
local look = {state = "far", shown = 0, ready = 0, grey = 0}

-- Category of an object from the cursor the game would show over it.
local cursorFiles = {} -- file ID -> {category, unable}
for name, category in pairs({Mine = "ore", GatherHerbs = "herb"}) do
	for _, prefix in ipairs({"", "Unable"}) do
		local id = GetFileIDFromPath and Ask(GetFileIDFromPath, "Interface\\Cursor\\" .. prefix .. name)
		if id then
			cursorFiles[id] = {category, prefix ~= ""}
		end
	end
end

local probe = UIParent:CreateTexture()
probe:Hide()

local function FromName(name)
	if type(name) ~= "string" then return end
	name = name:lower()
	local unable = name:find("unable", 1, true) ~= nil
	if name:find("herb", 1, true) or name:find("gather", 1, true) then
		return "herb", unable
	elseif name:find("mine", 1, true) then
		return "ore", unable
	end
end

local function CursorCategory(unit)
	if not (SetUnitCursorTexture and Ask(SetUnitCursorTexture, probe, unit, nil, true)) then return end
	local texture = probe:GetTexture()
	if Secret(texture) then return end
	local known = cursorFiles[texture]
	if known then
		return known[1], known[2]
	end
	local category, unable = FromName(texture)
	if not category and probe.GetAtlas then
		local atlas = probe:GetAtlas()
		if not Secret(atlas) then
			category, unable = FromName(atlas)
		end
	end
	return category, unable
end

-- A dead creature that still holds loot this character may take.
local function HasLoot(unit)
	if Ask(UnitIsDead, unit) ~= true or not CanLootUnit then return false end
	local guid = Ask(UnitGUID, unit)
	if not guid then return false end
	local ok, hasLoot, canLoot = pcall(CanLootUnit, guid)
	return ok and not Secret(hasLoot) and not Secret(canLoot) and hasLoot == true and canLoot ~= false
end

-- What the interaction target is, if it should glow: "ore", "herb" or "corpse", and
-- whether the game would refuse it now (skill too low...).
local function Target()
	if Ask(UnitIsGameObject, UNIT) == true then
		local category, unable = CursorCategory(UNIT)
		if (category == "ore" and settings.ore) or (category == "herb" and settings.herbs) then
			return category, unable
		end
	elseif settings.corpses and Ask(UnitExists, UNIT) == true and HasLoot(UNIT) then
		return "corpse", false
	end
end

local function SetGate(open)
	if open == gateOpen or InCombatLockdown() then return end
	gateOpen = open
	Write(GATE, open and 1 or 0)
end

local function Plate()
	local plate = C_NamePlate and Ask(C_NamePlate.GetNamePlateForUnit, UNIT)
	if plate then return plate end
	-- some clients only answer for the "nameplateN" token of the same object
	for _, other in ipairs(C_NamePlate and Ask(C_NamePlate.GetNamePlates) or {}) do
		local token = other.namePlateUnitToken or (other.UnitFrame and other.UnitFrame.unit)
		if token and not Secret(token) and Ask(UnitIsUnit, token, UNIT) == true then
			return other
		end
	end
end

local function Lerp(a, b, t) return a + (b - a) * t end

local function Toward(value, target, step)
	if value < target then return math.min(value + step, target) end
	return math.max(value - step, target)
end

-- New place, size and life for a glint; "now" starts it at once (the burst when in reach).
local function Reset(glint, now)
	local angle, distance = math.random() * 2 * math.pi, math.sqrt(math.random())
	glint.x = math.cos(angle) * distance * RADIUS
	glint.y = math.sin(angle) * distance * RADIUS * 0.7
	glint.life = 0.7 + math.random() * 0.7
	glint.size = SIZE * (0.5 + math.random() * 0.6)
	glint.spin = (math.random() - 0.5) * 2.4
	glint.time = now and 0 or -math.random() * 0.7
end

local function Animate(self, elapsed)
	elapsed = math.min(elapsed, 0.1)
	look.shown = Toward(look.shown, 1, elapsed / 0.3)
	look.ready = Toward(look.ready, look.state == "ready" and 1 or 0, elapsed / 0.3)
	look.grey = Toward(look.grey, look.state == "unable" and 1 or 0, elapsed / 0.3)
	-- dim when out of reach, grey and slower when the game refuses it
	local alpha = look.shown * Lerp(0.5, 1, look.ready) * (1 - 0.5 * look.grey)
	local speed = Lerp(0.8, 1.2, look.ready) * (1 - 0.5 * look.grey)
	local r, g, b = Lerp(1, 0.6, look.grey), Lerp(0.85, 0.6, look.grey), Lerp(0.45, 0.6, look.grey)
	for _, glint in ipairs(self.glints) do
		glint.time = glint.time + elapsed * speed
		if glint.time >= glint.life then Reset(glint) end
		local age = math.max(glint.time, 0)
		local light = glint.time > 0 and math.sin(math.pi * glint.time / glint.life) or 0
		local size = math.max(glint.size * (0.4 + 0.6 * light), 0.01)
		local texture = glint.texture
		texture:SetPoint("CENTER", self, "CENTER", glint.x, glint.y + 8 * age)
		texture:SetSize(size, size)
		texture:SetRotation(glint.spin * age)
		texture:SetVertexColor(r, g, b, math.min(alpha * light, 1))
	end
end

local function CreateGlow()
	glow = CreateFrame("Frame")
	glow:SetSize(1, 1)
	glow:Hide()
	glow.glints = {}
	for i = 1, GLINTS do
		local texture = glow:CreateTexture(nil, "OVERLAY")
		texture:SetTexture(STAR)
		texture:SetBlendMode("ADD")
		texture:SetVertexColor(1, 1, 1, 0)
		glow.glints[i] = {texture = texture}
	end
	glow:SetScript("OnUpdate", Animate)
end

local function Hide()
	if not plateOf then return end
	glow:Hide()
	glow:ClearAllPoints()
	glow:SetParent(nil)
	plateOf = nil
end

local function Show(plate, state)
	if not glow then CreateGlow() end
	glow:SetParent(plate)
	glow:ClearAllPoints()
	glow:SetPoint("CENTER", plate, "CENTER", 0, DROP)
	glow:SetIgnoreParentAlpha(true)
	local ok, level = pcall(plate.GetFrameLevel, plate)
	if ok and type(level) == "number" and not Secret(level) then
		glow:SetFrameLevel(math.max(level - 1, 0)) -- under the name, which stays readable
	end
	plateOf = plate
	look.state, look.next = state, nil
	look.shown, look.ready, look.grey = 0, state == "ready" and 1 or 0, state == "unable" and 1 or 0
	for _, glint in ipairs(glow.glints) do Reset(glint) end
	glow:Show()
end

-- A state shows only after holding a moment (no flicker at the edge of reach).
local function ChangeState(state)
	if state == look.state then
		look.next = nil
		return
	end
	local now = GetTime()
	if look.next ~= state then
		look.next, look.since = state, now
	elseif now - look.since >= 0.2 then
		look.state, look.next = state, nil
		if state == "ready" then
			for _, glint in ipairs(glow.glints) do Reset(glint, true) end
		end
	end
end

local function Check()
	if not Wanted() or not (settings.ore or settings.herbs or settings.corpses) then
		Hide()
		return
	end
	local category, unable = Target()
	if not category then
		SetGate(false)
		Hide()
		return
	end
	SetGate(true)
	local plate = Plate()
	if not plate then -- it comes a moment after the gate opens
		Hide()
		return
	end
	local inReach = UnitIsInInteractRange and Ask(UnitIsInInteractRange, UNIT)
	local state = inReach == false and "far" or (unable and "unable" or "ready")
	if plate ~= plateOf then
		Hide()
		Show(plate, state)
	else
		ChangeState(state)
	end
end

local poll = CreateFrame("Frame")
poll:Hide()
poll.wait = 0
poll:SetScript("OnUpdate", function(self, elapsed)
	self.wait = self.wait - elapsed
	if self.wait <= 0 then
		self.wait = CHECK_EVERY
		Check()
	end
end)


--[[ Module ]]--

function Sparkles:Refresh()
	active = ns:IsModuleActive("sparkles")
	if active and settings.questLoot then
		ApplyLootEffect()
	end
	ApplySoftTarget()
	gateOpen = nil
	local glints = Wanted() and (settings.ore or settings.herbs or settings.corpses)
	poll:SetShown(glints and true or false)
	if not glints then
		Hide()
		if Wanted() then
			SetGate(false) -- icons only: no nameplate on the interaction target
		end
	end
end

-- Switching the quest sparkle off only takes effect after restarting the game.
function Sparkles:SetQuestLoot(value)
	settings.questLoot = value
	if value then
		ApplyLootEffect()
	elseif active then
		ns:RunOutOfCombat("sparkles-loot", function() Write(LOOT_EFFECT, 0) end)
		ns:Print(ns.L.SPARKLES_RESTART)
	end
end

function Sparkles:OnInitialize()
	settings = ns.db.sparkles
end

function Sparkles:OnLogin()
	self:Refresh()
	-- account settings can arrive after login and overwrite these
	C_Timer.After(5, function() self:Refresh() end)

	pcall(ns.RegisterEvent, ns, "CVAR_UPDATE", function(_, name)
		if type(name) == "string" and PRESETS[name:lower()] and active and settings.questLoot then
			C_Timer.After(1, ApplyLootEffect)
		end
	end)
	-- no corpse nameplates during a fight: the gate closes before combat locks settings
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if poll:IsShown() then
			SetGate(false)
			Hide()
		end
	end)
	for _, event in ipairs({"PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED"}) do
		pcall(ns.RegisterEvent, ns, event, function()
			if poll:IsShown() then Check() end
		end)
	end
	ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
		if plateOf and C_NamePlate and Ask(C_NamePlate.GetNamePlateForUnit, unit) == plateOf then
			Hide()
		end
	end)
end
