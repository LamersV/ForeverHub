--[[
	Professions - tooltips

	Materials: the known recipes (of every character on the realm) that use the
	item, colored by the difficulty seen last, and how many the shopping list needs.

	Creatures: the Skinning skill needed, for beasts and for dead creatures the
	game marks as skinnable, colored as gathering colors work (red: cannot;
	orange, yellow, green: chance of a point; gray: no point).
	Classic rule: up to level 10 skill 1; levels 11-20 (level - 10) x 10;
	from 21 level x 5.
--]]

local _, ns = ...
local L = ns.L
local Prof = ns.Professions

local ProfTooltip = ns:NewModule("ProfessionTooltip")

local issecretvalue = issecretvalue or function() return false end
local MAX_RECIPES = 5
local settings


--[[ Materials ]]--

local function AddMaterial(tooltip, data)
	if not settings.tooltip or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
	local itemID = data and data.id
	if not itemID or issecretvalue(itemID) then return end

	local uses = Prof:GetRecipesUsing(itemID)
	local need = ns.Shopping and ns.Shopping:GetNeed(itemID)
	if not uses and not need then return end

	tooltip:AddLine(" ")
	if need then
		local have = Prof:Count(itemID)
		local color = have >= need and "|cff40ff40" or "|cffff5040"
		tooltip:AddDoubleLine(L.PROF_TIP_LIST, ("%s%d|r/%d"):format(color, math.min(have, need), need), 1, 0.82, 0, 1, 1, 1)
	end
	if not uses then return end

	local chars = Prof:GetCharacters()
	local profession = chars[uses[1].key] and chars[uses[1].key][uses[1].line]
	tooltip:AddLine(L.PROF_TIP_USED:format(#uses, profession and profession.name or ""), 1, 0.82, 0)
	for i = 1, math.min(#uses, MAX_RECIPES) do
		local use = uses[i]
		local recipe = Prof:GetRecipe(use.recipe)
		local entry = chars[use.key] and chars[use.key][use.line]
		local difficulty = entry and entry.known and entry.known[use.recipe]
		local color = Prof.COLORS[difficulty] or Prof.COLORS[Prof.GRAY]
		if use.key == Prof.key and type(difficulty) ~= "number" then
			color = {1, 1, 1}
		end
		local amount = 0
		for j = 1, #recipe.r, 2 do
			if recipe.r[j] == itemID then
				amount = recipe.r[j + 1]
				break
			end
		end
		local who = use.key ~= Prof.key and (" |cff888888(" .. use.key:match("^[^-]+") .. ")|r") or ""
		tooltip:AddDoubleLine("   " .. (recipe.n or "?") .. who, "x" .. amount, color[1], color[2], color[3], 0.8, 0.8, 0.8)
	end
	if #uses > MAX_RECIPES then
		tooltip:AddLine("   " .. L.PROF_TIP_MORE:format(#uses - MAX_RECIPES), 0.6, 0.6, 0.6)
	end
end


--[[ Skinning ]]--

local function RequiredSkill(level)
	if level <= 10 then return 1 end
	if level <= 20 then return (level - 10) * 10 end
	return level * 5
end

local beastName
local function BeastName()
	if beastName == nil then
		local info = C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo and C_CreatureInfo.GetCreatureTypeInfo(1)
		beastName = info and info.name or L.PROF_BEAST
	end
	return beastName
end

local function MarkedSkinnable(data)
	local text = UNIT_SKINNABLE_LEATHER
	if not text or not data or not data.lines then return false end
	for _, line in ipairs(data.lines) do
		if line.leftText == text then
			return true
		end
	end
	return false
end

local function AddSkinning(tooltip, data)
	local skill = Prof:GetSkill(Prof.SKINNING)
	if not skill then return end
	local _, unit = tooltip:GetUnit()
	if not unit or issecretvalue(unit) or UnitIsPlayer(unit) then return end

	local skinnable
	if UnitIsDead(unit) then
		skinnable = MarkedSkinnable(data)
	else
		skinnable = UnitCreatureType(unit) == BeastName() and UnitCanAttack("player", unit)
	end
	if not skinnable then return end

	local level = UnitLevel(unit)
	if not level or issecretvalue(level) then return end
	if level < 1 then
		tooltip:AddLine(L.PROF_SKIN_UNKNOWN, 1, 0.3, 0.3)
		return
	end
	local required = RequiredSkill(level)
	local r, g, b
	if skill < required then
		r, g, b = 1, 0.25, 0.25
	elseif skill < required + 25 then
		r, g, b = 1, 0.5, 0.25
	elseif skill < required + 50 then
		r, g, b = 1, 1, 0
	elseif skill < required + 100 then
		r, g, b = 0.25, 0.75, 0.25
	else
		r, g, b = 0.55, 0.55, 0.55
	end
	tooltip:AddLine(L.PROF_SKIN_REQUIRED:format(required, skill), r, g, b)
end

local function OnUnit(tooltip, data)
	if settings.skinning and tooltip == GameTooltip then
		pcall(AddSkinning, tooltip, data) -- secret values raise errors when tested; then the line is skipped
	end
end


--[[ Module ]]--

function ProfTooltip:OnInitialize()
	settings = ns.db.professions
end

function ProfTooltip:OnLogin()
	if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddMaterial)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
end
