--[[
	Options: one page per context, listed under ForeverHub in the game's Options >
	AddOns. The first page sums up the replaced addons and the shortcuts.

	Each page is built the first time it is shown. Options that only take effect after
	/reload show a bar with the Reload button at the bottom of every page once one of
	them changes. A sub-option is greyed out while the option it depends on is off.
--]]

local _, ns = ...
local L, W = ns.L, ns.Widgets

local Options = ns:NewModule("Options")

local LEFT, COLUMN, INDENT = 16, 300, 28
local ROW, BAR_HEIGHT = 28, 34

local category
local pages = {} -- key -> {category = ..., frame = ...}
local reloadBars = {}
local reloadNeeded = false

local function NeedReload()
	reloadNeeded = true
	for _, bar in ipairs(reloadBars) do
		bar:Show()
	end
end

local function OpenPage(key)
	local page = key and pages[key]
	local target = page and page.category or category
	if target and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(target:GetID())
	end
end


--[[ Dependencies: a sub-option follows the option above it ]]--

local function SetActive(widget, active)
	if widget.Slider then -- slider holder
		widget.Slider:EnableMouse(active)
		widget.Slider:EnableMouseWheel(active)
		widget:SetAlpha(active and 1 or 0.45)
	elseif widget:IsObjectType("CheckButton") then
		widget:SetEnabled(active)
		if widget.Label then
			widget.Label:SetFontObject(active and GameFontHighlight or GameFontDisable)
		end
	elseif widget:IsObjectType("EditBox") then
		widget:EnableMouse(active)
		widget:SetAlpha(active and 1 or 0.45)
		if not active then widget:ClearFocus() end
	elseif widget.SetEnabled then
		widget:SetEnabled(active)
	end
end

-- Children are active only while the parent is checked and itself active.
local function UpdateChildren(parent)
	if not parent.children then return end
	local active = parent:GetChecked() and parent:IsEnabled()
	for _, child in ipairs(parent.children) do
		SetActive(child, active and true or false)
		if child.children then UpdateChildren(child) end
	end
end


--[[ Page builder ]]--

local Page = {}
Page.__index = Page

function Page:Space(height)
	self.y = self.y - (height or 8)
end

function Page:Header(text)
	self:Space(10)
	local title = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LEFT, self.y)
	title:SetText(text)
	local line = self.content:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", LEFT, self.y - 22)
	line:SetPoint("RIGHT", -LEFT, 0)
	self.y = self.y - 32
end

function Page:Note(text, indent)
	local x = LEFT + (indent and INDENT + 4 or 0)
	local note = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", x, self.y)
	note:SetWidth(560 - x)
	note:SetJustifyH("LEFT")
	note:SetTextColor(0.75, 0.75, 0.75)
	note:SetText(text)
	self.y = self.y - math.ceil(note:GetStringHeight()) - 8
	return note
end

local function Tooltip(opts)
	local tip = opts.tip
	if opts.reload then
		local line = "|cffff9a1f" .. L.RELOAD_TIP .. "|r"
		tip = tip and (tip .. "|n" .. line) or line
	end
	return tip
end

local function Depend(widget, parent)
	if not parent then return end
	parent.children = parent.children or {}
	table.insert(parent.children, widget)
end

-- opts: tip, reload, after (function), parent (the option it depends on), column (2)
function Page:Check(label, get, set, opts)
	opts = opts or {}
	local check
	check = W.CreateCheck(self.content, label, get, function(value)
		set(value)
		if opts.reload then NeedReload() end
		if opts.after then opts.after(value) end
		UpdateChildren(check)
	end, Tooltip(opts))
	local x = opts.column == 2 and COLUMN or LEFT + (opts.parent and INDENT or 0)
	check:SetPoint("TOPLEFT", x, self.y)
	if opts.column ~= 1 then -- the first of two columns keeps the row
		self.y = self.y - ROW
	end
	Depend(check, opts.parent)
	self.checks[#self.checks + 1] = check
	return check
end

-- Short checks two per row: entries are {label, key, opts}; table is the saved table.
function Page:Grid(entries, table, after, parent)
	for i, entry in ipairs(entries) do
		local opts = entry[3] or {}
		opts.after = opts.after or after
		opts.parent = parent
		opts.column = i % 2 == 1 and (i < #entries and 1 or nil) or 2
		local key = entry[2]
		self:Check(entry[1], function() return table[key] end, function(value) table[key] = value end, opts)
	end
end

-- A check on a key of a saved table.
function Page:Option(label, table, key, opts)
	return self:Check(label, function() return table[key] end, function(value) table[key] = value end, opts)
end

function Page:Slider(label, min, max, step, get, set, format, opts)
	opts = opts or {}
	local slider = W.CreateSlider(self.content, label, min, max, step, get, set, format)
	local x = opts.column == 2 and COLUMN + 4 or LEFT + 4 + (opts.parent and INDENT or 0)
	slider:SetPoint("TOPLEFT", x, self.y - 2)
	if opts.tip then W.AttachTooltip(slider.Slider, opts.tip, label) end
	if opts.column ~= 1 then
		self.y = self.y - 48
	end
	Depend(slider, opts.parent)
	return slider
end

function Page:Cycle(label, choices, get, set, opts)
	opts = opts or {}
	local cycle = W.CreateCycle(self.content, label, choices, get, set, opts.width or 260)
	local x = opts.column == 2 and COLUMN or LEFT + 4 + (opts.parent and INDENT or 0)
	cycle:SetPoint("TOPLEFT", x, self.y - 2)
	if opts.column ~= 1 then
		self.y = self.y - 32
	end
	Depend(cycle, opts.parent)
	return cycle
end

function Page:Button(label, width, onClick, opts)
	opts = opts or {}
	local button = W.CreateButton(self.content, label, width, onClick)
	local x = opts.column == 2 and COLUMN or LEFT + 4 + (opts.parent and INDENT or 0)
	button:SetPoint("TOPLEFT", x, self.y - 2)
	if opts.tip then W.AttachTooltip(button, opts.tip) end
	if opts.column ~= 1 then
		self.y = self.y - 32
	end
	Depend(button, opts.parent)
	return button
end

-- The module's own switch at the top of its page, with the conflicting addon if any.
function Page:Module(key, label, desc, opts)
	opts = opts or {}
	opts.tip = desc
	if opts.reload == nil then opts.reload = true end
	local check = self:Option(label, ns.db.modules, key, opts)
	local conflict = ns:GetConflict(key)
	if conflict then
		self:Note(L.CONFLICT_ACTIVE:format(conflict), true)
	end
	return check
end

function Page:Finish()
	self.content:SetHeight(-self.y + 20)
	local function Refresh()
		for _, check in ipairs(self.checks) do
			if check.children then UpdateChildren(check) end
		end
	end
	self.frame:HookScript("OnShow", function() C_Timer.After(0, Refresh) end)
	Refresh()
end

local function NewPage(frame, title)
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("BOTTOMLEFT", 8, 4)
	bar:SetPoint("BOTTOMRIGHT", -8, 4)
	bar:SetHeight(BAR_HEIGHT - 6)
	local background = bar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 0.6, 0.1, 0.12)
	local text = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", 10, 0)
	text:SetText(L.RELOAD_NEEDED)
	local button = W.CreateButton(bar, L.RELOAD, 120, C_UI.Reload)
	button:SetPoint("RIGHT", -4, 0)
	bar:SetShown(reloadNeeded)
	reloadBars[#reloadBars + 1] = bar

	local scroll, content = W.CreateScrollFrame(frame)
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, BAR_HEIGHT)

	local page = setmetatable({frame = frame, content = content, y = -10, checks = {}}, Page)
	local heading = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	heading:SetPoint("TOPLEFT", LEFT, page.y)
	heading:SetText(title)
	page.y = page.y - 36
	return page
end


--[[ Pages ]]--

local function BuildGeneral(p)
	local db = ns.db
	p:Note(L.GEN_INTRO)

	p:Header(L.GEN_REPLACED)
	local modules = {
		{"bags", L.MODULE_BAGS, "bags"},
		{"mover", L.MODULE_MOVER, "windows"},
		{"errors", L.MODULE_ERRORS, "windows"},
		{"disenchant", L.SEC_DISENCHANT, "bags"},
		{"sparkles", L.SECTION_SPARKLES, "interface"},
	}
	local lines = {}
	for _, info in ipairs(modules) do
		local key = info[1]
		-- name and state on one line, the replaced addons below in grey
		local name = p.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		name:SetPoint("TOPLEFT", LEFT + 4, p.y - 2)
		name:SetText(info[2])
		local replaced = p.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		replaced:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
		replaced:SetText(L.GEN_LINE:format(table.concat(ns.replaces[key] or {}, ", ")))
		local status = p.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		status:SetPoint("TOPLEFT", 230, p.y - 2)
		local open = W.CreateButton(p.content, L.GEN_OPEN, 70, function() OpenPage(info[3]) end)
		open:SetPoint("TOPLEFT", 500, p.y + 2)
		lines[#lines + 1] = function()
			local conflict = ns:GetConflict(key)
			if conflict then
				status:SetText(L.GEN_CONFLICT:format(conflict))
			elseif db.modules[key] == false then
				status:SetText(L.GEN_OFF)
			else
				status:SetText(L.GEN_ON)
			end
		end
		p:Space(36)
	end
	local function Refresh()
		for _, line in ipairs(lines) do line() end
	end
	p.frame:HookScript("OnShow", Refresh)
	Refresh()
	p:Space(4)
	p:Button(L.DISABLE_OLD, 220, function() ns:DisableReplacedAddons() end)

	p:Header(L.GEN_SHORTCUTS)
	p:Check(L.OPT_MINIMAP, function() return not db.minimap.hide end,
		function(value) ns.MinimapButton:SetShown(value) end)
	p:Note(L.GEN_COMMANDS)
end

local function BuildBags(p)
	local bags = ns.db.bags
	local function Apply()
		if ns.Bags.active then ns.Bags:ApplySettings() end
	end
	local function ApplyUpgrade()
		ns.Upgrade:Reset(true)
		Apply()
	end
	local module = p:Module("bags", L.ENABLE_BAGS, L.MODULE_BAGS_DESC)

	p:Header(L.SEC_LOOK)
	local function BagSlider(label, min, max, step, key, format, column)
		p:Slider(label, min, max, step, function() return bags[key] end,
			function(value) bags[key] = value; Apply() end, format, {column = column, parent = module})
	end
	BagSlider(L.OPT_BAG_COLUMNS, 6, 24, 1, "columns", "%d", 1)
	BagSlider(L.OPT_BANK_COLUMNS, 6, 30, 1, "bankColumns", "%d", 2)
	BagSlider(L.OPT_ITEM_SCALE, 0.5, 1.5, 0.05, "itemScale", "%.2f", 1)
	BagSlider(L.OPT_SPACING, 0, 8, 1, "spacing", "%d", 2)
	BagSlider(L.OPT_LOW_SPACE, 0, 10, 1, "lowSpace", "%d")
	p:Grid({
		{L.OPT_REVERSE, "reverseBags"},
		{L.OPT_SPLIT_BAGS, "splitBags"},
		{L.OPT_COLOR_BAGS, "colorBags"},
	}, bags, Apply, module)

	p:Header(L.SEC_MARKS)
	p:Grid({
		{L.OPT_QUALITY, "qualityBorder"},
		{L.OPT_ITEM_LEVEL, "itemLevel"},
		{L.OPT_JUNK, "junkIcon"},
		{L.OPT_QUEST, "questIcon"},
		{L.OPT_UNUSABLE, "unusable"},
		{L.OPT_NEW_GLOW, "newGlow"},
		{L.OPT_BOE, "boe"},
	}, bags, Apply, module)
	p:Note(L.JUNK_HINT, true)

	p:Header(L.SEC_COMPARE)
	local upgrade = p:Option(L.OPT_UPGRADE, bags, "upgrade",
		{tip = L.OPT_UPGRADE_DESC, after = ApplyUpgrade, parent = module})
	p:Option(L.OPT_UPGRADE_ONLY, bags, "upgradeOnly", {after = ApplyUpgrade, parent = upgrade})
	p:Cycle(L.OPT_UPGRADE_MODE, {
		{"stats", L.OPT_UPGRADE_STATS},
		{"level", L.OPT_UPGRADE_LEVEL},
	}, function() return bags.upgradeMode end, function(value) bags.upgradeMode = value; ApplyUpgrade() end,
		{width = 300, parent = upgrade})

	-- everything about disenchanting together: the bag icon and the tooltip lines
	p:Header(L.SEC_DISENCHANT)
	local deConflict = ns:GetConflict("disenchant")
	if deConflict then p:Note(L.CONFLICT_ACTIVE:format(deConflict)) end
	local mark = p:Option(L.OPT_DE_MARK, bags, "disenchantMark", {tip = L.OPT_DE_MARK_TIP, after = Apply, parent = module})
	p:Option(L.OPT_DE_MARK_ALWAYS, bags, "disenchantMarkAlways", {after = Apply, parent = mark})
	local deTip = p:Option(L.OPT_TIP_DISENCHANT, ns.db.tooltip, "disenchant")
	p:Cycle(L.OPT_TIP_DISENCHANT_MOD, {
		{"NONE", L.MOD_ALWAYS},
		{"SHIFT", SHIFT_KEY_TEXT or "Shift"},
		{"CTRL", CTRL_KEY_TEXT or "Ctrl"},
		{"ALT", ALT_KEY_TEXT or "Alt"},
	}, function() return ns.db.tooltip.disenchantModifier end,
		function(value) ns.db.tooltip.disenchantModifier = value end, {parent = deTip})

	p:Header(L.SEC_EXTRAS)
	local qol = ns.db.qol
	local function Extras() ns.BagExtras:Refresh() end
	p:Option(L.OPT_TIPCOUNTS, bags, "tooltipCounts", {after = Apply, parent = module})
	p:Option(L.OPT_OPEN_BOXES, qol, "openBoxes", {tip = L.OPT_OPEN_BOXES_TIP, after = Extras, parent = module})
	p:Option(L.OPT_AMMO, qol, "ammo", {tip = L.OPT_AMMO_TIP, after = Extras})
	p:Option(L.OPT_AMMO_WARN, qol, "ammoWarn", {after = Extras})
end

local function BuildMerchant(p)
	local merchant, qol = ns.db.merchant, ns.db.qol
	p:Header(L.SECTION_MERCHANT)
	p:Option(L.OPT_SELL_JUNK, ns.db.bags, "sellJunkButton", {tip = L.JUNK_HINT,
		after = function() if ns.Bags.active then ns.Bags:ApplySettings() end end})
	p:Option(L.OPT_AUTO_SELL, merchant, "autoSell")
	local repair = p:Option(L.OPT_AUTO_REPAIR, merchant, "autoRepair")
	p:Option(L.OPT_GUILD_REPAIR, merchant, "guildRepair", {parent = repair})
	p:Option(L.OPT_RESTOCK, merchant, "restockEnabled")
	p:Note(L.RESTOCK_HELP, true)
	p:Note(L.MERCHANT_SHIFT_HINT)

	p:Header(L.SEC_LOOT)
	p:Note(L.AUTOMATION_HINT)
	local automation = ns.db.automation
	local function Errors() ns.Automation:RefreshErrors() end
	p:Option(L.OPT_FASTER_LOOT, automation, "fasterLoot")
	p:Option(L.OPT_LOOT_LIMIT, automation, "lootLimit")
	p:Option(L.OPT_AUTO_RES, automation, "autoRes")
	p:Option(L.OPT_HIDE_ERRORS, automation, "hideErrors", {tip = L.OPT_HIDE_ERRORS_TIP, after = Errors})

	p:Header(L.SEC_MAIL)
	local function Mail() ns.Mail:Refresh() end
	p:Option(L.OPT_MAIL_TAKE_ALL, qol, "mailTakeAll", {tip = L.OPT_MAIL_TAKE_ALL_TIP, after = Mail})
	p:Option(L.OPT_MAIL_RECIPIENTS, qol, "mailRecipients", {tip = L.OPT_MAIL_RECIPIENTS_TIP, after = Mail})
end

local function BuildCharacter(p)
	local qol, durability = ns.db.qol, ns.db.durability
	p:Header(L.SECTION_EQUIPMENT)
	p:Option(L.OPT_SLOT_LEVELS, qol, "slotLevels", {after = function() ns.ItemSlots:Refresh() end})
	local function Durability() ns.Durability:Refresh() end
	p:Option(L.OPT_DURABILITY_SHOW, durability, "show", {after = Durability})
	local warn = p:Option(L.OPT_DURABILITY_WARN, durability, "warn", {after = Durability})
	p:Slider(L.OPT_DURABILITY_THRESHOLD, 5, 50, 5, function() return durability.threshold end,
		function(value) durability.threshold = value end, "%d%%", {parent = warn})

	p:Header(L.SEC_XP)
	local xp = p:Option(L.OPT_XP_SHOW, ns.db.xp, "show", {tip = L.XP_HINT, after = function() ns.Experience:Refresh() end})
	p:Option(L.OPT_READY_XP, qol, "readyXP", {tip = L.OPT_READY_XP_TIP, parent = xp,
		after = function() ns.Experience:UpdateText() end})
	p:Button(L.OPT_XP_RESET_POSITION, 240, function() ns.Experience:ResetPosition() end, {parent = xp})

	p:Header(L.SEC_QUESTS)
	p:Option(L.OPT_QUEST_LEVELS, qol, "questLevels", {after = function() ns.Quests:Refresh() end})
	p:Option(L.OPT_BEST_REWARD, qol, "bestReward", {tip = L.OPT_BEST_REWARD_TIP})

	p:Header(L.SEC_REMINDERS)
	p:Note(L.REMINDERS_HINT)
	local function Reminders() ns.Reminders:Refresh() end
	p:Option(L.OPT_BUFF_REMINDERS, qol, "buffReminders", {after = Reminders})
	p:Option(L.OPT_PET_REMINDERS, qol, "petReminders", {after = Reminders})
end

local function BuildChat(p)
	local chat = ns.db.chat
	p:Header(L.SEC_CHAT_READ)
	p:Option(L.OPT_CHAT_COPY, chat, "copyButton", {after = function() ns.Chat:Refresh() end})
	p:Option(L.OPT_CHAT_URLS, chat, "urls")
	p:Option(L.OPT_CHAT_TOOLTIPS, chat, "tooltips")
	p:Option(L.OPT_CHAT_ITEMINFO, chat, "itemInfo")
	p:Option(L.OPT_CHAT_TERMS, chat, "terms", {tip = L.OPT_CHAT_TERMS_TIP})
	p:Option(L.OPT_CHAT_FILTER, chat, "filterButton", {tip = L.OPT_CHAT_BAR_TIP, after = function() ns.ChatTabs:Refresh() end})
	p:Option(L.OPT_CHAT_SHORT, chat, "shortChannels")
	p:Option(L.OPT_CHAT_PLAYERINFO, chat, "playerInfo")

	p:Header(L.SEC_CHAT_HIGHLIGHT)
	local highlight = p:Option(L.OPT_CHAT_HIGHLIGHT, chat, "highlight")
	-- words to highlight, besides the character's name
	local label = p.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", LEFT + INDENT + 4, p.y - 6)
	label:SetText(L.OPT_CHAT_KEYWORDS)
	local keywords = CreateFrame("EditBox", nil, p.content, "InputBoxTemplate")
	keywords:SetSize(250, 22)
	keywords:SetPoint("LEFT", label, "RIGHT", 12, 0)
	keywords:SetAutoFocus(false)
	keywords:SetMaxLetters(200)
	local function Save(self)
		chat.keywords = self:GetText()
		ns.Chat:UpdateKeywords()
	end
	keywords:SetScript("OnShow", function(self) self:SetText(chat.keywords or "") end)
	keywords:SetScript("OnEnterPressed", function(self)
		Save(self)
		self:ClearFocus()
	end)
	keywords:SetScript("OnEditFocusLost", Save)
	keywords:SetScript("OnEscapePressed", function(self)
		self:SetText(chat.keywords or "")
		self:ClearFocus()
	end)
	keywords:SetText(chat.keywords or "")
	Depend(keywords, highlight)
	p:Space(30)
	p:Option(L.OPT_CHAT_SOUND, chat, "highlightSound", {parent = highlight})

	p:Header(L.SEC_CHAT_COMFORT)
	p:Option(L.OPT_CHAT_HISTORY, chat, "history")
	p:Option(L.OPT_CHAT_ARROWS, chat, "arrows", {after = function() ns.ChatFrames:Refresh() end})
	p:Option(L.OPT_CHAT_INVITE, chat, "altInvite")
	p:Option(L.OPT_CHAT_BAR, chat, "channelBar", {tip = L.OPT_CHAT_BAR_TIP, after = function() ns.ChatBar:Refresh() end})

	p:Header(L.SEC_CHAT_LOOK)
	p:Option(L.OPT_CHAT_BUTTONS, chat, "hideButtons", {reload = true})
	p:Option(L.OPT_CHAT_FADETABS, chat, "fadeTabs", {reload = true})
	p:Option(L.OPT_CHAT_SKIN, chat, "skin", {tip = L.OPT_CHAT_SKIN_TIP, reload = true})
end

local function BuildTooltips(p)
	local tooltip = ns.db.tooltip
	p:Header(L.SECTION_TOOLTIPS)
	p:Option(L.OPT_TIP_IDS, tooltip, "ids")
	p:Option(L.OPT_TIP_UNIT_PRICE, tooltip, "unitPrice")
	p:Option(L.OPT_TIP_TARGET, tooltip, "targetOfTarget")
	p:Option(L.OPT_GOLD_SHOW, ns.db.gold, "show", {tip = L.GOLD_HINT})
	p:Space(4)
	p:Note(L.TIP_ELSEWHERE)
end

local function BuildInterface(p)
	local perf, sparkles = ns.db.performance, ns.db.sparkles
	p:Header(L.SECTION_PERFORMANCE)
	local function Perf() ns.Performance:Refresh() end
	local show = p:Option(L.OPT_PERF_SHOW, perf, "show", {tip = L.PERF_HINT, after = Perf})
	p:Grid({
		{L.OPT_PERF_FPS, "fps"},
		{L.OPT_PERF_LATENCY, "latency"},
		{L.OPT_PERF_MEMORY, "memory"},
		{L.OPT_PERF_CLOCK, "clock"},
	}, perf, Perf, show)
	p:Button(L.OPT_PERF_RESET_POSITION, 280, function() ns.Performance:ResetPosition() end, {parent = show})

	p:Header(L.SECTION_ACTIONBARS)
	p:Option(L.OPT_MANA_COST, ns.db.actionbars, "manaCost", {tip = L.OPT_MANA_COST_DESC,
		after = function() ns.ActionBars:Refresh() end})

	p:Header(L.SECTION_SPARKLES)
	local function Beacon() ns.QuestGlow:Refresh() end
	local function Refresh() ns.Sparkles:Refresh(); Beacon() end
	local module = p:Module("sparkles", L.ENABLE_SPARKLES, nil, {reload = false, after = Refresh})
	p:Note(L.GLOW_SECTION_HINT, true)
	p:Button(L.GLOW_OPEN, 300, function()
		-- the game's options window would cover it
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		ns.GlowWindow:Open()
	end, {parent = module, tip = L.GLOW_OPEN_TIP})
	p:Option(L.OPT_SPARKLE_QUEST, sparkles, "questLoot", {tip = L.OPT_SPARKLE_QUEST_TIP, parent = module,
		after = function(value) ns.Sparkles:SetQuestLoot(value) end})

	p:Header(L.SECTION_QUEST_GLOW)
	p:Option(L.OPT_QUEST_MOBS, sparkles, "questMobs", {tip = L.OPT_QUEST_MOBS_TIP, after = Beacon, parent = module})
	p:Option(L.OPT_QUEST_PROGRESS, sparkles, "questProgress", {after = Beacon, parent = module})
	p:Option(L.OPT_QUEST_BEAM, sparkles, "questBeam", {after = Beacon, parent = module})
	local colors = {}
	for _, color in ipairs(ns.QuestGlow.COLORS) do
		colors[#colors + 1] = {color[1], L["GLOW_COLOR_" .. color[1]:upper()]}
	end
	p:Cycle(L.OPT_QUEST_COLOR, colors, function() return sparkles.questColor end,
		function(value) sparkles.questColor = value; Beacon() end, {parent = module})
	p:Slider(L.OPT_QUEST_SCALE, 60, 160, 10, function() return sparkles.questScale end,
		function(value) sparkles.questScale = value; Beacon() end, "%d%%", {parent = module, column = 1})
	p:Slider(L.OPT_QUEST_INTENSITY, 10, 100, 10, function() return sparkles.questIntensity end,
		function(value) sparkles.questIntensity = value; Beacon() end, "%d%%", {column = 2, parent = module})
	p:Note(L.QUEST_GLOW_HINT, true)
end

local function BuildWindows(p)
	local mover, errors = ns.db.mover, ns.db.errors
	p:Header(L.MODULE_MOVER)
	local moverModule = p:Module("mover", L.ENABLE_MOVER, L.MODULE_MOVER_DESC)
	p:Note(L.MOVER_HINT, true)
	p:Cycle(L.OPT_MOVER_SAVE, {
		{"off", L.OPT_MOVER_SAVE_OFF},
		{"session", L.OPT_MOVER_SAVE_SESSION},
		{"always", L.OPT_MOVER_SAVE_ALWAYS},
	}, function() return mover.save end, function(value) ns.Mover:SetSaveMode(value) end,
		{column = 1, parent = moverModule, width = 240})
	p:Cycle(L.OPT_MOVER_MODIFIER, {
		{"NONE", L.MOD_NONE},
		{"SHIFT", SHIFT_KEY_TEXT or "Shift"},
		{"CTRL", CTRL_KEY_TEXT or "Ctrl"},
		{"ALT", ALT_KEY_TEXT or "Alt"},
	}, function() return mover.modifier end, function(value) mover.modifier = value end,
		{column = 2, parent = moverModule, width = 250})
	p:Option(L.OPT_MOVER_SCALING, mover, "scaling", {reload = true, parent = moverModule})
	p:Button(L.OPT_MOVER_RESET, 220, function()
		if ns.Mover.active then ns.Mover:ResetAll() end
	end, {parent = moverModule})

	p:Header(L.MODULE_ERRORS)
	local errorsModule = p:Module("errors", L.ENABLE_ERRORS, L.MODULE_ERRORS_DESC)
	p:Option(L.OPT_ERR_CHAT, errors, "chat", {parent = errorsModule})
	p:Option(L.OPT_ERR_SOUND, errors, "sound", {parent = errorsModule})
	p:Option(L.OPT_ERR_POPUP, errors, "popup", {parent = errorsModule})
	p:Option(L.OPT_ERR_SUPPRESS, errors, "suppressBlizzard", {reload = true, parent = errorsModule})
	p:Button(L.OPT_ERR_OPEN, 220, function()
		if ns.Errors:IsActive() and ns.db.modules.errors then ns.ErrorWindow:Open() end
	end, {parent = errorsModule})
end

local function BuildProfessions(p)
	local prof = ns.db.professions
	p:Note(L.PROF_NOTE)
	local shopping = p:Option(L.OPT_PROF_SHOPPING, prof, "shopping", {tip = L.OPT_PROF_SHOPPING_TIP,
		after = function() ns.Shopping:Refresh() end})
	p:Button(L.OPT_PROF_RESET_POSITION, 280, function() ns.Shopping:ResetPosition() end, {parent = shopping})
	p:Option(L.OPT_PROF_GUIDE, prof, "guide", {tip = L.OPT_PROF_GUIDE_TIP,
		after = function() ns.ProfessionGuide:Refresh() end})
	p:Option(L.OPT_PROF_TOOLTIP, prof, "tooltip")
	p:Option(L.OPT_PROF_SKINNING, prof, "skinning")
end

local function BuildGraphics(p)
	local CVars = ns.CVars
	p:Note(L.GRAPHICS_DESC)
	for _, info in ipairs(CVars.list) do
		local name = info.name
		local tip = L[info.desc] .. "|n|cff888888/console " .. name .. "|r"
		if info.bool then
			local check = p:Check(L[info.label], function() return CVars:Get(name) == 1 end,
				function(value) CVars:Set(name, value and 1 or 0) end, {tip = tip, column = 1})
			if not CVars:Exists(name) then
				check:Disable()
				check:SetAlpha(0.4)
			end
			local default = W.CreateButton(p.content, L.CV_DEFAULT, 70, function()
				CVars:Reset(name)
				check:SetChecked(CVars:Get(name) == 1)
			end)
			default:SetPoint("TOPLEFT", 400, p.y - 2)
			W.AttachTooltip(default, L.CV_DEFAULT_TIP)
			p:Space(ROW)
		else
			local status = p.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			status:SetPoint("TOPLEFT", 340, p.y - 20)
			status:SetTextColor(0.75, 0.75, 0.75)

			-- requested: the value just written, to tell when the game clamped it
			local function Status(requested)
				if not CVars:Exists(name) then
					return status:SetText(L.CV_MISSING)
				end
				local current = CVars:Get(name)
				if requested and InCombatLockdown() then
					status:SetText(L.CV_COMBAT)
				elseif requested and math.abs(current - requested) > info.step / 2 then
					status:SetText(L.CV_CLAMPED:format(info.format:format(current)))
				else
					local default = CVars:GetDefault(name)
					local text = default and (L.CV_DEFAULT .. ": " .. info.format:format(default)) or ""
					if CVars:IsManaged(name) then
						text = text .. "  |cff4fc3f7" .. L.CV_MANAGED .. "|r"
					end
					status:SetText(text)
				end
			end

			local y = p.y
			local slider = p:Slider(L[info.label], info.min, info.max, info.step,
				function()
					Status()
					return CVars:Get(name) or info.min
				end,
				function(value)
					CVars:Set(name, value)
					Status(value)
				end,
				info.format, {tip = tip})
			local default = W.CreateButton(p.content, L.CV_DEFAULT, 70, function()
				CVars:Reset(name)
				slider.Slider:SetValue(CVars:Get(name) or info.min)
				Status()
			end)
			default:SetPoint("TOPLEFT", 252, y - 16)
			W.AttachTooltip(default, L.CV_DEFAULT_TIP)

			if not CVars:Exists(name) then
				slider.Slider:EnableMouse(false)
				slider.Slider:EnableMouseWheel(false)
				slider:SetAlpha(0.4)
				default:Disable()
			end
			p:Space(6)
		end
	end
end


--[[ Registration ]]--

local PAGES = {
	{"bags", "PAGE_BAGS", BuildBags},
	{"merchant", "PAGE_MERCHANT", BuildMerchant},
	{"character", "PAGE_CHARACTER", BuildCharacter},
	{"chat", "PAGE_CHAT", BuildChat},
	{"tooltips", "PAGE_TOOLTIPS", BuildTooltips},
	{"interface", "PAGE_INTERFACE", BuildInterface},
	{"windows", "PAGE_WINDOWS", BuildWindows},
	{"professions", "PAGE_PROFESSIONS", BuildProfessions},
	{"graphics", "PAGE_GRAPHICS", BuildGraphics},
}

-- A frame that builds its page the first time it is shown.
local function LazyFrame(title, build)
	local frame = CreateFrame("Frame")
	frame:Hide()
	frame:SetScript("OnShow", function(self)
		self:SetScript("OnShow", nil)
		local page = NewPage(self, title)
		build(page)
		page:Finish()
	end)
	return frame
end

function Options:OnLogin()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local title = ns.color .. "Forever|rHub  |cff888888" .. ns.version .. "|r"
	category = Settings.RegisterCanvasLayoutCategory(LazyFrame(title, BuildGeneral), ns.name)
	for _, info in ipairs(PAGES) do
		local name = L[info[2]]
		local frame = LazyFrame(name, info[3])
		local sub = Settings.RegisterCanvasLayoutSubcategory
			and Settings.RegisterCanvasLayoutSubcategory(category, frame, name)
		pages[info[1]] = {category = sub, frame = frame}
	end
	Settings.RegisterAddOnCategory(category)
end

-- Opens the options, on a page when given ("bags", "chat"...).
function ns:OpenOptions(page)
	OpenPage(page)
end
