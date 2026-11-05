--[[
	Bags - search
	Queries are compiled once per text change; item data is normalised once per link.

	Syntax: words match name, type or subtype. Prefixes:
	  q:epic  q:>=3   quality (name or number)
	  t:armor         type, subtype or equip slot
	  lvl:>50         item level
	A leading ! negates a term. All terms must match.
--]]

local _, ns = ...
local Search = {}
ns.Search = Search

local GetItemInfo = C_Item.GetItemInfo
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local find, lower, gsub, tonumber = string.find, string.lower, string.gsub, tonumber


--[[ Text normalisation ]]--

local accents = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
	["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
	["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
	["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
	["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
	["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
	["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n",
}

local function Normalize(text)
	if not text or text == "" then return "" end
	return lower((gsub(text, "[\195][\128-\191]", accents)))
end
Search.Normalize = Normalize


--[[ Item data ]]--

local items = {} -- link -> normalised data, only for items the client already knows

local function GetData(link)
	local data = items[link]
	if data then return data end

	local name, _, quality, level, _, itemType, subType, _, equipLoc = GetItemInfo(link)
	if not name then return nil end -- not cached yet, GET_ITEM_INFO_RECEIVED refreshes later

	data = {
		name = Normalize(name),
		type = Normalize(itemType),
		subType = Normalize(subType),
		equip = Normalize(equipLoc and equipLoc ~= "" and _G[equipLoc] or ""),
		quality = quality,
		level = (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)) or level or 0,
	}
	items[link] = data
	return data
end


--[[ Quality names ]]--

local qualities = {
	poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, artifact = 6, heirloom = 7,
}
for i = 0, 8 do
	local name = _G["ITEM_QUALITY" .. i .. "_DESC"]
	if name then
		qualities[Normalize(name)] = i
	end
end

local function QualityValue(text)
	local number = tonumber(text)
	if number then return number end
	for name, value in pairs(qualities) do
		if find(name, text, 1, true) == 1 then
			return value
		end
	end
end


--[[ Compiling ]]--

local function Compare(value, op, target)
	if op == ">" then return value > target
	elseif op == "<" then return value < target
	elseif op == ">=" then return value >= target
	elseif op == "<=" then return value <= target
	end
	return value == target
end

-- Returns a predicate taking (data, quality) for one term.
local function CompileTerm(term)
	local prefix, rest = term:match("^(%a+):(.*)$")

	if prefix == "q" then
		local op, value = rest:match("^([<>=]*)(.+)$")
		value = value and QualityValue(value)
		if not value then return nil end
		return function(_, quality) return quality and Compare(quality, op, value) end

	elseif prefix == "lvl" or prefix == "ilvl" then
		local op, value = rest:match("^([<>=]*)(%d+)$")
		value = tonumber(value)
		if not value then return nil end
		return function(data) return data and Compare(data.level, op, value) end

	elseif prefix == "t" then
		if rest == "" then return nil end
		return function(data)
			return data and (find(data.type, rest, 1, true) or find(data.subType, rest, 1, true) or find(data.equip, rest, 1, true)) and true
		end
	end

	return function(data)
		return data and (find(data.name, term, 1, true) or find(data.type, term, 1, true) or find(data.subType, term, 1, true)) and true
	end
end

local compiledText, compiled

-- Returns a list of {predicate, negate} or nil for an empty query.
local function Compile(text)
	if text == compiledText then return compiled end
	compiledText = text
	compiled = nil

	for word in Normalize(text):gmatch("%S+") do
		local negate = word:sub(1, 1) == "!"
		if negate then
			word = word:sub(2)
		end
		if word ~= "" then
			local predicate = CompileTerm(word)
			if predicate then
				compiled = compiled or {}
				compiled[#compiled + 1] = {predicate, negate}
			end
		end
	end
	return compiled
end

-- True when an item matches the query (or the query is empty).
function Search:Matches(text, link, quality)
	local query = Compile(text or "")
	if not query then return true end
	if not link then return false end

	local data = GetData(link)
	for i = 1, #query do
		local term = query[i]
		local result = term[1](data, quality or (data and data.quality)) and true or false
		if result == term[2] then
			return false
		end
	end
	return true
end

function Search:IsEmpty(text)
	return Compile(text or "") == nil
end
