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


--[[ Events ]]--

-- One dispatcher frame for the whole addon. Handlers receive (event, ...).
local dispatcher = CreateFrame("Frame")
local handlers = {}

dispatcher:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	for i = 1, #list do
		list[i](event, ...)
	end
end)

function ns:RegisterEvent(event, func)
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
	modules = {bags = true, mover = true, errors = true, disenchant = true},
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
	gold = {
		show = true,
		days = {}, -- "Name-Realm" -> {day = "YYYY-MM-DD", gained, spent}
	},
	tooltip = {ids = false, unitPrice = true, targetOfTarget = true, disenchant = true, disenchantModifier = "NONE"},
	chat = {copyButton = true, urls = true},
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
			func()
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
