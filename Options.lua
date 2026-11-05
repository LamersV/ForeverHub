--[[
	Options panel, registered in the game's Settings window.
	Controls are built the first time the panel is shown.
--]]

local _, ns = ...
local L, W = ns.L, ns.Widgets

local Options = ns:NewModule("Options")
local category

local function Header(parent, text, y)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, y)
	title:SetText(text)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 16, y - 22)
	line:SetPoint("RIGHT", -16, 0)
	return y - 32
end

local function Note(parent, text, y, x)
	local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", x or 16, y)
	note:SetPoint("RIGHT", -16, 0)
	note:SetJustifyH("LEFT")
	note:SetText(text)
	note:SetTextColor(0.75, 0.75, 0.75)
	return note
end

local function Build(panel)
	local scroll, content = W.CreateScrollFrame(panel)
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)
	content:SetHeight(1000)

	local db = ns.db
	local y = -10

	local title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, y)
	title:SetText(ns.color .. "Forever|rHub  |cff888888" .. ns.version .. "|r")
	y = y - 40

	-- modules
	y = Header(content, L.OPTIONS_MODULES, y)
	Note(content, L.OPTIONS_MODULES_DESC, y)
	y = y - 22

	local reload = W.CreateButton(content, L.RELOAD, 120, C_UI.Reload)
	reload:SetPoint("TOPRIGHT", -16, y + 52)
	reload:Hide()

	local modules = {
		{"bags", L.MODULE_BAGS, L.MODULE_BAGS_DESC},
		{"mover", L.MODULE_MOVER, L.MODULE_MOVER_DESC},
		{"errors", L.MODULE_ERRORS, L.MODULE_ERRORS_DESC},
	}
	for _, info in ipairs(modules) do
		local key = info[1]
		local check = W.CreateCheck(content, info[2],
			function() return db.modules[key] end,
			function(value)
				db.modules[key] = value
				reload:Show()
			end)
		check:SetPoint("TOPLEFT", 16, y)

		local conflict = ns:GetConflict(key)
		Note(content, conflict and L.CONFLICT_ACTIVE:format(conflict) or info[3], y - 26, 46)
		y = y - 50
	end

	local disable = W.CreateButton(content, L.DISABLE_OLD, 200, function() ns:DisableReplacedAddons() end)
	disable:SetPoint("TOPLEFT", 16, y)
	y = y - 34

	local minimap = W.CreateCheck(content, L.OPT_MINIMAP,
		function() return not db.minimap.hide end,
		function(value) ns.MinimapButton:SetShown(value) end)
	minimap:SetPoint("TOPLEFT", 16, y)
	y = y - 40

	-- bags
	local bags = db.bags
	local function Apply()
		if ns.Bags.active then
			ns.Bags:ApplySettings()
		end
	end
	y = Header(content, L.MODULE_BAGS, y)

	local sliders = {
		{L.OPT_BAG_COLUMNS, 6, 24, 1, "columns", "%d"},
		{L.OPT_BANK_COLUMNS, 6, 30, 1, "bankColumns", "%d"},
		{L.OPT_ITEM_SCALE, 0.5, 1.5, 0.05, "itemScale", "%.2f"},
		{L.OPT_SPACING, 0, 8, 1, "spacing", "%d"},
		{L.OPT_LOW_SPACE, 0, 10, 1, "lowSpace", "%d"},
	}
	for i, info in ipairs(sliders) do
		local key = info[5]
		local slider = W.CreateSlider(content, info[1], info[2], info[3], info[4],
			function() return bags[key] end,
			function(value) bags[key] = value; Apply() end,
			info[6])
		slider:SetPoint("TOPLEFT", i % 2 == 1 and 20 or 290, y)
		if i % 2 == 0 or i == #sliders then
			y = y - 48
		end
	end

	local checks = {
		{L.OPT_REVERSE, "reverseBags"},
		{L.OPT_QUALITY, "qualityBorder"},
		{L.OPT_JUNK, "junkIcon"},
		{L.OPT_QUEST, "questIcon"},
		{L.OPT_UNUSABLE, "unusable"},
		{L.OPT_NEW_GLOW, "newGlow"},
		{L.OPT_ITEM_LEVEL, "itemLevel"},
		{L.OPT_BOE, "boe"},
		{L.OPT_DE_MARK, "disenchantMark"},
		{L.OPT_DE_MARK_ALWAYS, "disenchantMarkAlways"},
		{L.OPT_SPLIT_BAGS, "splitBags"},
		{L.OPT_COLOR_BAGS, "colorBags"},
		{L.OPT_TIPCOUNTS, "tooltipCounts"}, -- long label: keep last, alone on its row
	}
	for i, info in ipairs(checks) do
		local key = info[2]
		local check = W.CreateCheck(content, info[1],
			function() return bags[key] end,
			function(value) bags[key] = value; Apply() end)
		check:SetPoint("TOPLEFT", i % 2 == 1 and 16 or 286, y)
		if i % 2 == 0 or i == #checks then
			y = y - 30
		end
	end

	-- upgrade over the equipped item
	local function ApplyUpgrade()
		ns.Upgrade:Reset(true)
		Apply()
	end
	local upgrade = W.CreateCheck(content, L.OPT_UPGRADE,
		function() return bags.upgrade end,
		function(value) bags.upgrade = value; ApplyUpgrade() end,
		L.OPT_UPGRADE_DESC)
	upgrade:SetPoint("TOPLEFT", 16, y)
	local upgradeOnly = W.CreateCheck(content, L.OPT_UPGRADE_ONLY,
		function() return bags.upgradeOnly end,
		function(value) bags.upgradeOnly = value; ApplyUpgrade() end)
	upgradeOnly:SetPoint("TOPLEFT", 286, y)
	y = y - 32
	local upgradeMode = W.CreateCycle(content, L.OPT_UPGRADE_MODE, {
		{"stats", L.OPT_UPGRADE_STATS},
		{"level", L.OPT_UPGRADE_LEVEL},
	}, function() return bags.upgradeMode end, function(value) bags.upgradeMode = value; ApplyUpgrade() end, 300)
	upgradeMode:SetPoint("TOPLEFT", 20, y)
	y = y - 46

	-- mover
	local mover = db.mover
	y = Header(content, L.MODULE_MOVER, y)
	Note(content, L.MOVER_HINT, y)
	y = y - 24

	local save = W.CreateCycle(content, L.OPT_MOVER_SAVE, {
		{"off", L.OPT_MOVER_SAVE_OFF},
		{"session", L.OPT_MOVER_SAVE_SESSION},
		{"always", L.OPT_MOVER_SAVE_ALWAYS},
	}, function() return mover.save end, function(value) ns.Mover:SetSaveMode(value) end, 250)
	save:SetPoint("TOPLEFT", 20, y)

	local modifier = W.CreateCycle(content, L.OPT_MOVER_MODIFIER, {
		{"NONE", L.MOD_NONE},
		{"SHIFT", SHIFT_KEY_TEXT or "Shift"},
		{"CTRL", CTRL_KEY_TEXT or "Ctrl"},
		{"ALT", ALT_KEY_TEXT or "Alt"},
	}, function() return mover.modifier end, function(value) mover.modifier = value end, 250)
	modifier:SetPoint("TOPLEFT", 290, y)
	y = y - 32

	local scaling = W.CreateCheck(content, L.OPT_MOVER_SCALING,
		function() return mover.scaling end,
		function(value) mover.scaling = value; reload:Show() end)
	scaling:SetPoint("TOPLEFT", 16, y)

	local reset = W.CreateButton(content, L.OPT_MOVER_RESET, 200, function()
		if ns.Mover.active then
			ns.Mover:ResetAll()
		end
	end)
	reset:SetPoint("TOPLEFT", 290, y)
	y = y - 46

	-- errors
	local errors = db.errors
	y = Header(content, L.MODULE_ERRORS, y)
	local errorChecks = {
		{L.OPT_ERR_CHAT, "chat"},
		{L.OPT_ERR_SOUND, "sound"},
		{L.OPT_ERR_POPUP, "popup"},
		{L.OPT_ERR_SUPPRESS, "suppressBlizzard", true},
	}
	for _, info in ipairs(errorChecks) do
		local key, needsReload = info[2], info[3]
		local check = W.CreateCheck(content, info[1],
			function() return errors[key] end,
			function(value)
				errors[key] = value
				if needsReload then reload:Show() end
			end)
		check:SetPoint("TOPLEFT", 16, y)
		y = y - 30
	end

	local open = W.CreateButton(content, L.OPT_ERR_OPEN, 200, function()
		if ns.Errors:IsActive() and db.modules.errors then
			ns.ErrorWindow:Open()
		end
	end)
	open:SetPoint("TOPLEFT", 20, y - 6)
	y = y - 50

	-- merchant
	y = Header(content, L.SECTION_MERCHANT, y)
	local sellJunk = W.CreateCheck(content, L.OPT_SELL_JUNK,
		function() return db.bags.sellJunkButton end,
		function(value) db.bags.sellJunkButton = value; Apply() end,
		L.JUNK_HINT)
	sellJunk:SetPoint("TOPLEFT", 16, y)
	y = y - 30
	local merchantChecks = {
		{L.OPT_AUTO_SELL, "autoSell"},
		{L.OPT_AUTO_REPAIR, "autoRepair"},
		{L.OPT_GUILD_REPAIR, "guildRepair", 30},
	}
	for _, info in ipairs(merchantChecks) do
		local key = info[2]
		local check = W.CreateCheck(content, info[1],
			function() return db.merchant[key] end,
			function(value) db.merchant[key] = value end)
		check:SetPoint("TOPLEFT", 16 + (info[3] or 0), y)
		y = y - 30
	end
	local restockCheck = W.CreateCheck(content, L.OPT_RESTOCK,
		function() return db.merchant.restockEnabled end,
		function(value) db.merchant.restockEnabled = value end)
	restockCheck:SetPoint("TOPLEFT", 16, y)
	Note(content, L.RESTOCK_HELP, y - 26, 46)
	y = y - 62
	Note(content, L.MERCHANT_SHIFT_HINT, y + 6)
	y = y - 26

	-- automation
	y = Header(content, L.SECTION_AUTOMATION, y)
	Note(content, L.AUTOMATION_HINT, y)
	y = y - 22
	local automationChecks = {
		{L.OPT_FASTER_LOOT, "fasterLoot"},
		{L.OPT_LOOT_LIMIT, "lootLimit"},
		{L.OPT_AUTO_RES, "autoRes"},
		{L.OPT_HIDE_ERRORS, "hideErrors"},
	}
	for _, info in ipairs(automationChecks) do
		local key = info[2]
		local check = W.CreateCheck(content, info[1],
			function() return db.automation[key] end,
			function(value)
				db.automation[key] = value
				ns.Automation:RefreshErrors()
			end)
		check:SetPoint("TOPLEFT", 16, y)
		y = y - 30
	end
	y = y - 16

	-- equipment
	y = Header(content, L.SECTION_EQUIPMENT, y)
	local durabilityChecks = {
		{L.OPT_DURABILITY_SHOW, "show"},
		{L.OPT_DURABILITY_WARN, "warn"},
	}
	for _, info in ipairs(durabilityChecks) do
		local key = info[2]
		local check = W.CreateCheck(content, info[1],
			function() return db.durability[key] end,
			function(value)
				db.durability[key] = value
				ns.Durability:Refresh()
			end)
		check:SetPoint("TOPLEFT", 16, y)
		y = y - 30
	end
	local threshold = W.CreateSlider(content, L.OPT_DURABILITY_THRESHOLD, 5, 50, 5,
		function() return db.durability.threshold end,
		function(value) db.durability.threshold = value end,
		"%d%%")
	threshold:SetPoint("TOPLEFT", 20, y - 4)
	y = y - 56

	-- progress
	y = Header(content, L.SECTION_PROGRESS, y)
	local xp = W.CreateCheck(content, L.OPT_XP_SHOW,
		function() return db.xp.show end,
		function(value)
			db.xp.show = value
			ns.Experience:Refresh()
		end,
		L.XP_HINT)
	xp:SetPoint("TOPLEFT", 16, y)
	y = y - 30
	local xpReset = W.CreateButton(content, L.OPT_XP_RESET_POSITION, 220, function() ns.Experience:ResetPosition() end)
	xpReset:SetPoint("TOPLEFT", 46, y)
	y = y - 30
	local gold = W.CreateCheck(content, L.OPT_GOLD_SHOW,
		function() return db.gold.show end,
		function(value) db.gold.show = value end,
		L.GOLD_HINT)
	gold:SetPoint("TOPLEFT", 16, y)
	y = y - 46

	-- tooltips
	y = Header(content, L.SECTION_TOOLTIPS, y)
	local tooltipChecks = {
		{L.OPT_TIP_IDS, "ids"},
		{L.OPT_TIP_UNIT_PRICE, "unitPrice"},
		{L.OPT_TIP_TARGET, "targetOfTarget"},
		{L.OPT_TIP_DISENCHANT, "disenchant"},
	}
	for _, info in ipairs(tooltipChecks) do
		local key = info[2]
		local check = W.CreateCheck(content, info[1],
			function() return db.tooltip[key] end,
			function(value) db.tooltip[key] = value end)
		check:SetPoint("TOPLEFT", 16, y)
		y = y - 30
	end
	local disenchantModifier = W.CreateCycle(content, L.OPT_TIP_DISENCHANT_MOD, {
		{"NONE", L.MOD_ALWAYS},
		{"SHIFT", SHIFT_KEY_TEXT or "Shift"},
		{"CTRL", CTRL_KEY_TEXT or "Ctrl"},
		{"ALT", ALT_KEY_TEXT or "Alt"},
	}, function() return db.tooltip.disenchantModifier end,
		function(value) db.tooltip.disenchantModifier = value end, 250)
	disenchantModifier:SetPoint("TOPLEFT", 50, y)
	y = y - 48

	-- chat
	y = Header(content, L.SECTION_CHAT, y)
	local copyButton = W.CreateCheck(content, L.OPT_CHAT_COPY,
		function() return db.chat.copyButton end,
		function(value)
			db.chat.copyButton = value
			ns.Chat:Refresh()
		end)
	copyButton:SetPoint("TOPLEFT", 16, y)
	y = y - 30
	local urls = W.CreateCheck(content, L.OPT_CHAT_URLS,
		function() return db.chat.urls end,
		function(value) db.chat.urls = value end)
	urls:SetPoint("TOPLEFT", 16, y)
	y = y - 46

	-- graphics and camera
	local CVars = ns.CVars
	y = Header(content, L.MODULE_GRAPHICS, y)
	Note(content, L.GRAPHICS_DESC, y)
	y = y - 34

	for _, info in ipairs(CVars.list) do
		local name = info.name
		if info.bool then
			local check = W.CreateCheck(content, L[info.label],
				function() return CVars:Get(name) == 1 end,
				function(value) CVars:Set(name, value and 1 or 0) end,
				L[info.desc] .. "|n|cff888888/console " .. name .. "|r")
			check:SetPoint("TOPLEFT", 16, y)
			if not CVars:Exists(name) then
				check:Disable()
				check:SetAlpha(0.4)
			end
			local default = W.CreateButton(content, L.CV_DEFAULT, 70, function()
				CVars:Reset(name)
				check:SetChecked(CVars:Get(name) == 1)
			end)
			default:SetPoint("TOPLEFT", 400, y - 2)
			W.AttachTooltip(default, L.CV_DEFAULT_TIP)
			y = y - 30
		else
			local status = Note(content, "", y - 20, 340)

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

			local slider = W.CreateSlider(content, L[info.label], info.min, info.max, info.step,
				function()
					Status()
					return CVars:Get(name) or info.min
				end,
				function(value)
					CVars:Set(name, value)
					Status(value)
				end,
				info.format)
			slider:SetPoint("TOPLEFT", 20, y)
			W.AttachTooltip(slider.Slider, L[info.desc] .. "|n|cff888888/console " .. name .. "|r", L[info.label])

			local default = W.CreateButton(content, L.CV_DEFAULT, 70, function()
				CVars:Reset(name)
				slider.Slider:SetValue(CVars:Get(name) or info.min)
				Status()
			end)
			default:SetPoint("TOPLEFT", 252, y - 14)
			W.AttachTooltip(default, L.CV_DEFAULT_TIP)

			if not CVars:Exists(name) then
				slider.Slider:EnableMouse(false)
				slider.Slider:EnableMouseWheel(false)
				slider:SetAlpha(0.4)
				default:Disable()
			end
			y = y - 54
		end
	end

	content:SetHeight(-y)
end

function Options:OnLogin()
	local panel = CreateFrame("Frame")
	panel:Hide()
	panel:SetScript("OnShow", function(self)
		self:SetScript("OnShow", nil)
		Build(self)
	end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, ns.name)
		Settings.RegisterAddOnCategory(category)
	end
end

function ns:OpenOptions()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	end
end
