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
	}
	for i, info in ipairs(sliders) do
		local key = info[5]
		local slider = W.CreateSlider(content, info[1], info[2], info[3], info[4],
			function() return bags[key] end,
			function(value) bags[key] = value; Apply() end,
			info[6])
		slider:SetPoint("TOPLEFT", i % 2 == 1 and 20 or 290, y)
		if i % 2 == 0 then
			y = y - 48
		end
	end

	local checks = {
		{L.OPT_REVERSE, "reverseBags"},
		{L.OPT_QUALITY, "qualityBorder"},
		{L.OPT_JUNK, "junkIcon"},
		{L.OPT_QUEST, "questIcon"},
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
	y = y - 16

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

	-- graphics and camera
	local CVars = ns.CVars
	y = Header(content, L.MODULE_GRAPHICS, y)
	Note(content, L.GRAPHICS_DESC, y)
	y = y - 34

	for _, info in ipairs(CVars.list) do
		local name = info.name
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
