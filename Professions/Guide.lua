--[[
	Professions - leveling guide and the profession window

	A panel beside the profession window suggests what to craft next to gain
	skill: known recipes that still give points (orange, yellow, green), the ones
	that can be made with what the character has first (bags + bank), then by
	cost per expected point. The cost is an estimate: what the materials cost at
	a vendor, or their sell price.

	Also adds an "add to shopping list" button next to the craft buttons.
	Only our own frames are created on Blizzard's window; nothing of it is replaced.
--]]

local _, ns = ...
local L = ns.L
local Prof = ns.Professions

local Guide = ns:NewModule("ProfessionGuide")

local ROWS, ROW_HEIGHT, WIDTH = 6, 34, 260
-- expected skill points of one craft, by difficulty
local CHANCE = {[Prof.ORANGE] = 1, [Prof.YELLOW] = 0.6, [Prof.GREEN] = 0.2}

local settings
local panel, addButton
local selectedRecipe
local candidates = {}


--[[ Suggestions ]]--

-- How many crafts the bags and bank allow, how many the bags alone, and the
-- first material missing.
local function Possible(recipe)
	local reagents = recipe.r
	local crafts, inBags, missing, missingCount = math.huge, math.huge, nil, 0
	for i = 1, #reagents, 2 do
		local have, bags = Prof:Count(reagents[i])
		local amount = reagents[i + 1]
		crafts = math.min(crafts, math.floor(have / amount))
		inBags = math.min(inBags, math.floor(bags / amount))
		if have < amount and not missing then
			missing, missingCount = reagents[i], amount - have
		end
	end
	if crafts == math.huge then crafts, inBags = 0, 0 end
	return crafts, inBags, missing, missingCount
end

local function Cost(recipe)
	local reagents, total = recipe.r, 0
	for i = 1, #reagents, 2 do
		total = total + Prof:GetValue(reagents[i]) * reagents[i + 1]
	end
	return total
end

local function Compare(a, b)
	if (a.crafts > 0) ~= (b.crafts > 0) then
		return a.crafts > 0
	end
	if a.perPoint ~= b.perPoint then
		return a.perPoint < b.perPoint
	end
	return a.name < b.name
end

local function Collect()
	wipe(candidates)
	for recipeID, info in pairs(Prof.live) do
		local chance = CHANCE[info.relativeDifficulty]
		local recipe = Prof:GetRecipe(recipeID)
		if chance and recipe and #recipe.r > 0 then
			if info.relativeDifficulty == Prof.ORANGE and (info.numSkillUps or 0) > 1 then
				chance = info.numSkillUps
			end
			local crafts, inBags, missing, missingCount = Possible(recipe)
			candidates[#candidates + 1] = {
				id = recipeID, name = info.name or recipe.n or "?", icon = info.icon or recipe.i,
				difficulty = info.relativeDifficulty, crafts = crafts, bags = inBags,
				missing = missing, missingCount = missingCount, perPoint = Cost(recipe) / chance,
			}
		end
	end
	table.sort(candidates, Compare)
end


--[[ Panel ]]--

local function SelectRecipe(recipeID)
	if C_TradeSkillUI.OpenRecipe and pcall(C_TradeSkillUI.OpenRecipe, recipeID) then return end
	local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
	local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
	if list and list.SelectRecipe and info then
		pcall(list.SelectRecipe, list, info, true)
	end
end

local function RowClick(row)
	local entry = row.entry
	if not entry then return end
	if IsShiftKeyDown() or IsControlKeyDown() then
		if ns.Shopping then
			ns.Shopping:Add(entry.id, IsControlKeyDown() and 5 or 1)
		end
	else
		SelectRecipe(entry.id)
	end
end

local function RowEnter(row)
	local entry = row.entry
	if not entry then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if C_TradeSkillUI.GetRecipeItemLink then
		local link = C_TradeSkillUI.GetRecipeItemLink(entry.id)
		if link then
			GameTooltip:SetHyperlink(link)
		end
	end
	if GameTooltip:NumLines() == 0 then
		GameTooltip:SetText(entry.name)
	end
	GameTooltip:AddLine(" ")
	if entry.perPoint > 0 then
		GameTooltip:AddDoubleLine(L.PROF_GUIDE_COST, GetMoneyString(math.ceil(entry.perPoint), true), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:AddLine(L.PROF_GUIDE_ROW_HINT, 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

local function CreateRow(i)
	local row = CreateFrame("Button", nil, panel)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 8, -46 - (i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", -8, 0)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
	row.Icon:SetPoint("LEFT")
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 6, -2)
	row.Name:SetPoint("RIGHT")
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Info:SetPoint("BOTTOMLEFT", row.Icon, "BOTTOMRIGHT", 6, 2)
	row.Info:SetPoint("RIGHT")
	row.Info:SetJustifyH("LEFT")
	row.Info:SetWordWrap(false)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:SetScript("OnClick", RowClick)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function CreatePanel()
	panel = CreateFrame("Frame", "ForeverHubProfessionGuide", ProfessionsFrame, "BackdropTemplate")
	panel:SetWidth(WIDTH)
	-- the anchor is set at each refresh (see PlacePanel)
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = {left = 3, right = 3, top = 3, bottom = 3},
	})
	panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
	panel:SetBackdropBorderColor(0.6, 0.6, 0.6)
	panel:EnableMouse(true)

	panel.Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.Title:SetPoint("TOPLEFT", 10, -10)
	panel.Title:SetPoint("RIGHT", -28, 0)
	panel.Title:SetJustifyH("LEFT")
	panel.Status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.Status:SetPoint("TOPLEFT", panel.Title, "BOTTOMLEFT", 0, -4)
	panel.Status:SetPoint("RIGHT", -10, 0)
	panel.Status:SetJustifyH("LEFT")

	local collapse = CreateFrame("Button", nil, panel)
	collapse:SetSize(18, 18)
	collapse:SetPoint("TOPRIGHT", -6, -6)
	collapse:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	collapse:SetScript("OnClick", function()
		settings.guideCollapsed = not settings.guideCollapsed
		Guide:Refresh()
	end)
	panel.Collapse = collapse

	panel.Rows = {}
	for i = 1, ROWS do
		panel.Rows[i] = CreateRow(i)
	end
	panel.Hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Hint:SetPoint("BOTTOMLEFT", 10, 8)
	panel.Hint:SetPoint("RIGHT", -10, 0)
	panel.Hint:SetJustifyH("LEFT")
	panel.Hint:SetText(L.PROF_GUIDE_HINT)
end

local function MissingText(entry)
	local name = Prof:ItemName(entry.missing) or ("item " .. entry.missing)
	return L.PROF_GUIDE_MISSING:format(entry.missingCount, name)
end

-- Beside the window, past anything that sticks out of its right edge (the
-- profession tabs, for instance).
-- Done when the window opens (placed = false), not at every refresh.
local placed = false

-- Right edge of the frames that start near the window's right border, two levels deep.
local function OuterEdge(frame, right, edge, depth)
	for _, child in ipairs({frame:GetChildren()}) do
		if child ~= panel and child:IsShown() then
			local left, childRight = child:GetLeft(), child:GetRight()
			if left and childRight and left > right - 60 and childRight > edge then
				edge = childRight
			end
			if depth < 2 then
				edge = OuterEdge(child, right, edge, depth + 1)
			end
		end
	end
	return edge
end

local function PlacePanel()
	if placed then return end
	local right = ProfessionsFrame:GetRight()
	if not right then return end
	placed = true
	local edge = OuterEdge(ProfessionsFrame, right, right, 1)
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", edge - right + 4, -24)
end

function Guide:Refresh()
	local craftingPage = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local show = settings.guide and craftingPage and craftingPage:IsVisible() and Prof:IsOwnProfessionOpen()
	if addButton then
		addButton:SetShown(settings.shopping and craftingPage and craftingPage:IsVisible() and Prof:IsOwnProfessionOpen())
	end
	if not show then
		if panel then panel:Hide() end
		return
	end
	if not panel then CreatePanel() end
	PlacePanel()

	local line, name, skill, max = Prof:GetOpenProfession()
	panel.Title:SetText(L.PROF_GUIDE_TITLE:format(name or ""))
	local collapsed = settings.guideCollapsed
	panel.Collapse:SetNormalTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")

	local status = ("%d/%d"):format(skill or 0, max or 0)
	if line and skill and max and max > 0 and skill >= max then
		status = status .. "  |cffff8040" .. L.PROF_GUIDE_TRAIN .. "|r"
	end

	Collect()
	if #candidates == 0 and not (skill and max and max > 0 and skill >= max) then
		status = status .. "  |cffaaaaaa" .. L.PROF_GUIDE_NONE .. "|r"
	end
	panel.Status:SetText(status)

	local shown = collapsed and 0 or math.min(ROWS, #candidates)
	for i, row in ipairs(panel.Rows) do
		local entry = i <= shown and candidates[i]
		row.entry = entry or nil
		if entry then
			local color = Prof.COLORS[entry.difficulty]
			row.Icon:SetTexture(entry.icon)
			row.Name:SetText(entry.name)
			row.Name:SetTextColor(color[1], color[2], color[3])
			if entry.crafts > 0 then
				local text = L.PROF_GUIDE_CAN:format(entry.crafts)
				if entry.bags < entry.crafts then
					text = text .. " |cffaaaaaa" .. L.PROF_GUIDE_BANK .. "|r"
				end
				row.Info:SetText(text)
			else
				row.Info:SetText("|cffff6060" .. MissingText(entry) .. "|r")
			end
			row:Show()
		else
			row:Hide()
		end
	end
	panel.Hint:SetShown(shown > 0)
	panel:SetHeight(shown > 0 and (46 + shown * ROW_HEIGHT + 22) or 44)
	panel:Show()
end

function Guide:Update()
	Prof:Schedule("guide", 0.1, function() Guide:Refresh() end)
end


--[[ Add to the shopping list ]]--

local function SelectedRecipe()
	local form = ProfessionsFrame.CraftingPage.SchematicForm
	if form then
		local ok, info = pcall(form.GetRecipeInfo, form)
		if ok and type(info) == "table" and info.recipeID then
			return info.recipeID
		end
		if form.currentRecipeInfo and form.currentRecipeInfo.recipeID then
			return form.currentRecipeInfo.recipeID
		end
	end
	return selectedRecipe
end

local function Quantity()
	local box = ProfessionsFrame.CraftingPage.CreateMultipleInputBox
	local ok, value = pcall(function() return box:GetValue() end)
	value = ok and tonumber(value)
	return value and value > 0 and math.floor(value) or 1
end

local function CreateAddButton()
	local page = ProfessionsFrame.CraftingPage
	addButton = ns.Widgets.CreateButton(page, L.PROF_ADD_LIST, 130, function()
		local recipeID = SelectedRecipe()
		if not recipeID then return end
		if not Prof:GetRecipe(recipeID) then
			Prof:Scan()
		end
		ns.Shopping:Add(recipeID, Quantity())
	end)
	-- inside the recipe details, bottom left (the line of "Track recipe")
	local form = page.SchematicForm
	if form then
		addButton:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 14)
	else
		addButton:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -320, 40)
	end
	ns.Widgets.AttachTooltip(addButton, L.PROF_ADD_LIST_TIP, L.PROF_ADD_LIST)
	addButton:Hide()
end


--[[ Module ]]--

local function Setup()
	if not ProfessionsFrame or Guide.ready then return end
	Guide.ready = true
	local page = ProfessionsFrame.CraftingPage
	if page then
		CreateAddButton()
		page:HookScript("OnShow", function() Guide:Update() end)
		page:HookScript("OnHide", function() Guide:Update() end)
	end
	ProfessionsFrame:HookScript("OnShow", function()
		placed = false
		Guide:Update()
	end)
	if EventRegistry and EventRegistry.RegisterCallback then
		pcall(EventRegistry.RegisterCallback, EventRegistry, "ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, info)
			selectedRecipe = type(info) == "table" and info.recipeID or nil
		end, Guide)
	end
	Guide:Update()
end

function Guide:OnInitialize()
	settings = ns.db.professions
end

function Guide:OnLogin()
	if C_AddOns.IsAddOnLoaded("Blizzard_Professions") then
		Setup()
	else
		ns:RegisterEvent("ADDON_LOADED", function(_, name)
			if name == "Blizzard_Professions" then
				Setup()
			end
		end)
	end
	Prof:On("RecipesChanged", function() Guide:Update() end)
	Prof:On("Closed", function() if panel then panel:Hide() end end)
	ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
		if panel and panel:IsShown() then Guide:Update() end
	end)
end
