--[[
	ForeverHub - core
	Namespace, event dispatch, saved variables, slash commands and shared helpers.
--]]

local ADDON, ns = ...
ForeverHub = ns

ns.name = "ForeverHub"
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
ns.color = "|cff4fc3f7"

local pairs, type, next, select = pairs, type, next, select


--[[ Allocation profile (/fh mem) ]]--

-- While on, every event, deferred call and tracked function adds up the Lua memory it
-- allocates (KB), to find what fills the addon's memory with garbage. Off it costs one test.
-- Approximate: a garbage collection step inside a call hides part of what it allocated.
local gcCount = collectgarbage
local profile -- {at = start time, kb = {key -> KB}, calls = {key -> count}}

local function Finish(key, before, ...)
	local delta = gcCount("count") - before
	local kb, calls = profile.kb, profile.calls
	if delta > 0 then kb[key] = (kb[key] or 0) + delta end
	calls[key] = (calls[key] or 0) + 1
	return ...
end

-- Wraps func so its allocations are counted under key while the profile runs.
function ns:Track(key, func)
	return function(...)
		if not profile then return func(...) end
		local before = gcCount("count")
		return Finish(key, before, func(...))
	end
end

-- Where a handler was registered ("QuestGlow.lua:456"), to tell apart the modules that
-- listen to the same event.
local origins = setmetatable({}, {__mode = "k"})

local function Origin()
	local stack = debugstack and debugstack(3, 4, 0)
	-- lines look like Interface/AddOns/!ForeverHub/QuestGlow.lua:456: or [string "@...lua"]:456:
	for file in (stack or ""):gmatch("AddOns[/\\]!ForeverHub[/\\]([^:]+:%d+)") do
		file = file:gsub("[\"%]]", "")
		if not file:find("^Core%.lua") then return file end
	end
	return "?"
end


--[[ Events ]]--

-- One dispatcher frame for the whole addon. Handlers receive (event, ...).
local dispatcher = CreateFrame("Frame")
local handlers = {}

dispatcher:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if profile then
		for i = 1, #list do
			local func = list[i]
			local before = gcCount("count")
			Finish(event .. " @" .. (origins[func] or "?"), before, func(event, ...))
		end
		return
	end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

function ns:RegisterEvent(event, func)
	origins[func] = origins[func] or Origin()
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		dispatcher:RegisterEvent(event)
	end
	list[#list + 1] = func
end

-- Copy-on-write so that unregistering from inside a handler is safe.
function ns:UnregisterEvent(event, func)
	local list = handlers[event]
	if not list then return end

	local copy = {}
	for i = 1, #list do
		if list[i] ~= func then
			copy[#copy + 1] = list[i]
		end
	end

	if #copy == 0 then
		handlers[event] = nil
		dispatcher:UnregisterEvent(event)
	else
		handlers[event] = copy
	end
end

-- Runs func once when event fires, then unregisters it.
function ns:RegisterEventOnce(event, func)
	local function once(...)
		ns:UnregisterEvent(event, once)
		func(...)
	end
	ns:RegisterEvent(event, once)
end


--[[ Combat queue ]]--

-- Protected frame operations requested during combat are replayed afterwards.
local combatQueue = {}

function ns:RunOutOfCombat(key, func)
	if InCombatLockdown() then
		combatQueue[key] = func
	else
		func()
	end
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	local key, func = next(combatQueue)
	while key do
		combatQueue[key] = nil
		func()
		key, func = next(combatQueue)
	end
end)


--[[ Saved variables ]]--

ns.defaults = {
	modules = {bags = true, mover = true, errors = true, disenchant = true, sparkles = true},
	positions = {}, -- ForeverHub's own windows
	errors = {
		chat = true,
		sound = false,
		showLocals = false,
		popup = false,
		suppressBlizzard = true,
	},
	mover = {
		save = "session", -- "off" | "session" | "always"
		modifier = "NONE", -- modifier key required to drag
		scaling = true,
		positions = {},
	},
	bags = {
		columns = 12,
		bankColumns = 16,
		itemScale = 1,
		spacing = 2,
		reverseBags = false,
		qualityBorder = true,
		junkIcon = true,
		questIcon = true,
		tooltipCounts = true,
		splitBags = true, -- profession bags in their own groups
		colorBags = true, -- tint the slots of profession bags
		sellJunkButton = true,
		unusable = true, -- red tint on items this character cannot use
		newGlow = true,
		itemLevel = true,
		boe = true,
		lowSpace = 4, -- free slots left when the counter turns red
		upgrade = true, -- % better/worse than the equipped item
		upgradeMode = "stats", -- "stats" (class weighted) or "level"
		upgradeOnly = false, -- show only improvements
		disenchantMark = true, -- icon on gear worth disenchanting (enchanters)
		disenchantMarkAlways = false, -- ...also on characters without Enchanting
		junkMarked = {}, -- itemID -> true: sold as junk although not gray
		junkKeep = {}, -- itemID -> true: gray items never sold
		showBagBar = {inventory = false, bank = false},
		hiddenBags = {},
		positions = {},
	},
	minimap = {hide = false, angle = 205},
	merchant = {
		restockEnabled = true,
		restock = {}, -- "Name-Realm" -> {itemID -> amount to keep in the bags}
		autoSell = true, -- sell junk when a merchant opens
		autoRepair = true,
		guildRepair = true, -- use guild funds first when allowed
	},
	automation = {
		fasterLoot = true, -- take everything at once when auto loot is on
		lootLimit = true, -- warn when a stack does not fit the item's unique limit
		autoRes = true, -- accept resurrections (not from someone in combat)
		hideErrors = true, -- hide the red error spam, keep the important ones
	},
	durability = {show = true, warn = true, threshold = 20},
	xp = {show = true},
	actionbars = {manaCost = true},
	professions = {
		shopping = true, -- shopping list, its window and the merchant button
		guide = true, -- leveling suggestions beside the profession window
		guideCollapsed = false,
		tooltip = true, -- recipes that use a material
		skinning = true, -- Skinning skill on creature tooltips
		recipes = {}, -- recipeID -> {n = name, r = {itemID, amount...}, o = product, i = icon}
		chars = {}, -- "Name-Realm" -> {[skill line] = {name, skill, max, known = {[recipeID] = difficulty}}}
		list = {}, -- "Name-Realm" -> {[recipeID] = crafts}
		vendor = {}, -- itemID -> unit price at a vendor
	},
	performance = {show = true, fps = true, latency = true, memory = false, clock = false},
	gold = {
		show = true,
		days = {}, -- "Name-Realm" -> {day = "YYYY-MM-DD", gained, spent}
	},
	tooltip = {itemLevel = true, ids = false, unitPrice = true, targetOfTarget = true, disenchant = true, disenchantModifier = "NONE"},
	chat = {
		copyButton = true, urls = true,
		tooltips = true, -- tooltip when the mouse is over a link
		itemInfo = true, -- icon, item level and upgrade next to item links
		shortChannels = true, -- [2. Trade - City] -> [T]
		playerInfo = true, -- class icon and level before the name of who speaks
		highlight = true, keywords = "", highlightSound = true, -- the character's name and chosen words
		history = true, -- lines and typed text back after /reload and login
		arrows = true, -- arrow keys go through what was typed, without Alt
		altInvite = true, -- Alt+click on a name invites
		hideButtons = true, fadeTabs = true, -- look (after /reload)
		channelBar = true, -- buttons to talk in each channel (right-click: show only that channel)
		filterButton = true, -- button on each chat window: open a tab with only one channel
		skin = true, -- tabs, windows and edit box in the look of the channel bar (after /reload)
		terms = true, -- WoW terms (LFM, LoS, RFC...) become links with their meaning
	},
	sparkles = {
		questLoot = true, -- the game's sparkle on quest items, kept on (the object glow: ns.db.glow)
		questMobs = true, -- quest beacon on every nameplate of a creature a quest needs
		questProgress = true, questBeam = true, -- "3/8" beside the mark, beam rising from it
		questColor = "gold", questScale = 100, -- beacon color and size (%)
		questIntensity = 50, -- strength of the light (%); the mark and progress stay sharp
	},
	qol = {
		questLevels = true, -- [16] before quest names (tracker and log)
		readyXP = true, -- XP of the quests ready to hand in, on the experience line
		bestReward = true, -- most valuable and best upgrade among the reward choices
		mailTakeAll = true, mailRecipients = true,
		openBoxes = true, -- button that opens the next container in the bags
		ammo = true, ammoWarn = true, ammoLow = 200, -- ammo and soul shards: footer counter, warning
		slotLevels = true, -- item level on the character and inspect slots
		buffReminders = true, petReminders = true,
	},
	cvars = {}, -- console variable -> value chosen in the options (only these are managed)
}

local function MergeDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then
				target[k] = {}
			end
			MergeDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

-- Modules register themselves here and are initialised in TOC order.
local modules = {}

function ns:NewModule(name)
	local module = {name = name}
	modules[#modules + 1] = module
	ns[name] = module
	return module
end

local function SafeCall(module, method)
	local func = module[method]
	if func then
		local ok, err = pcall(func, module)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end

	ForeverHubDB = ForeverHubDB or {}
	MergeDefaults(ForeverHubDB, ns.defaults)
	ns.db = ForeverHubDB

	for i = 1, #modules do
		SafeCall(modules[i], "OnInitialize")
	end
end)

ns:RegisterEventOnce("PLAYER_LOGIN", function()
	for i = 1, #modules do
		SafeCall(modules[i], "OnLogin")
	end
	ns:CheckConflicts()
end)


--[[ Conflicts with the addons this one replaces ]]--

-- BugSack cannot run without !BugGrabber, so the grabber is what matters for errors.
ns.replaces = {
	bags = {"Bagnon", "BagBrother"},
	mover = {"BlizzMove"},
	errors = {"!BugGrabber"},
	disenchant = {"DisenchantBuddy"},
	sparkles = {"ForeverLootSparkles", "Lueur"},
}

-- Returns the first loaded addon that conflicts with a module, if any.
function ns:GetConflict(module)
	for _, addon in ipairs(ns.replaces[module]) do
		if C_AddOns.IsAddOnLoaded(addon) then
			return addon
		end
	end
end

function ns:CheckConflicts()
	local found = {}
	for module in pairs(ns.replaces) do
		local addon = ns:GetConflict(module)
		if addon and ns.db.modules[module] then
			found[#found + 1] = addon
		end
	end
	if #found > 0 then
		ns:Print(ns.L.CONFLICTS:format(table.concat(found, ", ")))
	end
end

function ns:DisableReplacedAddons()
	local character = UnitName("player")
	for _, list in pairs(ns.replaces) do
		for _, addon in ipairs(list) do
			if C_AddOns.DoesAddOnExist(addon) then
				C_AddOns.DisableAddOn(addon, character)
			end
		end
	end
	for _, addon in ipairs({"BugSack", "Bagnon_Bank", "Bagnon_Config", "Bagnon_GuildBank", "BlizzMove_Debug", "Leatrix_Plus"}) do
		if C_AddOns.DoesAddOnExist(addon) then
			C_AddOns.DisableAddOn(addon, character)
		end
	end
	C_UI.Reload()
end

-- Leatrix Plus option turned on (ForeverHub then leaves that job to it, never doing it twice).
function ns:LeatrixHas(option)
	return LeaPlusDB ~= nil and LeaPlusDB[option] == "On" and C_AddOns.IsAddOnLoaded("Leatrix_Plus")
end

-- A module is active when enabled in settings and the original addon is not running.
function ns:IsModuleActive(module)
	return ns.db.modules[module] and not ns:GetConflict(module)
end


--[[ Helpers ]]--

function ns:Print(...)
	print(ns.color .. ns.name .. "|r:", ...)
end

ns.playerName = UnitName("player")
ns.realm = GetRealmName()

-- Window positions are saved as {point, relPoint, x, y}. Only complete entries are
-- saved and applied: a bad one (saved while the frame had no anchor) used to break
-- the window's creation, so it is dropped and the default position is used instead.
function ns:SavePosition(store, key, frame)
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if type(point) == "string" and type(relPoint) == "string" and type(x) == "number" and type(y) == "number" then
		store[key] = {point, relPoint, x, y}
	end
end

function ns:ApplyPosition(store, key, frame)
	local pos = store and store[key]
	if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
		and type(pos[3]) == "number" and type(pos[4]) == "number" then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		return true
	end
	if store then
		store[key] = nil
	end
	return false
end

-- Calls func on the next frame, coalescing repeated requests with the same key.
do
	local pending = {}
	local runner = CreateFrame("Frame")
	runner:Hide()
	runner:SetScript("OnUpdate", function(self)
		self:Hide()
		local key, func = next(pending)
		while key do
			pending[key] = nil
			if profile then
				local before = gcCount("count")
				Finish("defer:" .. key, before, func())
			else
				func()
			end
			key, func = next(pending)
		end
	end)

	function ns:Defer(key, func)
		pending[key] = func
		runner:Show()
	end
end


--[[ Slash commands ]]--

local commands = {}

function ns:RegisterCommand(name, func, help)
	commands[name] = {func = func, help = help}
end

SLASH_FOREVERHUB1 = "/fh"
SLASH_FOREVERHUB2 = "/foreverhub"
SlashCmdList.FOREVERHUB = function(msg)
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()

	local entry = commands[cmd]
	if entry then
		entry.func(rest)
	elseif cmd == "" or cmd == "config" or cmd == "options" then
		ns:OpenOptions()
	else
		ns:Print(ns.L.COMMANDS)
		local names = {}
		for name in pairs(commands) do
			names[#names + 1] = name
		end
		table.sort(names)
		for _, name in ipairs(names) do
			print(("  |cffffd200/fh %s|r - %s"):format(name, commands[name].help))
		end
	end
end

ns:RegisterCommand("disableold", function() ns:DisableReplacedAddons() end, "Disable Bagnon, BlizzMove and BugSack and reload")

-- /fh mem: starts the allocation profile; run again to see what allocated most and stop.
local PROFILE_ROWS = 15

local function ProfileReport()
	local L = ns.L
	local minutes = math.max((GetTime() - profile.at) / 60, 1 / 60)
	local keys, total = {}, 0
	for key, kb in pairs(profile.kb) do
		keys[#keys + 1] = key
		total = total + kb
	end
	table.sort(keys, function(a, b) return profile.kb[a] > profile.kb[b] end)
	ns:Print(L.MEM_REPORT:format(minutes, total / 1024, total / 1024 / minutes))
	for i = 1, math.min(#keys, PROFILE_ROWS) do
		local key = keys[i]
		local kb = profile.kb[key]
		print(("  |cffffd200%s|r  %.0f KB (%.0f KB/min)  %s"):format(key, kb, kb / minutes,
			L.MEM_CALLS:format(profile.calls[key] or 0)))
	end
	if #keys == 0 then print("  " .. L.MEM_NOTHING) end
end

ns:RegisterCommand("mem", function()
	if profile then
		ProfileReport()
		profile = nil
	else
		profile = {at = GetTime(), kb = {}, calls = {}}
		ns:Print(ns.L.MEM_STARTED)
	end
end, "Measure what allocates memory (run again to see the result)")


--[[ Addon compartment (minimap addon menu) ]]--

function ForeverHub_OnCompartmentClick(_, button)
	if button == "RightButton" then
		ns:OpenOptions()
	elseif ns.ErrorWindow and ns:IsModuleActive("errors") then
		ns.ErrorWindow:Toggle()
	else
		ns:OpenOptions()
	end
end

function ForeverHub_OnCompartmentEnter(_, frame)
	GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
	GameTooltip:AddLine(ns.color .. ns.name .. "|r " .. ns.version)
	if ns.Errors and ns:IsModuleActive("errors") then
		GameTooltip:AddLine(ns.L.ERRORS_COUNT:format(ns.Errors:CountSession()), 1, 1, 1)
	end
	GameTooltip:AddLine(ns.L.COMPARTMENT_HINT, 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

function ForeverHub_OnCompartmentLeave()
	GameTooltip:Hide()
end
