--[[
	Glow: lights up the object you are about to use (ore, herbs, quest objects, chests,
	the fishing bobber, corpses with loot...).

	The game's soft targeting picks, at any moment, one object to interact with (the unit
	"softinteract") and can give it a nameplate. The glow rides that nameplate: one light,
	colored by the kind of object (read from its interaction cursor), drawn by the chosen
	effect (Effects.lua) and shaded by its state: out of reach, in reach, or refused for now
	(skill too low...). Above it, the object's name and action icon.

	"Exclusive" mode only lets the game show its nameplate and icon for the objects that
	glow: NPCs, mailboxes and the rest still work with the interact key, unmarked.

	Settings live in ns.db.glow. The game's soft targeting settings are changed while the
	glow is on; the player's own values come back when it is switched off and at logout,
	so turning ForeverHub off leaves nothing behind.

	Written for ForeverHub from scratch; the addon Lueur (same idea) was only used as a
	reference for the game's behaviour. ForeverHub stays off while Lueur is enabled.
--]]

local ADDON, ns = ...
local L = ns.L
local FX = ns.GlowFX

local Glow = ns:NewModule("Glow")

local SOFT = "softinteract"
local CURSORS = "Interface\\Cursor\\"
local LINE_RANGE = 60 -- yards searched while the fishing line is out (the bobber falls far)
local FISHING_ICON = 136245
local BOBBERS = {[35591] = true} -- object ID of the fishing bobber, read from its GUID
-- seconds between checks: while an object glows (its reach can change) or its nameplate is
-- awaited, and otherwise (a new target comes with PLAYER_SOFT_INTERACT_CHANGED anyway)
local POLL_ACTIVE, POLL_IDLE = 0.1, 0.5
local STATE_HOLD, LOCK_HOLD = 0.15, 0.6 -- a state shows once it held this long (no flicker)
local SILHOUETTE_RATE = 1 / 30

Glow.CATEGORIES = {"ore", "herb", "quest", "chest", "bobber", "loot", "other"}
Glow.ICONS = {
	ore = "Interface\\Icons\\Trade_Mining", herb = "Interface\\Icons\\Trade_Herbalism",
	quest = "Interface\\Icons\\INV_Misc_Note_01", chest = "Interface\\Icons\\INV_Box_01",
	bobber = "Interface\\Icons\\Trade_Fishing", loot = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	other = "Interface\\Icons\\INV_Misc_Gear_01",
}
-- cursor the preview and the menu show for each category, having no object to ask
Glow.SAMPLE_CURSORS = {ore = "Mine", herb = "GatherHerbs", quest = "Quest", chest = "Pickup", bobber = "Interact",
	loot = "LootAll", other = "Interact"}

Glow.LIMITS = {
	range = {5, 15}, -- the game loses the interaction target past 15 yards
	arc = {0, 2},
	offsetY = {-200, 200},
	size = {40, 300},
	intensity = {30, 150},
	textSize = {60, 200},
	bodyScale = {40, 300},
	bodyShift = {-100, 100},
}
local LIMITS = Glow.LIMITS

-- Look settings: one value for every object, which a category may override (db.own).
local LOOK = {effect = true, size = true, intensity = true, offsetY = true, followAlpha = true, silhouette = true,
	showName = true, showIcon = true, textSize = true, font = true}
Glow.LOOK = LOOK

-- Fonts the name can use: the game's, or one of the other fonts every client has.
Glow.FONTS = {
	{"game"},
	{"arial", "Arial Narrow", "Fonts\\ARIALN.TTF"},
	{"friz", "Friz Quadrata", "Fonts\\FRIZQT__.TTF"},
	{"morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF"},
	{"skurri", "Skurri", "Fonts\\SKURRI.TTF"},
}
local fontFiles = {}
for _, font in ipairs(Glow.FONTS) do
	if font[3] then fontFiles[font[1]] = font[3] end
end

ns.defaults.glow = {
	enabled = true,
	range = 15, arc = 2, -- arc: 0 straight ahead, 1 in front, 2 all around
	exclusive = true, -- the game marks (nameplate, icon) only the objects that glow
	glowOnly = false, -- the light alone: no name or icon of ours, the nameplate left to the game
	effect = "aura", size = 120, intensity = 100, offsetY = -45,
	followAlpha = false, -- fades with the nameplate (object behind scenery...)
	silhouette = true, -- the light passes behind the character instead of over it
	showName = true, showIcon = true, textSize = 100, font = "game",
	own = {}, -- category -> its own look settings
	categories = {ore = true, herb = true, quest = true, chest = true, bobber = true, loot = true, other = false},
	colors = {
		ore = {1, 0.6, 0.18}, herb = {0.4, 1, 0.42}, quest = {1, 0.84, 0.15}, chest = {0.45, 0.78, 1},
		bobber = {1, 0.45, 0.4}, loot = {0.85, 0.55, 1}, other = {0.9, 0.9, 0.94},
	},
	hideInCombat = false, hideInInstance = false,
	hideLocked = false, -- no light on an object the game refuses for now
	hideUntrained = true, -- no light on ore or herbs this character cannot gather
	bodyScale = 100, bodyShift = 0, -- the area cut out around the character
	ignored = {}, -- folded name -> name: objects never lit
	containers = {}, -- object ID -> true: things looted before, counted as chests
	questObjects = {}, -- normalized object name -> quest title, learned from tooltips
	debug = false,
}
local DEFAULT_COLORS = ns.defaults.glow.colors

local db
local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Unit calls can error or answer with secret values in instances: both mean "unknown".
local function Ask(func, ...)
	if not func then return nil end
	local ok, value = pcall(func, ...)
	if ok and not IsSecret(value) then return value end
end

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

-- Lowercase without accents, so names match however they are typed.
local ACCENTS = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ç"] = "c", ["ñ"] = "n",
	["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["É"] = "e", ["Ê"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ô"] = "o",
	["Õ"] = "o", ["Ú"] = "u", ["Ç"] = "c",
}

local function Fold(text)
	text = text:gsub("\194\160", " "):gsub("\226\128\153", "'")
	return (text:gsub("[\195][\128-\191]", ACCENTS):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end
Glow.Fold = Fold


--[[ Settings ]]--

local function Look(category, key)
	local own = category and db.own[category]
	local value = own and own[key]
	if value == nil then return db[key] end
	return value
end

function Glow:Get(key, category)
	if LOOK[key] then return Look(category, key) end
	return db[key]
end

function Glow:GetColor(category)
	local color = db.colors[category] or db.colors.other
	return color[1], color[2], color[3]
end

function Glow:IsCategoryShown(category)
	return db.categories[category] == true
end

function Glow:HasOwn(category)
	return category ~= nil and db.own[category] ~= nil
end

function Glow:FontFile(key)
	return fontFiles[key]
end

local listeners = {}

-- Called with no argument whenever a setting changes (the window refreshes itself).
function Glow:OnChange(func)
	listeners[#listeners + 1] = func
end

local function Notify()
	for _, func in ipairs(listeners) do func() end
end


--[[ The game's settings ]]--

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

local MANAGED = {
	"SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
	"SoftTargetInteractOnlyInRange", "SoftTargetInteractRangeIsHard", "SoftTargetIconInteract", "SoftTargetIconGameObject",
	"nameplateGameObjectMaxDistance",
}

local function ReadCVar(name)
	local ok, value = pcall(GetCVar, name)
	if ok then return value end
end

-- Only settings this client knows (the list changes between versions).
local function WriteCVar(name, value)
	local current = ReadCVar(name)
	value = tostring(value)
	if current == nil or current == value then return end
	pcall(SetCVar, name, value)
end

local state = {
	active = false, -- module on and glow enabled
	gate = nil, -- the game's nameplate/icon on the interaction target: open, closed, nil = to apply
	pending = nil, -- "apply" or "restore" once combat ends
	combat = false,
	line = false, -- the fishing line is in the water
	leaving = false,
}

local function Range()
	return state.line and LINE_RANGE or db.range
end

-- The nameplate and icon the game gives the interaction target. In exclusive mode they
-- open only for an object that glows. The icon setting for world objects must be on for
-- the game to make their nameplate at all.
local function SetGate(open)
	open = open or not db.exclusive
	if open == state.gate or InCombatLockdown() then return end
	state.gate = open
	WriteCVar("SoftTargetNameplateInteract", open and 1 or 0)
	if open then WriteCVar("SoftTargetIconGameObject", 1) end
	local saved = db.savedCVars and db.savedCVars.SoftTargetIconInteract
	if saved ~= false then WriteCVar("SoftTargetIconInteract", open and (saved or 1) or 0) end
end

local function LooksApplied()
	local range = tonumber(ReadCVar("SoftTargetInteractRange"))
	return ReadCVar("SoftTargetInteract") == "3" and (range == db.range or range == LINE_RANGE)
end

local Evaluate

local function ApplyCVars()
	if InCombatLockdown() then
		state.pending = "apply"
		return
	end
	if db.cvarsReturned then
		-- given back at the last logout: what the client holds now is the player's
		db.cvarsReturned = nil
		if not LooksApplied() then db.savedCVars = nil end
	end
	db.savedCVars = db.savedCVars or {}
	for _, name in ipairs(MANAGED) do
		if db.savedCVars[name] == nil then
			db.savedCVars[name] = ReadCVar(name) or false
		end
	end
	WriteCVar("SoftTargetInteract", 3) -- the interaction target, always
	WriteCVar("SoftTargetInteractRange", Range())
	WriteCVar("SoftTargetInteractArc", db.arc)
	WriteCVar("SoftTargetInteractOnlyInRange", 0) -- also objects a few steps away
	WriteCVar("SoftTargetInteractRangeIsHard", 0)
	-- the light rides the nameplate: the game must show it as far as it picks objects
	WriteCVar("nameplateGameObjectMaxDistance", math.max(tonumber(db.savedCVars.nameplateGameObjectMaxDistance) or 0, LINE_RANGE))
	state.gate = nil
	Evaluate()
end

local function RestoreCVars()
	if InCombatLockdown() then
		state.pending = "restore"
		return
	end
	if not db.savedCVars then return end
	for name, value in pairs(db.savedCVars) do
		if value ~= false then WriteCVar(name, value) end
	end
	db.savedCVars = nil
	state.gate = nil
end

-- At logout the client gets the player's values back, so disabling ForeverHub leaves
-- nothing behind. They stay saved in case the client does not store them (a crash).
local function ReturnCVars()
	if not state.active or not db.savedCVars or InCombatLockdown() then return end
	for name, value in pairs(db.savedCVars) do
		if value ~= false then WriteCVar(name, value) end
	end
	db.cvarsReturned = true
end

local function ApplyRange()
	if not state.active or not db.savedCVars then return end
	if InCombatLockdown() then
		state.pending = state.pending or "apply"
	else
		WriteCVar("SoftTargetInteractRange", Range())
	end
end


--[[ What the object is ]]--

-- Cursor files of the game (Interface\Cursor\*) -> category. "service": the cursor tells
-- what the thing is (mailbox, vendor...), never a quest object by its name alone.
local CURSOR_CATEGORY = {
	Mine = "ore", GatherHerbs = "herb",
	Quest = "quest", QuestRepeatable = "quest", QuestTurnIn = "quest", QuestInteract = "quest",
	PickLock = "chest", LootAll = "chest", Pickup = "chest",
	Fishing = "bobber",
	Interact = "other", Inspect = "other", GamepadInteract = "other",
	Mail = "service", Speak = "service", Buy = "service", Trainer = "service", Taxi = "service", Innkeeper = "service",
	Repair = "service", RepairNPC = "service", Stablemaster = "service",
}
-- the client may answer with a path or an atlas name instead: keywords, first match wins
local CURSOR_WORDS = {
	{"gather", "herb"}, {"mine", "ore"}, {"quest", "quest"}, {"lootall", "chest"}, {"pickup", "chest"},
	{"picklock", "chest"}, {"fishing", "bobber"}, {"mail", "service"}, {"speak", "service"}, {"buy", "service"},
	{"trainer", "service"}, {"taxi", "service"}, {"innkeeper", "service"}, {"repair", "service"}, {"stable", "service"},
	{"interact", "other"}, {"inspect", "other"},
}

local cursorFiles = {} -- file ID -> {category, unable}
local probe

local function BuildCursorFiles()
	if not GetFileIDFromPath then return end
	for name, category in pairs(CURSOR_CATEGORY) do
		for _, prefix in ipairs({"", "Unable"}) do
			local id = Ask(GetFileIDFromPath, CURSORS .. prefix .. name)
			if id then cursorFiles[id] = {category, prefix ~= ""} end
		end
	end
end

local function CursorWords(name)
	if type(name) ~= "string" then return end
	name = name:lower()
	local unable = name:find("unable", 1, true) ~= nil
	for _, entry in ipairs(CURSOR_WORDS) do
		if name:find(entry[1], 1, true) then return entry[2], unable end
	end
	return nil, unable
end

-- Whether the object has a cursor, its category, whether it is greyed out ("Unable"),
-- and the raw cursor (debug).
local function ReadCursor(unit)
	if not (SetUnitCursorTexture and Ask(SetUnitCursorTexture, probe, unit, nil, true)) then return false end
	local texture, atlas = probe:GetTexture(), probe.GetAtlas and probe:GetAtlas()
	if IsSecret(texture) then texture = nil end
	if IsSecret(atlas) then atlas = nil end
	local key = texture or atlas
	local known = key and cursorFiles[key]
	if not known then
		-- a path or an atlas name: read once, then remembered like a file ID
		local category, unable = CursorWords(texture)
		if not category then
			local fromAtlas, atlasUnable = CursorWords(atlas)
			category, unable = fromAtlas, unable or atlasUnable
		end
		known = {category, unable or false}
		if key then cursorFiles[key] = known end
	end
	return true, known[1], known[2], atlas or texture
end

-- Object ID, the same for every object of a kind, read from its GUID.
local function ObjectID(guid)
	return type(guid) == "string" and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
end

-- Quest objectives not done yet, matched against object names.
-- titles: normalized title -> true; raw: title as the game writes it -> normalized (tooltips)
local quests = {dirty = true, objectives = {}, titles = {}, raw = {}, count = 0}

local function Normalize(text)
	text = Fold(text)
	text = text:gsub("%d+%s*/%s*%d+", ""):gsub("^[%s:%-]+", ""):gsub("[%s:%-]+$", "")
	return text
end

-- words too common to link an object to an objective on their own
local COMMON = {}
for word in ("small little large great giant ancient old pequeno pequena grande grandes velho velha antigo antiga"):gmatch("%S+") do
	COMMON[word] = true
end

local function RebuildQuests()
	quests.dirty = false
	wipe(quests.objectives)
	wipe(quests.titles)
	wipe(quests.raw)
	quests.count = 0
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then return end
	for i = 1, Ask(log.GetNumQuestLogEntries) or 0 do
		local info = Ask(log.GetInfo, i)
		if type(info) == "table" and not info.isHeader and info.questID then
			if type(info.title) == "string" and not IsSecret(info.title) then
				local title = Normalize(info.title)
				quests.titles[title], quests.raw[info.title] = true, title
				quests.count = quests.count + 1
			end
			for _, objective in ipairs(Ask(log.GetQuestObjectives, info.questID) or {}) do
				local text = objective.text
				if not objective.finished and type(text) == "string" and not IsSecret(text) then
					local progress = text:match("(%d+%s*/%s*%d+)")
					text = Normalize(text)
					if #text >= 4 then
						local kind = objective.type
						quests.objectives[#quests.objectives + 1] = {text = text, progress = progress and progress:gsub("%s", ""),
							pickable = kind == nil or kind == "item" or kind == "object"}
					end
				end
			end
		end
	end
end

-- a telling word of source that also starts a word of target
local function SharedWord(source, target)
	target = " " .. target:gsub("%p", " ")
	for word in source:gmatch("[^%s%p]+") do
		if #word >= 5 and not COMMON[word] and target:find(" " .. word, 1, true) then return word end
	end
end

-- Whether this object name belongs to a quest in the log, and the progress it shows.
-- Returns the reason (debug) and the progress.
local function MatchQuestName(name)
	if type(name) ~= "string" or #name < 4 then return end
	if quests.dirty then RebuildQuests() end
	name = Normalize(name)
	if quests.titles[db.questObjects[name] or ""] then return "tooltip" end
	for _, objective in ipairs(quests.objectives) do
		local text = objective.text
		if text:find(name, 1, true) or (#text >= 5 and name:find(text, 1, true)) then return "name", objective.progress end
	end
	for _, objective in ipairs(quests.objectives) do
		-- never a kill objective: a "Murloc Hut" is not a "Murloc slain"
		if objective.pickable and (SharedWord(name, objective.text) or SharedWord(objective.text, name)) then
			return "word", objective.progress
		end
	end
end

-- The tooltip of a quest object names its quest: when the game shows one, the object's
-- name is remembered (the only sure link when the name shares nothing with the objective).
-- The event fires for everything under the mouse: units are skipped before the tooltip is
-- built, and with no quest in the log nothing is read.
local function LearnFromTooltip()
	if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) or Ask(UnitExists, "mouseover") then return false end
	if quests.dirty then RebuildQuests() end
	if quests.count == 0 then return false end
	local data = Ask(C_TooltipInfo.GetWorldCursor)
	local lines = type(data) == "table" and data.lines
	if type(lines) ~= "table" or not lines[1] then return false end
	local name = lines[1].leftText
	if IsSecret(name) or type(name) ~= "string" then return false end
	for i = 2, #lines do
		local text = lines[i].leftText
		if type(text) == "string" and not IsSecret(text) then
			local title = quests.raw[text]
			if not title then
				title = Normalize(text) -- a title written another way (spacing, apostrophes)
				if not quests.titles[title] then title = nil end
			end
			if title then
				local key = Normalize(name)
				if db.questObjects[key] == title then return false end
				db.questObjects[key] = title
				return true
			end
		end
	end
	return false
end

-- Chest names, in English and Portuguese: a chest has no cursor of its own.
local CHEST_WORDS = {chest = 1, footlocker = 1, strongbox = 1, lockbox = 1, coffer = 1, ["bau"] = 1, cofre = 1, arca = 0,
	cofrinho = 1}

local function IsContainer(id, name)
	if id and db.containers[id] then return "looted" end
	if type(name) ~= "string" then return end
	for word in Fold(name):gmatch("[^%s%p]+") do
		local prefix = word:sub(1, 5)
		if CHEST_WORDS[word] or (#word > 5 and CHEST_WORDS[prefix] == 1) then return "name" end
	end
end

-- Object IDs of the ore and herbs met since login: never counted as chests when looted.
local gathered = {}

local function LearnContainers()
	if not (GetNumLootItems and GetLootSourceInfo) then return end
	for slot = 1, Ask(GetNumLootItems) or 0 do
		local id = ObjectID(Ask(GetLootSourceInfo, slot))
		if id and not BOBBERS[id] and not gathered[id] then db.containers[id] = true end
	end
end

-- Whether the player is fishing (the channel of the Fishing spell).
local function Fishing()
	if not UnitChannelInfo then return false end
	local ok, name, _, icon = pcall(UnitChannelInfo, "player")
	if not ok or IsSecret(name) or IsSecret(icon) then return false end
	return icon == FISHING_ICON or (type(icon) == "string" and icon:lower():find("trade_fishing", 1, true) ~= nil)
		or (name ~= nil and name == PROFESSIONS_FISHING)
end

-- Category of a world object and how it was found; cached per object (GUID) until the
-- target or the quest log changes. The greyed cursor is read again on every check.
local cache = {}

local function QuestOf(unit, name, service)
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and Ask(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true then
		local _, progress = ns.QuestGlow.Read(unit, true)
		return "game", progress
	end
	local needed, progress = ns.QuestGlow.Read(unit, true)
	if needed then return "tooltip", progress end
	if not service then return MatchQuestName(name) end
end

local function ClassifyObject(unit, cursorCategory, hasCursor)
	local guid = Ask(UnitGUID, unit)
	local entry = guid and cache[guid]
	if entry then return entry end
	local name = Ask(UnitName, unit)
	entry = {id = ObjectID(guid), guid = guid, name = name, ignored = type(name) == "string" and db.ignored[Fold(name)] ~= nil}
	local category = cursorCategory
	local service = category == "service"
	if service then category = "other" end
	if entry.id and BOBBERS[entry.id] then
		category, entry.why = "bobber", "id"
	elseif category ~= "ore" and category ~= "herb" and category ~= "bobber" then
		local why, progress = QuestOf(unit, name, service)
		if why then
			category, entry.why, entry.progress = "quest", why, progress
		elseif not service and not entry.id and (category == nil or category == "other") and state.line then
			category, entry.why = "bobber", "fishing"
		elseif not service and (category == nil or category == "other") then
			local container = IsContainer(entry.id, name)
			if container then category, entry.why = "chest", container end
		end
	end
	if not category and (hasCursor or Ask(UnitIsInteractable, unit) == true) then category = "other" end
	entry.category = category
	if entry.id and (category == "ore" or category == "herb") then gathered[entry.id] = true end
	if guid then cache[guid] = entry end
	return entry
end

-- A dead creature that still holds loot this character may take.
local function HasLoot(unit)
	if Ask(UnitIsDead, unit) ~= true or not CanLootUnit then return false end
	local guid = Ask(UnitGUID, unit)
	if not guid then return false end
	local ok, hasLoot, canLoot = pcall(CanLootUnit, guid)
	return ok and not IsSecret(hasLoot) and not IsSecret(canLoot) and hasLoot == true and canLoot ~= false
end

-- Whether this character has the profession that gathers a category: true, false, or nil
-- when the game does not say.
local PROFESSIONS = {herb = {line = 182, spells = {2383}}, ore = {line = 186, spells = {2580}}}
local TRAINED_CACHE = 5 -- seconds an answer is kept (asked on every check of a vein or herb)
local trained = {}

local function AskTrained(profession)
	local answered = false
	local known = IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
	if known then
		for _, spell in ipairs(profession.spells) do
			local has = Ask(known, spell)
			if has == true then return true end
			answered = answered or has == false
		end
	end
	if GetProfessions and GetProfessionInfo then
		local ok, first, second = pcall(GetProfessions)
		if ok then
			for _, index in ipairs({first or 0, second or 0}) do
				if index > 0 then
					local line = select(8, pcall(GetProfessionInfo, index)) -- after pcall's own result
					if line == profession.line then return true end
				end
			end
		end
	end
	if answered then return false end
	return nil
end

local function Trained(category)
	local profession = PROFESSIONS[category]
	if not profession then return nil end
	local entry = trained[category]
	local now = GetTime()
	if not entry or now - entry.at > TRAINED_CACHE then
		entry = entry or {}
		entry.value, entry.at = AskTrained(profession), now
		trained[category] = entry
	end
	return entry.value
end

-- "ready": can be used; "far": too far; "locked": in reach but refused (skill too low...).
local function ReadState(unit, unable)
	local inRange = UnitIsInInteractRange and Ask(UnitIsInInteractRange, unit)
	if inRange == false then return "far" end
	if unable then return inRange == true and "locked" or "far" end
	return "ready"
end


--[[ The target and its nameplate ]]--

local plates = {} -- nameplate unit tokens on screen

local function GetPlate(unit)
	return C_NamePlate and Ask(C_NamePlate.GetNamePlateForUnit, unit)
end

-- true, false, or nil when the game does not say (a world object does not "exist").
local function SoftExists()
	local isUnit, isObject = Ask(UnitExists, SOFT), Ask(UnitIsGameObject, SOFT)
	if isUnit or isObject then return true end
	if isUnit == false and isObject == false then return false end
end

-- The unit to ask, its nameplate (nil until the game shows it), and whether the target
-- is unknown rather than absent.
local function Resolve()
	local exists = SoftExists()
	if exists == false then return end
	local plate = GetPlate(SOFT)
	if plate then
		state.direct = true
		return SOFT, plate
	end
	-- some clients only answer for the "nameplateN" token of the same object; once the
	-- direct way worked, the plate is just not there yet
	if state.direct then
		if exists then return SOFT end
		return nil, nil, true
	end
	for token in pairs(plates) do
		if Ask(UnitIsGameObject, token) == true or Ask(UnitIsUnit, token, SOFT) == true then
			plate = GetPlate(token)
			if plate then return token, plate end
		end
	end
	if exists then return SOFT end
	return nil, nil, true
end

-- Name and action icon of the object above the light, in the category's color.
local Label = {}
Label.__index = Label

function Glow.NewLabel()
	local frame = CreateFrame("Frame")
	frame:SetSize(1, 1)
	frame:Hide()
	local label = setmetatable({frame = frame}, Label)
	label.icon = frame:CreateTexture(nil, "OVERLAY")
	label.icon:SetSize(22, 22)
	label.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label.name:SetPoint("CENTER")
	label.name:SetShadowOffset(1, -1)
	label.progress = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label.progress:SetPoint("LEFT", label.name, "RIGHT", 4, 0)
	label.font, label.height, label.flags = label.name:GetFont()
	return label
end

-- unit: the object (its own icon), or nil and the category whose sample icon shows (the
-- preview). category: whose look settings apply (nil: every object's).
function Label:Show(anchor, unit, name, category, progress, followAlpha, iconCategory)
	local showName, showIcon = Look(category, "showName"), Look(category, "showIcon")
	if db.glowOnly or not (showName or showIcon) then
		self:Hide()
		return
	end
	local frame = self.frame
	local hasIcon = false
	if showIcon and unit then
		hasIcon = Ask(SetUnitCursorTexture, self.icon, unit, nil, true) == true
	elseif showIcon then
		self.icon:SetTexture(CURSORS .. (Glow.SAMPLE_CURSORS[iconCategory or category] or "Interact"))
		hasIcon = true
	end
	self.icon:SetShown(hasIcon)
	self.name:SetText(name or "")
	self.name:SetShown(showName)
	self.progress:SetText(progress or "")
	self.progress:SetShown(showName and progress ~= nil)
	self.icon:ClearAllPoints()
	if showName then
		local height = (self.height or 12) * Look(category, "textSize") / 100
		local file = fontFiles[Look(category, "font")] or self.font
		if not (file and pcall(self.name.SetFont, self.name, file, height, self.flags)) and self.font then
			self.name:SetFont(self.font, height, self.flags)
		end
		self.icon:SetPoint("BOTTOM", frame, "CENTER", 0, height / 2 + 2)
	else
		self.icon:SetPoint("CENTER")
	end
	if self.anchor ~= anchor then
		self.anchor = anchor
		frame:SetParent(anchor)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", anchor, "CENTER")
		local ok, level = pcall(anchor.GetFrameLevel, anchor)
		if ok and type(level) == "number" then frame:SetFrameLevel(level + 2) end
	end
	frame:SetIgnoreParentAlpha(not followAlpha)
	self.category = category
	frame:Show()
end

-- The name takes the light's color, dimmed on a refused object.
function Label:SetState(stateName, r, g, b)
	self.name:SetTextColor(r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55)
	self.frame:SetAlpha(stateName == "locked" and (db.hideLocked and 0 or 0.6) or 1)
end

function Label:Hide()
	local frame = self.frame
	frame:Hide()
	frame:ClearAllPoints()
	frame:SetParent(nil)
	self.anchor = nil
end


--[[ The light on the target ]]--

local glow, label
local current = {} -- anchor, unit, category, state, pending, since, name, progress, guid
local native, muted -- nameplate frames hidden: the one the light rides, the one of an unlit target in combat

local function SetFrameAlpha(frame, alpha)
	pcall(frame.SetAlpha, frame, alpha)
end

local function UnitFrameOf(plate)
	return plate.UnitFrame
end

-- (a forbidden nameplate errors when read: pcall, without making a closure every check)
local function PlateFrame(plate)
	local ok, frame = pcall(UnitFrameOf, plate)
	if ok and type(frame) == "table" then return frame end
end

local function RestoreNative()
	if native then
		SetFrameAlpha(native, 1)
		native = nil
	end
end

-- Hides what the game draws on the nameplate the light rides: our name replaces it.
local function HideNative(plate)
	local frame = PlateFrame(plate)
	if frame ~= native then RestoreNative() end
	if frame and pcall(frame.SetAlpha, frame, 0) then native = frame end
end

local function Unmute()
	if muted and muted ~= native then SetFrameAlpha(muted, 1) end
	muted = nil
end

-- Nameplates the player shows anyway for this kind of unit are left alone.
local PLATE_CVARS = {enemy = {"nameplateShowEnemies"}, player = {"nameplateShowFriendlyPlayers", "nameplateShowFriends"},
	npc = {"nameplateShowFriendlyNpcs", "nameplateShowFriends"}}

local function PlateOwed(unit)
	if Ask(UnitIsGameObject, unit) == true or Ask(UnitIsDead, unit) == true then return false end
	local hostile = Ask(UnitCanAttack, "player", unit)
	if hostile == nil then return true end
	local kind = hostile and "enemy" or Ask(UnitIsPlayer, unit) == true and "player" or "npc"
	local known = false
	for _, name in ipairs(PLATE_CVARS[kind]) do
		local value = ReadCVar(name)
		if value == "1" then return true end
		known = known or value ~= nil
	end
	return not known
end

-- In combat the gate stays open (settings are locked): the nameplate of a target that
-- does not glow is hidden while it is the target.
local function Mute(plate)
	local frame = PlateFrame(plate)
	if frame ~= muted then Unmute() end
	if frame and frame ~= native and pcall(frame.SetAlpha, frame, 0) then muted = frame end
end


--[[ Silhouette: the light passes behind the character ]]--

-- The interface is always drawn over the world: nothing can go behind a 3D model. The
-- character is the one model whose place on the screen is known without measuring (the
-- camera looks at it, its size depends on the zoom only), so an elliptic mask cuts the
-- light out there, and it seems to pass behind.
local BODY_HEIGHT = 1.9 -- character height in screen heights, camera at 1 yard, default field of view

local silhouette = {}

local function Smoothstep(low, high, value)
	local t = Clamp((value - low) / (high - low), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Width and height of the character on the screen and its feet below the middle; nil in
-- first person.
local function MeasureBody()
	local zoom = Ask(GetCameraZoom)
	if not zoom or zoom < 2 then return end
	if not silhouette.fov then
		silhouette.fov = math.tan(math.rad((tonumber(ReadCVar("cameraFov")) or 90) / 2))
	end
	local height = BODY_HEIGHT * UIParent:GetHeight() / zoom / silhouette.fov * db.bodyScale / 100
	local width = height * 0.45
	if Ask(IsMounted) == true then
		height = height * 1.3
		width = height * 0.8
	end
	height = height * 0.9 -- seen from above, the body looks shorter
	return width, height, (db.bodyShift / 100 - 0.92) * height
end

local function UpdateSilhouette(self, elapsed)
	self.wait = (self.wait or 0) - elapsed
	if self.wait > 0 then return end
	self.wait = SILHOUETTE_RATE
	local mask, outline = silhouette.mask, silhouette.outline
	local width, height, feet = MeasureBody()
	if not width then
		if silhouette.w ~= 0.01 then
			silhouette.w, silhouette.h = 0.01, 0.01
			mask:SetSize(0.01, 0.01)
		end
		outline:Hide()
		return
	end
	-- only when the object is farther than the character, so higher on the screen than its
	-- feet; nearer the camera, the light covers the character
	local strength = 1
	if current.anchor then
		local _, y = glow:ScreenPosition()
		if y then strength = Smoothstep(feet - 0.1 * height, feet + 0.2 * height, y - UIParent:GetHeight() / 2) end
	end
	local middle = feet + height / 2
	local w, h = width * 1.9, height * 1.5
	local mw, mh = math.max(w * strength, 0.01), math.max(h * strength, 0.01)
	-- moving a mask redraws every layer it cuts: only when it changed by half a pixel
	if math.abs(mw - (silhouette.w or 0)) + math.abs(mh - (silhouette.h or 0)) + math.abs(middle - (silhouette.y or 0)) > 0.5 then
		silhouette.w, silhouette.h, silhouette.y = mw, mh, middle
		mask:SetSize(mw, mh)
		mask:SetPoint("CENTER", silhouette.owner, "CENTER", 0, middle)
	end
	if silhouette.show then
		outline:SetSize(w * 0.55 / 0.74, h * 0.55 / 0.74) -- the fully hidden part, drawn by the ring
		outline:SetPoint("CENTER", silhouette.owner, "CENTER", 0, middle)
		outline:Show()
	else
		outline:Hide()
	end
end

local function CreateSilhouette()
	local owner = CreateFrame("Frame", nil, UIParent)
	owner:SetSize(1, 1)
	owner:SetPoint("CENTER", WorldFrame or UIParent, "CENTER")
	owner:Hide()
	local ok, mask = pcall(owner.CreateMaskTexture, owner)
	if not ok or not mask then
		silhouette.failed = L.GLOW_FAIL_MASK
		return
	end
	local set = pcall(mask.SetTexture, mask, FX.MEDIA .. "hole.tga", "CLAMPTOWHITE", "CLAMPTOWHITE")
	if not set then
		silhouette.failed = L.GLOW_FAIL_MASK
		return
	end
	mask:SetSize(0.01, 0.01)
	mask:SetPoint("CENTER", owner, "CENTER")
	local outline = owner:CreateTexture(nil, "OVERLAY")
	outline:SetTexture(FX.MEDIA .. "ring.tga")
	outline:SetVertexColor(1, 0.25, 0.25, 0.9)
	outline:Hide()
	silhouette.owner, silhouette.mask, silhouette.outline = owner, mask, outline
	owner:SetScript("OnUpdate", ns:Track("glow:silhouette", UpdateSilhouette))
end

local function ApplySilhouette()
	local wanted = current.anchor ~= nil and Look(current.category, "silhouette") and not silhouette.failed
	if not (wanted or silhouette.show or silhouette.owner) then return end
	if not silhouette.owner and not silhouette.failed then CreateSilhouette() end
	if not silhouette.owner then return end
	if glow and not glow:SetMask(wanted and silhouette.mask or nil) then
		glow:SetMask(nil)
		silhouette.failed = L.GLOW_FAIL_MASK
		wanted = false
	end
	silhouette.owner:SetShown(wanted or silhouette.show or false)
end

function Glow:ShowZone(shown)
	silhouette.show = shown or nil
	ApplySilhouette()
	Notify()
end

function Glow:IsZoneShown()
	return silhouette.show == true
end

function Glow:SilhouetteFailure()
	return silhouette.failed
end


--[[ Attaching ]]--

-- Gives a glow the look of a category (nil: the look of every object) and the color of
-- colorCategory (default: the same).
function Glow:Style(instance, category, instant, colorCategory)
	instance:SetEffect(Look(category, "effect"))
	instance:SetSize(Look(category, "size"))
	instance:SetIntensity(Look(category, "intensity"))
	local r, g, b = self:GetColor(colorCategory or category or "quest")
	instance:SetColor(r, g, b, instant)
end

local function Release(withGhost)
	RestoreNative()
	if not current.anchor then return end
	if withGhost then FX.Ghost(glow) end
	glow:Detach()
	label:Hide()
	current.anchor, current.category, current.pending = nil, nil, nil
	ApplySilhouette()
end

local function Attach(plate, unit, category, stateName)
	glow = glow or FX.New()
	label = label or Glow.NewLabel()
	local r, g, b = Glow:GetColor(category)
	glow:Setup(Look(category, "effect"), Look(category, "size"), Look(category, "intensity"), r, g, b, stateName)
	glow:Attach(plate, Look(category, "offsetY"), Look(category, "followAlpha"))
	current.anchor, current.unit, current.category, current.state, current.pending = plate, unit, category, stateName, nil
	ApplySilhouette()
end

local function ShowLabel(unit)
	label:Show(current.anchor, unit, current.name, current.category, current.progress, Look(current.category, "followAlpha"))
	label:SetState(current.state, Glow:GetColor(current.category))
end

-- A new state shows once it held a moment (no flicker at the edge of reach).
local function ProposeState(stateName)
	if stateName == current.state then
		current.pending = nil
		return
	end
	local now = GetTime()
	if current.pending ~= stateName then
		current.pending, current.since = stateName, now
	elseif now - current.since >= (stateName == "locked" and LOCK_HOLD or STATE_HOLD) then
		current.pending = nil
		current.state = stateName
		glow:SetState(stateName)
		label:SetState(stateName, Glow:GetColor(current.category))
	end
end

local function Present(plate, unit, name, category, stateName, progress, guid)
	local fresh = current.anchor ~= plate or current.category ~= category or current.guid ~= guid
	if fresh then
		Release(current.anchor ~= nil and current.anchor ~= plate)
		Attach(plate, unit, category, stateName)
	else
		ProposeState(stateName)
	end
	current.guid = guid
	-- the game may give the frame its alpha back: hidden again on every check
	if db.glowOnly then RestoreNative() else HideNative(plate) end
	if fresh or name ~= current.name or progress ~= current.progress then
		current.name, current.progress = name, progress
		ShowLabel(unit)
	end
end


--[[ Deciding ]]--

local lastReport

local function Report(text)
	if not db.debug or text == lastReport then return end
	lastReport = text
	ns:Print(L.GLOW_DEBUG_PREFIX .. text)
end

local function Paused()
	if db.hideInCombat and (state.combat or InCombatLockdown()) then return true end
	return db.hideInInstance and state.instance
end

-- The target is not lit: the gate closes. When it cannot (combat), the nameplate the game
-- shows is returned so it can be hidden.
local function Shut(unit, plate)
	SetGate(false)
	if plate and db.exclusive and state.gate ~= false and not PlateOwed(unit) then return plate end
end

local function CategoryName(category)
	return L["GLOW_CAT_" .. (category or "none"):upper()] or tostring(category)
end

-- What the interaction target is and whether it glows. Returns a nameplate to hide.
local function Decide()
	if not state.active or state.leaving then
		Release()
		return
	end
	if Paused() then
		Release()
		local unit, plate = Resolve()
		if unit then return Shut(unit, plate) end
		SetGate(false)
		return
	end
	local unit, plate, unknown = Resolve()
	if not unit then
		SetGate(unknown == true) -- not knowing, let the game show its target
		Release(true)
		current.guid = nil
		return
	end
	local category, unable, progress, guid, why, name
	if Ask(UnitIsGameObject, unit) == true then
		local hasCursor, cursorCategory, greyed, cursor = ReadCursor(unit)
		local entry = ClassifyObject(unit, cursorCategory, hasCursor)
		name, guid = entry.name, entry.guid
		if entry.ignored then
			Report(L.GLOW_DEBUG_IGNORED:format(tostring(name)))
			Release(true)
			return Shut(unit, plate)
		end
		category, unable, progress, why = entry.category, greyed, entry.progress, entry.why
		if db.debug then
			Report(L.GLOW_DEBUG_OBJECT:format(tostring(name), CategoryName(category), tostring(cursor), tostring(entry.id),
				tostring(why)))
		end
	elseif HasLoot(unit) then
		category, guid, name = "loot", Ask(UnitGUID, unit), Ask(UnitName, unit)
	else
		Release(true)
		return Shut(unit, plate)
	end
	if not category or not db.categories[category] then
		Release(true)
		return Shut(unit, plate)
	end
	if db.hideUntrained and Trained(category) == false then
		Report(L.GLOW_DEBUG_UNTRAINED:format(tostring(name)))
		Release(true)
		return Shut(unit, plate)
	end
	local stateName = ReadState(unit, unable)
	if stateName == "locked" and db.hideLocked then
		Release(true)
		return Shut(unit, plate)
	end
	SetGate(true)
	if not plate then
		Release() -- the nameplate comes a moment after the gate opens
		state.awaiting = true
		return
	end
	Present(plate, unit, name, category, stateName, progress, guid)
end

function Evaluate()
	if not db then return end
	state.awaiting = false
	local plate = Decide()
	if plate then Mute(plate) else Unmute() end
end


--[[ Driver ]]--

local driver = CreateFrame("Frame")
driver:Hide()
driver.wait = 0
local TrackedEvaluate = ns:Track("glow:check", function() Evaluate() end) -- /fh mem
driver:SetScript("OnUpdate", function(self, elapsed)
	self.wait = self.wait - elapsed
	if self.wait > 0 then return end
	TrackedEvaluate()
	self.wait = (current.anchor or state.awaiting) and POLL_ACTIVE or POLL_IDLE
end)

local function SetActive(value)
	value = value and true or false
	if value == state.active then return end
	state.active = value
	driver:SetShown(value)
	if value then
		ApplyCVars()
	else
		Release()
		Unmute()
		RestoreCVars()
	end
end

-- Settings that need more than the next check.
local APPLY = {}

local function Restyle()
	if current.anchor then
		Glow:Style(glow, current.category)
		glow:Move(current.anchor, Look(current.category, "offsetY"), Look(current.category, "followAlpha"))
		ShowLabel(current.unit)
		ApplySilhouette()
	end
end

for key in pairs(LOOK) do APPLY[key] = Restyle end
APPLY.glowOnly = function()
	if current.anchor then
		if db.glowOnly then RestoreNative() else HideNative(current.anchor) end
		ShowLabel(current.unit)
	end
end
APPLY.range = function() if state.active then ApplyCVars() end end
APPLY.arc = APPLY.range
APPLY.exclusive = function()
	state.gate = nil
	Evaluate()
end
APPLY.hideLocked = Evaluate
APPLY.hideUntrained = Evaluate
APPLY.hideInCombat = Evaluate
APPLY.hideInInstance = Evaluate
APPLY.enabled = function() Glow:Refresh() end
APPLY.bodyScale = function() end
APPLY.bodyShift = APPLY.bodyScale
APPLY.debug = function() lastReport = nil end

-- Changes a setting (clamped if numeric). A look setting changes for one category, which
-- then has its own value, or for every object (categories lose their own value of it).
function Glow:Set(key, value, category)
	local limits = LIMITS[key]
	if limits and type(value) == "number" then value = Clamp(math.floor(value + 0.5), limits[1], limits[2]) end
	if LOOK[key] and category then
		local own = db.own[category] or {}
		if value == db[key] then own[key] = nil else own[key] = value end
		db.own[category] = next(own) and own or nil
	else
		db[key] = value
		if LOOK[key] then
			for name, own in pairs(db.own) do
				own[key] = nil
				if not next(own) then db.own[name] = nil end
			end
		end
	end
	if APPLY[key] then APPLY[key]() end
	Notify()
end

function Glow:ClearOwn(category)
	db.own[category] = nil
	Restyle()
	Notify()
end

function Glow:SetCategoryShown(category, shown)
	db.categories[category] = shown and true or false
	Evaluate()
	Notify()
end

-- Without a color, the category gets its original one back.
function Glow:SetColor(category, r, g, b)
	local color, default = db.colors[category], DEFAULT_COLORS[category]
	color[1], color[2], color[3] = Clamp(r or default[1], 0, 1), Clamp(g or default[2], 0, 1), Clamp(b or default[3], 0, 1)
	if current.anchor and current.category == category then
		glow:SetColor(color[1], color[2], color[3])
		label:SetState(current.state, color[1], color[2], color[3])
	end
	Notify()
end

-- Back to the original settings. What was learned (quest objects, chests) and the ignored
-- objects stay.
local KEPT = {enabled = true, migrated = true, ignored = true, containers = true, questObjects = true, savedCVars = true, cvarsReturned = true,
	window = true}

function Glow:Reset()
	for key, value in pairs(ns.defaults.glow) do
		if not KEPT[key] then
			if type(value) == "table" then
				db[key] = CopyTable(value)
			else
				db[key] = value
			end
		end
	end
	silhouette.show = nil
	lastReport = nil
	Release()
	if state.active then ApplyCVars() end
	Notify()
end


--[[ Ignored objects ]]--

-- Name of the world object targeted now, lit or not.
function Glow:TargetName()
	local unit = Resolve()
	if unit and Ask(UnitIsGameObject, unit) == true then
		local name = Ask(UnitName, unit)
		if type(name) == "string" and name ~= "" then return name end
	end
end

-- Ignores an object by name (all objects of that name), or stops ignoring it. Returns
-- whether it is ignored now.
function Glow:ToggleIgnored(name)
	local key = Fold(name)
	if key == "" then return end
	db.ignored[key] = not db.ignored[key] and name or nil
	wipe(cache)
	lastReport = nil
	Evaluate()
	Notify()
	return db.ignored[key] ~= nil
end

function Glow:IgnoreTarget()
	local name = self:TargetName()
	if not name then
		ns:Print(L.GLOW_IGNORE_NONE)
		return
	end
	ns:Print((self:ToggleIgnored(name) and L.GLOW_IGNORED or L.GLOW_UNIGNORED):format(name))
end

function Glow:IgnoredNames()
	local names = {}
	for _, name in pairs(db.ignored) do names[#names + 1] = name end
	table.sort(names)
	return names
end

function Glow:ClearIgnored()
	wipe(db.ignored)
	wipe(cache)
	Evaluate()
	Notify()
end


--[[ Interact key ]]--

-- Using the targeted object is a protected action: only a key binding of the game can do
-- it. The glow window gives access to the game's own "Interact with target" binding.
local INTERACT = "INTERACTTARGET"

local function BindingContext()
	return C_KeyBindings and C_KeyBindings.GetBindingContextForAction and Ask(C_KeyBindings.GetBindingContextForAction, INTERACT)
end

function Glow:GetInteractKey()
	return (GetBindingKey(INTERACT, nil, BindingContext()))
end

-- The binding a key already serves, other than interacting.
function Glow:KeyOwner(key)
	local action = GetBindingAction(key, nil, BindingContext())
	if type(action) ~= "string" or action == "" or action == INTERACT then return end
	return _G["BINDING_NAME_" .. action] or action
end

-- Gives the key to "Interact with target" (nil removes it). Returns false and why.
function Glow:SetInteractKey(key)
	if InCombatLockdown() then return false, L.GLOW_KEY_COMBAT end
	local context = BindingContext()
	local first, second = GetBindingKey(INTERACT, nil, context)
	if first then SetBinding(first, nil, context) end
	if second then SetBinding(second, nil, context) end
	local bound = key == nil or SetBinding(key, INTERACT, context)
	if not bound and first then SetBinding(first, INTERACT, context) end
	if second and second ~= key then SetBinding(second, INTERACT, context) end
	local save = SaveBindings or AttemptToSaveBindings
	if save and GetCurrentBindingSet then pcall(save, GetCurrentBindingSet()) end
	Notify()
	if not bound then return false, L.GLOW_KEY_REFUSED:format(key) end
	return true
end


--[[ Module ]]--

function Glow:IsActive()
	return state.active
end

function Glow:Refresh()
	SetActive(ns:IsModuleActive("sparkles") and db.enabled)
	Notify()
end

function Glow:Status()
	ns:Print(L.GLOW_STATUS:format(tostring(state.active), tostring(state.gate), tostring(db.exclusive), Range(), db.arc))
	for _, name in ipairs(MANAGED) do
		local saved = db.savedCVars and db.savedCVars[name]
		print(("  %s = %s  |cff888888(%s)|r"):format(name, tostring(ReadCVar(name)), tostring(saved)))
	end
	print("  " .. L.GLOW_STATUS_TRAINED:format(tostring(Trained("herb")), tostring(Trained("ore"))))
	print("  " .. L.GLOW_STATUS_SILHOUETTE:format(tostring(silhouette.failed or Look(nil, "silhouette"))))
end

-- Migrates the settings of the old sparkles (glints on ore, herbs and corpses).
local function Migrate()
	local old = ns.db.sparkles
	if db.migrated then return end
	db.migrated = true
	if type(old.saved) == "table" and not db.savedCVars then
		db.savedCVars = old.saved -- the player's own values, still to be given back
	end
	old.saved = nil
	if old.ore == false then db.categories.ore = false end
	if old.herbs == false then db.categories.herb = false end
	if old.corpses == false then db.categories.loot = false end
	if old.questObjects == false then db.categories.quest = false end
	old.ore, old.herbs, old.corpses, old.questObjects, old.interactIcons = nil, nil, nil, nil, nil
end

-- Removes what makes no sense any more (a category or effect from a newer version...).
local function Validate()
	for category, own in pairs(db.own) do
		if not DEFAULT_COLORS[category] or type(own) ~= "table" then
			db.own[category] = nil
		else
			for key, value in pairs(own) do
				local limits = LIMITS[key]
				if not LOOK[key] or type(value) ~= type(ns.defaults.glow[key]) or (key == "effect" and not FX.EFFECTS[value]) then
					own[key] = nil
				elseif limits then
					own[key] = Clamp(value, limits[1], limits[2])
				end
			end
			if not next(own) then db.own[category] = nil end
		end
	end
	if not FX.EFFECTS[db.effect] then db.effect = "aura" end
	if not fontFiles[db.font] then db.font = "game" end
	for key, limits in pairs(LIMITS) do
		if type(db[key]) ~= "number" then db[key] = ns.defaults.glow[key] end
		db[key] = Clamp(db[key], limits[1], limits[2])
	end
end

function Glow:OnInitialize()
	db = ns.db.glow
	Migrate()
	Validate()
	probe = UIParent:CreateTexture(nil, "BACKGROUND")
	probe:Hide()
	BuildCursorFiles()
end

local function Command(rest)
	local word = (rest or ""):lower()
	if word == "debug" then
		Glow:Set("debug", not db.debug)
		ns:Print(L.GLOW_DEBUG_STATE:format(db.debug and L.GLOW_ON or L.GLOW_OFF))
	elseif word == "status" then
		Glow:Status()
	elseif word == "ignore" then
		Glow:IgnoreTarget()
	elseif word == "quest" then
		ns.QuestGlow:Debug()
	elseif word == "on" or word == "off" then
		Glow:Set("enabled", word == "on")
		ns:Print(word == "on" and L.GLOW_ENABLED or L.GLOW_DISABLED)
	elseif ns.GlowWindow then
		ns.GlowWindow:Toggle()
	end
end

function Glow:OnLogin()
	state.instance = Ask(IsInInstance) == true
	local events = {
		PLAYER_ENTERING_WORLD = function()
			state.instance = Ask(IsInInstance) == true
			if state.active then ApplyCVars() end
		end,
		ZONE_CHANGED_NEW_AREA = function()
			state.instance = Ask(IsInInstance) == true
		end,
		-- the camera's field of view, read by the silhouette
		CVAR_UPDATE = function(_, name)
			if name == "cameraFov" or name == "CAMERA_FOV" then silhouette.fov = nil end
		end,
		-- account settings may arrive after login and overwrite these
		VARIABLES_LOADED = function()
			if state.active then ApplyCVars() end
		end,
		PLAYER_LOGOUT = function()
			Release()
			Unmute()
			ReturnCVars()
			state.leaving = true
		end,
		-- settings lock in combat: the gate opens just before, so the light still shows
		PLAYER_REGEN_DISABLED = function()
			state.combat = true
			if state.active then SetGate(not db.hideInCombat) end
		end,
		PLAYER_REGEN_ENABLED = function()
			state.combat = false
			local pending = state.pending
			state.pending = nil
			if pending == "apply" and state.active then ApplyCVars() elseif pending == "restore" then RestoreCVars() end
			Evaluate()
		end,
		-- only a nameplate we wait for matters (the lit object's, or an unlit target's in combat)
		NAME_PLATE_UNIT_ADDED = function(_, unit)
			plates[unit] = true
			if state.active and (state.awaiting or state.combat) then Evaluate() end
		end,
		NAME_PLATE_UNIT_REMOVED = function(_, unit)
			plates[unit] = nil
			if current.anchor and GetPlate(unit) == current.anchor then Release(true) end
		end,
		PLAYER_SOFT_INTERACT_CHANGED = function()
			if state.active then
				driver.wait = 0
				Evaluate()
			end
		end,
		QUEST_LOG_UPDATE = function()
			quests.dirty = true
			wipe(cache)
		end,
		WORLD_CURSOR_TOOLTIP_UPDATE = function()
			if state.active and LearnFromTooltip() then
				wipe(cache)
				Evaluate()
			end
		end,
		LOOT_OPENED = function()
			if state.active then LearnContainers() end
		end,
	}
	for event, func in pairs(events) do
		pcall(ns.RegisterEvent, ns, event, func)
	end
	-- the bobber often lands past 15 yards: while the line is out the game searches farther
	local function Line(_, unit)
		if unit ~= "player" then return end
		local out = state.active and db.categories.bobber and Fishing() or false
		if out == state.line then return end
		state.line = out
		ApplyRange()
		wipe(cache)
	end
	for _, event in ipairs({"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP"}) do
		pcall(ns.RegisterEvent, ns, event, Line)
	end
	-- nameplates already on the screen (after /reload)
	for _, plate in ipairs(C_NamePlate and Ask(C_NamePlate.GetNamePlates) or {}) do
		local unit = plate.namePlateUnitToken
		if type(unit) == "string" and not IsSecret(unit) then plates[unit] = true end
	end
	ns:RegisterCommand("glow", Command, "Object glow: window · debug · status · ignore · quest · on/off")
	self:Refresh()
end
