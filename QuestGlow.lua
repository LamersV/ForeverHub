--[[
	Quest glow: a beacon of light on what a quest still needs.

	The game only tells where something is on the screen through nameplates, so the beacon
	rides them: every creature nameplate on screen whose unit has an objective of this
	character's quests not yet complete (read from the unit's tooltip; kill objectives are
	also matched by name, for when the tooltip says nothing).
	Objects a quest needs get the object glow instead (Glow\Glow.lua), which reads them with
	QuestGlow.Read below.

	The beacon: an aura on the body with a turning star, the quest mark above the name with
	the progress beside it, and a beam of light rising from the mark, seen from afar.
	All motion is done by animation groups inside the game engine (no Lua runs per frame);
	they stop by themselves when the nameplate leaves the screen.
--]]

local _, ns = ...

local QuestGlow = ns:NewModule("QuestGlow")

local GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR = "Interface\\Cooldown\\star4"
local MARK_ATLAS, MARK_FILE = "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon"
local BODY = -46 -- the creature's body, below its nameplate
local TAPPED = 0.35 -- alpha of a creature someone else tagged
local RESCAN_DELAY = 0.4 -- quest updates come in bursts

QuestGlow.COLORS = {
	{"gold", 1, 0.78, 0.2},
	{"green", 0.35, 1, 0.4},
	{"blue", 0.35, 0.7, 1},
	{"purple", 0.78, 0.45, 1},
	{"red", 1, 0.32, 0.22},
}
local colorOf = {}
for _, color in ipairs(QuestGlow.COLORS) do
	colorOf[color[1]] = color
end

local settings
local enabled -- the sparkles module runs (no conflicting addon)

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


--[[ What a quest needs ]]--

local LINE = Enum and Enum.TooltipDataLineType

-- "3/8" or "45%" out of an objective, and whether it is already full.
local function Progress(text)
	if Secret(text) or type(text) ~= "string" then return end
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have then
		return have .. "/" .. need, tonumber(have) >= tonumber(need)
	end
	local percent = text:match("(%d+)%s*%%")
	if percent then
		return percent .. "%", tonumber(percent) >= 100
	end
end

-- Kill objectives not yet done, from the quest log: {lowercase text, progress}.
local kills = {}

-- Rebuilds the kill objectives and returns a signature of the whole log's progress: the
-- tooltips of creatures only change when it does.
local signature = {}

local function BuildKills()
	wipe(kills)
	wipe(signature)
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then return "" end
	for i = 1, Ask(log.GetNumQuestLogEntries) or 0 do
		local info = Ask(log.GetInfo, i)
		if type(info) == "table" and not info.isHeader and info.questID then
			signature[#signature + 1] = info.questID
			for _, objective in ipairs(Ask(log.GetQuestObjectives, info.questID) or {}) do
				local fulfilled = objective.numFulfilled
				signature[#signature + 1] = objective.finished and "x" or Secret(fulfilled) and "?" or tostring(fulfilled)
				local text = objective.text
				if objective.type == "monster" and not objective.finished
					and not Secret(text) and type(text) == "string" and text ~= "" then
					local progress = Progress(text)
					if not progress and objective.numRequired then
						progress = (objective.numFulfilled or 0) .. "/" .. objective.numRequired
					end
					kills[#kills + 1] = {text:lower(), progress}
				end
			end
		end
	end
	return table.concat(signature, ",")
end

-- Whether a unit (creature or object) is still needed by a quest of this character, and
-- the progress of the first objective it serves. The tooltip lists the quest, then the
-- objectives; in a group, each player's name comes before their own objectives.
function QuestGlow.Read(unit, isObject)
	local data = LINE and C_TooltipInfo and Ask(C_TooltipInfo.GetUnit, unit)
	local any, objectives, mine = false, 0, true
	if type(data) == "table" and type(data.lines) == "table" then
		for _, line in ipairs(data.lines) do
			local kind = line.type
			if not Secret(kind) then
				if kind == LINE.QuestTitle then
					any, mine = true, true
				elseif kind == LINE.QuestPlayer then
					any = true
					local name = line.leftText
					mine = not Secret(name) and name == ns.playerName
				elseif kind == LINE.QuestObjective then
					any, objectives = true, objectives + 1
					if mine then
						local progress, full = Progress(line.leftText)
						local done = line.completed
						if not Secret(done) and done ~= true and not full then
							return true, progress
						end
					end
				end
			end
		end
	end
	-- a quest with no objective listed (talk to, use an item on...) still counts
	if any then return objectives == 0 end
	if isObject or #kills == 0 then return false end
	local name = Ask(UnitName, unit)
	if type(name) ~= "string" or #name < 3 then return false end
	name = name:lower()
	for _, kill in ipairs(kills) do
		if kill[1]:find(name, 1, true) then
			return true, kill[2]
		end
	end
	return false
end


--[[ The beacon ]]--

local function HasAtlas(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and Ask(C_Texture.GetAtlasInfo, atlas) ~= nil
end

local function AddGroup(beacon, region, looping)
	local group = region:CreateAnimationGroup()
	group:SetLooping(looping)
	beacon.groups[#beacon.groups + 1] = group
	return group
end

-- Fades between two alphas (at full intensity) and, with grow, swells a little at the same time.
local function Breathe(beacon, region, low, high, seconds, grow)
	local group = AddGroup(beacon, region, "BOUNCE")
	local fade = group:CreateAnimation("Alpha")
	beacon.fades[#beacon.fades + 1] = {fade, low, high}
	fade:SetDuration(seconds)
	fade:SetSmoothing("IN_OUT")
	if grow then
		local scale = group:CreateAnimation("Scale")
		if scale.SetScaleTo then
			scale:SetScaleFrom(1, 1)
			scale:SetScaleTo(grow, grow)
		else
			scale:SetScale(grow, grow)
		end
		scale:SetDuration(seconds)
		scale:SetSmoothing("IN_OUT")
	end
end

-- Up and down; the mark, its glow and the progress move together.
local function Bob(beacon, region)
	local group = AddGroup(beacon, region, "BOUNCE")
	local move = group:CreateAnimation("Translation")
	move:SetOffset(0, 5)
	move:SetDuration(0.8)
	move:SetSmoothing("IN_OUT")
end

-- A still light: its alpha at full intensity.
local function Still(beacon, region, alpha)
	beacon.stills[#beacon.stills + 1] = {region, alpha}
end

local function Light(beacon, layer, sublevel, texture, width, height)
	local region = beacon:CreateTexture(nil, layer, nil, sublevel)
	region:SetTexture(texture)
	region:SetBlendMode("ADD")
	region:SetSize(width, height)
	beacon.tinted[#beacon.tinted + 1] = region
	return region
end

local function PlayAll(self)
	for _, group in ipairs(self.groups) do group:Play() end
end

local function StopAll(self)
	for _, group in ipairs(self.groups) do group:Stop() end
end

local function CreateBeacon()
	local beacon = CreateFrame("Frame")
	beacon:SetSize(1, 1)
	beacon:Hide()
	beacon.groups, beacon.tinted, beacon.fades, beacon.stills = {}, {}, {}, {}

	-- on the body: a wide breathing aura, a turning star and a bright core
	local aura = Light(beacon, "BACKGROUND", 0, GLOW, 130, 100)
	aura:SetPoint("CENTER", beacon, "CENTER", 0, BODY)
	Breathe(beacon, aura, 0.35, 0.8, 1.1, 1.12)

	local star = Light(beacon, "BORDER", 0, STAR, 80, 80)
	star:SetPoint("CENTER", beacon, "CENTER", 0, BODY)
	Still(beacon, star, 0.5)
	local spin = AddGroup(beacon, star, "REPEAT"):CreateAnimation("Rotation")
	spin:SetDegrees(-360)
	spin:SetDuration(9)

	local core = Light(beacon, "ARTWORK", 0, GLOW, 54, 42)
	core:SetPoint("CENTER", beacon, "CENTER", 0, BODY)
	Breathe(beacon, core, 0.45, 0.85, 0.75)

	-- above the name: the quest mark on a glow, the progress, and the beam
	local mark = beacon:CreateTexture(nil, "OVERLAY")
	mark:SetSize(26, 26)
	if HasAtlas(MARK_ATLAS) then
		mark:SetAtlas(MARK_ATLAS)
	else
		mark:SetTexture(MARK_FILE)
	end
	beacon.mark = mark
	Bob(beacon, mark)

	local halo = Light(beacon, "ARTWORK", 1, GLOW, 46, 46)
	halo:SetPoint("CENTER", mark, "CENTER")
	Still(beacon, halo, 0.7)
	Bob(beacon, halo)

	local beam = Light(beacon, "BACKGROUND", 1, GLOW, 24, 240)
	beam:SetPoint("BOTTOM", mark, "CENTER")
	Breathe(beacon, beam, 0.25, 0.6, 1.4)
	beacon.beam = beam

	local text = beacon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	text:SetPoint("LEFT", mark, "RIGHT", 1, 0)
	text:SetTextColor(1, 1, 1)
	beacon.text = text
	Bob(beacon, text)

	beacon:SetScript("OnShow", PlayAll)
	beacon:SetScript("OnHide", StopAll)
	return beacon
end

local function Style(beacon)
	local color = colorOf[settings.questColor] or QuestGlow.COLORS[1]
	for _, region in ipairs(beacon.tinted) do
		region:SetVertexColor(color[2], color[3], color[4])
	end
	beacon:SetScale(math.max(settings.questScale or 100, 30) / 100)
	-- intensity dims only the light: the mark and the progress stay sharp
	local intensity = math.min(math.max(settings.questIntensity or 50, 10), 100) / 100
	for _, fade in ipairs(beacon.fades) do
		fade[1]:SetFromAlpha(fade[2] * intensity)
		fade[1]:SetToAlpha(fade[3] * intensity)
	end
	for _, still in ipairs(beacon.stills) do
		still[1]:SetAlpha(still[2] * intensity)
	end
	beacon.beam:SetShown(settings.questBeam)
	beacon.text:SetShown(settings.questProgress)
end

local function SetProgress(beacon, progress)
	beacon.text:SetText(progress or "")
end

local function Attach(beacon, plate)
	beacon:SetParent(plate)
	beacon:ClearAllPoints()
	beacon:SetPoint("CENTER", plate, "CENTER")
	beacon.mark:ClearAllPoints()
	beacon.mark:SetPoint("BOTTOM", plate, "TOP", 0, 2)
	-- full light even on the faded nameplates of creatures that are not the target
	beacon:SetIgnoreParentAlpha(true)
	local ok, level = pcall(plate.GetFrameLevel, plate)
	if ok and type(level) == "number" and not Secret(level) then
		beacon:SetFrameLevel(math.max(level - 1, 0)) -- under the nameplate, which stays readable
	end
	beacon.plate = plate
	beacon:Show()
end

local function Detach(beacon)
	beacon:Hide()
	beacon:ClearAllPoints()
	beacon.mark:ClearAllPoints()
	beacon:SetParent(nil)
	beacon.plate = nil
end

local pool = {}

local function Acquire()
	local beacon = table.remove(pool) or CreateBeacon()
	Style(beacon)
	return beacon
end

local function Release(beacon)
	Detach(beacon)
	pool[#pool + 1] = beacon
end


--[[ Creatures ]]--

local shown = {} -- nameplate unit tokens on screen
local lit = {} -- unit token -> beacon
local cache = {} -- creature ID -> {needed, progress}; cleared when the quest log changes

local function CreatureID(unit)
	local guid = Ask(UnitGUID, unit)
	if type(guid) ~= "string" then return end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then
		return id
	end
end

local function Needed(unit)
	if Ask(UnitIsPlayer, unit) ~= false or Ask(UnitIsGameObject, unit) == true
		or Ask(UnitIsDead, unit) == true then
		return false
	end
	local id = CreatureID(unit)
	local entry = id and cache[id]
	if not entry then
		local needed, progress = QuestGlow.Read(unit)
		entry = {needed == true, progress}
		if id then cache[id] = entry end
	end
	return entry[1], entry[2]
end

local function Unlight(unit)
	local beacon = lit[unit]
	if beacon then
		lit[unit] = nil
		Release(beacon)
	end
end

local function Tapped(unit)
	return Ask(UnitIsTapDenied, unit) == true
end

local function Update(unit)
	if not (enabled and settings.questMobs) then return Unlight(unit) end
	local needed, progress = Needed(unit)
	local plate = needed and C_NamePlate and Ask(C_NamePlate.GetNamePlateForUnit, unit)
	if not plate then return Unlight(unit) end
	local beacon = lit[unit]
	if beacon and beacon.plate ~= plate then
		Unlight(unit)
		beacon = nil
	end
	if not beacon then
		beacon = Acquire()
		lit[unit] = beacon
		Attach(beacon, plate)
	end
	SetProgress(beacon, progress)
	beacon:SetAlpha(Tapped(unit) and TAPPED or 1)
end

local pending

local lastSignature, forced

-- QUEST_LOG_UPDATE fires often without any progress: the creatures on the screen are read
-- again only when the log really changed (or the group did, or a setting).
local function Rescan(force)
	pending = nil
	force, forced = force or forced, nil
	local current = BuildKills()
	if not force and current == lastSignature then return end
	lastSignature = current
	wipe(cache)
	for unit in pairs(shown) do
		Update(unit)
	end
end

local TrackedRescan = ns:Track("questglow:rescan", Rescan) -- /fh mem

local function Schedule(event)
	if event == "GROUP_ROSTER_UPDATE" then forced = true end
	if pending then return end
	pending = true
	C_Timer.After(RESCAN_DELAY, TrackedRescan)
end


--[[ Module ]]--

function QuestGlow:Refresh()
	enabled = ns:IsModuleActive("sparkles")
	for _, beacon in pairs(lit) do
		Style(beacon)
	end
	Rescan(true)
end

function QuestGlow:Debug()
	local L = ns.L
	ns:Print(L.GLOW_DEBUG:format(#kills))
	local count, plates = 0, 0
	for _ in pairs(lit) do count = count + 1 end
	for _ in pairs(shown) do plates = plates + 1 end
	ns:Print(L.GLOW_DEBUG_PLATES:format(count, plates))
	local unit = Ask(UnitExists, "target") and "target" or (Ask(UnitExists, "softinteract") and "softinteract")
	if not unit then
		ns:Print(L.GLOW_DEBUG_NO_TARGET)
		return
	end
	local needed, progress = QuestGlow.Read(unit, Ask(UnitIsGameObject, unit) == true)
	ns:Print(L.GLOW_DEBUG_TARGET:format(tostring(Ask(UnitName, unit)), tostring(needed), tostring(progress)))
	local data = LINE and C_TooltipInfo and Ask(C_TooltipInfo.GetUnit, unit)
	for i, line in ipairs(type(data) == "table" and data.lines or {}) do
		if i > 10 then break end
		local kind, text = line.type, line.leftText
		print(("  %d. type %s: %s%s"):format(i, Secret(kind) and "?" or tostring(kind),
			Secret(text) and "?" or tostring(text), line.completed == true and " (ok)" or ""))
	end
end

function QuestGlow:OnInitialize()
	settings = ns.db.sparkles
end

function QuestGlow:OnLogin()
	ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
		shown[unit] = true
		Update(unit)
	end)
	ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
		shown[unit] = nil
		Unlight(unit)
	end)
	-- someone else tagged a creature: its light dims
	ns:RegisterEvent("UNIT_FLAGS", function(_, unit)
		local beacon = lit[unit]
		if beacon then
			beacon:SetAlpha(Tapped(unit) and TAPPED or 1)
		end
	end)
	-- an objective done: what it needed stops glowing; one taken: what it needs starts
	for _, event in ipairs({"QUEST_LOG_UPDATE", "QUEST_REMOVED", "GROUP_ROSTER_UPDATE"}) do
		pcall(ns.RegisterEvent, ns, event, Schedule)
	end
	-- nameplates already on the screen (after /reload)
	for _, plate in ipairs(C_NamePlate and Ask(C_NamePlate.GetNamePlates) or {}) do
		local unit = plate.namePlateUnitToken
		if type(unit) == "string" and not Secret(unit) then
			shown[unit] = true
		end
	end
	self:Refresh()
end
