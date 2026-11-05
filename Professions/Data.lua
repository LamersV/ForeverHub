--[[
	Professions - data

	Recipes are read from the profession window while it is open (only the
	character's own profession, not a linked or guild one):
	  * name, product and reagents of each recipe: they never change, so they are
	    kept once for every character (db.recipes);
	  * which recipes each character knows, with the difficulty color seen last
	    (db.chars), so tooltips can say where a material is used.
	The guide, the shopping list and the tooltips read everything from here, also
	with the window closed.
--]]

local _, ns = ...

local Prof = ns:NewModule("Professions")

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local pairs, ipairs, tonumber, wipe = pairs, ipairs, tonumber, wipe

Prof.SKINNING = 393
Prof.LEATHERWORKING = 165

local DIFFICULTY = Enum.TradeskillRelativeDifficulty or {Optimal = 0, Medium = 1, Easy = 2, Trivial = 3}
Prof.ORANGE, Prof.YELLOW, Prof.GREEN, Prof.GRAY = DIFFICULTY.Optimal, DIFFICULTY.Medium, DIFFICULTY.Easy, DIFFICULTY.Trivial
Prof.COLORS = {
	[Prof.ORANGE] = {1, 0.5, 0.25},
	[Prof.YELLOW] = {1, 1, 0},
	[Prof.GREEN] = {0.25, 0.75, 0.25},
	[Prof.GRAY] = {0.55, 0.55, 0.55},
}

-- Materials sold by vendors (classic). Others are learned at each merchant.
local VENDOR = {
	[2320] = true, [2321] = true, [4291] = true, [8343] = true, [14341] = true, -- threads
	[4289] = true, -- salt
	[2324] = true, [2325] = true, [2604] = true, [2605] = true, [4340] = true, -- bleach, dyes
	[4341] = true, [4342] = true, [6260] = true, [6261] = true, [10290] = true,
	[3371] = true, [3372] = true, [8925] = true, [18256] = true, -- vials
	[2678] = true, [2692] = true, [3713] = true, [159] = true, -- spices, water
	[2880] = true, [3466] = true, [18567] = true, [3857] = true, -- flux, coal
	[4399] = true, [4400] = true, [6217] = true, [4470] = true, -- stocks, copper rod, wood
}

local db, char
local listeners = {}
local index, producers -- reagent itemID -> {recipeID...}; product itemID -> recipeID (this character)
Prof.live = {} -- recipeID -> recipe info of the open profession (this session)


--[[ Messages ]]--

function Prof:On(message, func)
	listeners[message] = listeners[message] or {}
	table.insert(listeners[message], func)
end

function Prof:Fire(message, ...)
	for _, func in ipairs(listeners[message] or {}) do
		func(...)
	end
end

-- Runs func once after delay seconds, however often it is asked for meanwhile.
local scheduled = {}
function Prof:Schedule(key, delay, func)
	if scheduled[key] then return end
	scheduled[key] = true
	C_Timer.After(delay, function()
		scheduled[key] = nil
		func()
	end)
end


--[[ Skills ]]--

local skills -- skill line -> {level, max}

local function ReadSkills()
	skills = {}
	if not (GetProfessions and GetProfessionInfo) then return end
	for i = 1, select("#", GetProfessions()) do
		local slot = select(i, GetProfessions())
		if slot then
			local _, _, level, max, _, _, line = GetProfessionInfo(slot)
			if line then
				skills[line] = {level, max}
			end
		end
	end
end

-- Skill and maximum of a profession, or nil when the character does not have it.
function Prof:GetSkill(line)
	if not skills then ReadSkills() end
	local skill = skills[line]
	if skill then
		return skill[1], skill[2]
	end
end


--[[ The open profession window ]]--

local function Call(name)
	local func = C_TradeSkillUI and C_TradeSkillUI[name]
	return func and func()
end

-- True when the window shows the character's own profession.
function Prof:IsOwnProfessionOpen()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return false end
	if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then return false end
	return not (Call("IsTradeSkillLinked") or Call("IsTradeSkillGuild") or Call("IsNPCCrafting") or Call("IsRuneforging"))
end

-- Skill line, name, skill and maximum of the open profession.
function Prof:GetOpenProfession()
	local child = Call("GetChildProfessionInfo")
	local base = Call("GetBaseProfessionInfo")
	local info = child and (child.maxSkillLevel or 0) > 0 and child or base
	if not info then return end
	local line = info.parentProfessionID or info.professionID
	if not line or line == 0 then
		line = base and base.professionID
	end
	if not line or line == 0 then return end
	return line, info.parentProfessionName or info.professionName or (base and base.professionName),
		info.skillLevel or 0, info.maxSkillLevel or 0
end

local BASIC = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

-- Reagents as a flat list {itemID, amount, itemID, amount...}, plus the product.
local function ReadReagents(recipeID)
	local list = {}
	local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if schematic and schematic.reagentSlotSchematics then
		for _, slot in ipairs(schematic.reagentSlotSchematics) do
			local basic
			if BASIC and slot.reagentType then
				basic = slot.reagentType == BASIC
			else
				basic = slot.required ~= false
			end
			local reagent = slot.reagents and slot.reagents[1]
			if basic and reagent and reagent.itemID and (slot.quantityRequired or 0) > 0 then
				list[#list + 1] = reagent.itemID
				list[#list + 1] = slot.quantityRequired
			end
		end
		return list, schematic.outputItemID
	end
	-- older API
	if C_TradeSkillUI.GetRecipeNumReagents then
		for i = 1, C_TradeSkillUI.GetRecipeNumReagents(recipeID) or 0 do
			local _, _, count = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, i)
			local link = C_TradeSkillUI.GetRecipeReagentItemLink(recipeID, i)
			local id = link and tonumber(link:match("item:(%d+)"))
			if id and count then
				list[#list + 1] = id
				list[#list + 1] = count
			end
		end
		local link = C_TradeSkillUI.GetRecipeItemLink and C_TradeSkillUI.GetRecipeItemLink(recipeID)
		return list, link and tonumber(link:match("item:(%d+)"))
	end
end

function Prof:Scan()
	if not self:IsOwnProfessionOpen() then return end
	local line, name, skill, max = self:GetOpenProfession()
	if not line then return end

	local entry = char[line] or {}
	char[line] = entry
	entry.name, entry.skill, entry.max = name, skill, max
	entry.known = entry.known or {}
	local known = entry.known

	wipe(self.live)
	local seen = {}
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and info.learned and not info.isDummyRecipe and not info.isRecraft then
			seen[id] = true
			self.live[id] = info
			known[id] = info.relativeDifficulty or true
			if not db.recipes[id] then
				local reagents, product = ReadReagents(id)
				if reagents then -- nil while the game has not loaded the recipe yet
					db.recipes[id] = {n = info.name, r = reagents, o = product, i = info.icon}
				end
			end
		end
	end
	for id in pairs(known) do
		if not seen[id] then
			known[id] = nil
		end
	end

	-- the skill also changes here, while crafting
	if skills then
		skills[line] = {skill, max}
	end
	self.openLine = line
	index, producers = nil, nil
	self:Fire("RecipesChanged")
end


--[[ Lookups ]]--

function Prof:GetRecipe(recipeID)
	return db.recipes[recipeID]
end

function Prof:GetCharacters()
	return db.chars
end

function Prof:GetKey()
	return self.key
end

function Prof:GetProfessionData(line)
	return char[line]
end

local function BuildIndex()
	index, producers = {}, {}
	for key, professions in pairs(db.chars) do
		for line, entry in pairs(professions) do
			for recipeID in pairs(entry.known or {}) do
				local recipe = db.recipes[recipeID]
				if recipe then
					local reagents = recipe.r
					for i = 1, #reagents, 2 do
						local list = index[reagents[i]]
						if not list then
							list = {}
							index[reagents[i]] = list
						end
						list[#list + 1] = {recipe = recipeID, key = key, line = line}
					end
					if key == Prof.key and recipe.o then
						producers[recipe.o] = recipeID
					end
				end
			end
		end
	end
end

-- Known recipes (of any character on the realm) that use an item:
-- {recipe = id, key = "Name-Realm", line = skill line}.
function Prof:GetRecipesUsing(itemID)
	if not index then BuildIndex() end
	return index[itemID]
end

-- Recipe of this character that makes an item.
function Prof:GetProducer(itemID)
	if not producers then BuildIndex() end
	return producers[itemID]
end

-- Bags and bank (the game keeps the bank count after the bank is closed).
function Prof:Count(itemID)
	return GetItemCount(itemID, true) or 0, GetItemCount(itemID) or 0
end

-- Unit price paid at a vendor, if seen, else nil.
function Prof:GetVendorPrice(itemID)
	local price = db.vendor[itemID]
	return type(price) == "number" and price or nil
end

function Prof:IsVendorItem(itemID)
	return VENDOR[itemID] or db.vendor[itemID] ~= nil
end

function Prof:SetVendorPrice(itemID, price)
	db.vendor[itemID] = price
end

-- Rough value of one unit, to compare recipe costs: the vendor price when
-- bought from one, else the item's sell price.
function Prof:GetValue(itemID)
	return self:GetVendorPrice(itemID) or select(11, GetItemInfo(itemID)) or 0
end

function Prof:ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or GetItemInfo(itemID)
	return name
end

function Prof:ItemIcon(itemID)
	return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or select(10, GetItemInfo(itemID))
end


--[[ Module ]]--

function Prof:OnInitialize()
	db = ns.db.professions
	self.key = UnitName("player") .. "-" .. GetRealmName()
	db.chars[self.key] = db.chars[self.key] or {}
	char = db.chars[self.key]
	db.list[self.key] = db.list[self.key] or {}
	self.list = db.list[self.key]
	self.settings = db
end

function Prof:OnLogin()
	local function Rescan()
		Prof:Schedule("scan", 0.3, function() Prof:Scan() end)
	end
	for _, event in ipairs({"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED"}) do
		pcall(ns.RegisterEvent, ns, event, Rescan)
	end
	pcall(ns.RegisterEvent, ns, "TRADE_SKILL_CLOSE", function()
		Prof.openLine = nil
		wipe(Prof.live)
		Prof:Fire("Closed")
	end)
	ns:RegisterEvent("SKILL_LINES_CHANGED", function()
		skills = nil
		Prof:Fire("SkillsChanged")
	end)
end
