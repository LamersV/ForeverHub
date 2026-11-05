--[[
	Bags - data
	Single source of item data: live slot info for the current character (read once
	per change and shared by the windows), plus a saved snapshot of every character
	used for offline viewing and tooltip counts.
--]]

local _, ns = ...
local Data = ns:NewModule("BagData")

local C_Container = C_Container
local GetContainerNumSlots, GetContainerItemInfo = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local pairs, ipairs, tonumber, wipe = pairs, ipairs, tonumber, wipe

local BANK_CONTAINER = BANK_CONTAINER
local KEYRING_CONTAINER = KEYRING_CONTAINER or -2
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

Data.numBags = NUM_BAGS
Data.live = {} -- bag -> {size = n, [slot] = containerInfo}
Data.atBank = false

local dirty = {}
local listeners = {}
local player, realmChars
local countsCache = {} -- character name -> {[itemID] = {bags, bank, equip}}


--[[ Bag lists ]]--

Data.inventoryBags = {}
for bag = 0, NUM_BAGS do
	Data.inventoryBags[#Data.inventoryBags + 1] = bag
end
if HasKey and HasKey() then
	Data.inventoryBags[#Data.inventoryBags + 1] = KEYRING_CONTAINER
end

-- Bank layout differs between clients: tabs (modern) or the classic bank plus bag slots.
local function HasBankTabs()
	return C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum.BankType and Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1
end

function Data:GetBankBags()
	if HasBankTabs() then
		local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
		if ok and type(ids) == "table" and #ids > 0 then
			local bags = {}
			for i, id in ipairs(ids) do
				bags[i] = id
			end
			return bags
		end
	end

	local bags = {}
	if BANK_CONTAINER then
		bags[1] = BANK_CONTAINER
	end
	local count = NUM_BANKBAGSLOTS or (Constants.InventoryConstants and Constants.InventoryConstants.NumCharacterBankSlots) or 0
	for bag = NUM_BAGS + 1, NUM_BAGS + count do
		bags[#bags + 1] = bag
	end
	return bags
end

function Data:IsBankBag(bag)
	return bag == BANK_CONTAINER or bag > NUM_BAGS
end

-- Inventory slot of the bag item itself (nil for backpack, bank and keyring).
function Data:GetBagInventorySlot(bag)
	if bag <= 0 or bag == KEYRING_CONTAINER then return end
	local ok, slot = pcall(C_Container.ContainerIDToInventoryID, bag)
	return ok and slot or nil
end


--[[ Bag types ]]--

-- Container families (bit flags) of profession and special bags, in priority order.
-- Colors tint the empty slots of those bags.
Data.bagTypes = {
	{key = "herb", bit = 0x0020, r = 0.30, g = 0.85, b = 0.30, words = {"herbor", "herb"}},
	{key = "leather", bit = 0x0008, r = 0.95, g = 0.62, b = 0.32, words = {"esfola", "skinn", "leatherwork", "coureir"}},
	{key = "enchant", bit = 0x0040, r = 0.95, g = 0.45, b = 0.85, words = {"encanta", "enchant"}},
	{key = "engineering", bit = 0x0080, r = 0.35, g = 0.80, b = 0.85, words = {"engenhar", "engineer"}},
	{key = "mining", bit = 0x0400, r = 0.70, g = 0.58, b = 0.45, words = {"minera", "mining"}},
	{key = "gems", bit = 0x0200, r = 0.95, g = 0.35, b = 0.45, words = {"joalh", "jewel", "gems"}},
	{key = "inscription", bit = 0x0010, r = 0.45, g = 0.70, b = 1.00, words = {"escriv", "inscription"}},
	{key = "fishing", bit = 0x8000, r = 0.30, g = 0.55, b = 1.00, words = {"pesca", "fishing", "tackle"}},
	{key = "cooking", bit = 0x10000, r = 1.00, g = 0.40, b = 0.30, words = {"culin", "cooking"}},
	{key = "soul", bit = 0x0004, r = 0.60, g = 0.30, b = 0.85, words = {"alma", "soul"}},
	{key = "quiver", bit = 0x0001, r = 0.85, g = 0.68, b = 0.38, words = {"aljava", "quiver"}},
	{key = "ammo", bit = 0x0002, r = 0.68, g = 0.68, b = 0.74, words = {"munição", "munic", "ammo"}},
	{key = "keys", bit = 0x0100, r = 1.00, g = 0.88, b = 0.30, words = {}},
}
local OTHER_TYPE = {key = "other", r = 0.95, g = 0.85, b = 0.50}
local bagTypeByKey = {other = OTHER_TYPE}
for _, info in ipairs(Data.bagTypes) do
	bagTypeByKey[info.key] = info
end

-- Returns the type of a bag (nil for normal bags) from its family flags, falling back
-- to the bag's name: some clients report profession bags with an unknown or zero family.
function Data:GetBagType(bag, family, link)
	if bag == KEYRING_CONTAINER then
		return bagTypeByKey.keys
	end
	family = tonumber(family) or 0
	if family ~= 0 then
		for _, info in ipairs(self.bagTypes) do
			if bit.band(family, info.bit) ~= 0 then
				return info
			end
		end
	end

	local name = link and link:match("%[(.-)%]")
	if name then
		name = name:lower()
		for _, info in ipairs(self.bagTypes) do
			for _, word in ipairs(info.words) do
				if name:find(word, 1, true) then
					return info
				end
			end
		end
	end
	return family ~= 0 and OTHER_TYPE or nil
end


--[[ Live scanning ]]--

local function Encode(info)
	return (info.quality or 1) .. ";" .. (info.stackCount or 1) .. ";" .. info.hyperlink
end

-- Rereads a bag from the game and refreshes its saved snapshot.
local function ScanBag(bag)
	local isBank = Data:IsBankBag(bag)
	if isBank and not Data.atBank then return end

	local size = GetContainerNumSlots(bag) or 0
	local _, family = GetContainerNumFreeSlots(bag)
	family = tonumber(family) or 0
	local live = Data.live[bag] or {}
	wipe(live)
	live.size = size
	Data.live[bag] = live

	local saved = player.bags[bag] or {}
	wipe(saved)
	saved.size = size
	saved.family = family ~= 0 and family or nil

	for slot = 1, size do
		local info = GetContainerItemInfo(bag, slot)
		if info and info.hyperlink then
			live[slot] = info
			saved[slot] = Encode(info)
		end
	end

	local invSlot = Data:GetBagInventorySlot(bag)
	saved.link = invSlot and GetInventoryItemLink("player", invSlot) or nil
	player.bags[bag] = size > 0 and saved or nil
	countsCache[ns.playerName] = nil
end

local function Fire(event, ...)
	for i = 1, #listeners do
		listeners[i](event, ...)
	end
end

local changed = {}

local function Flush()
	if not next(dirty) then return end
	wipe(changed)
	for bag in pairs(dirty) do
		ScanBag(bag)
		changed[bag] = true
	end
	wipe(dirty)
	Fire("BAGS_CHANGED", changed)
end

local function MarkDirty(bag)
	dirty[bag] = true
	ns:Defer("bagdata", Flush)
end

function Data:ScanAll(bags)
	for _, bag in ipairs(bags) do
		dirty[bag] = true
	end
	Flush()
end

function Data:RegisterListener(func)
	listeners[#listeners + 1] = func
end


--[[ Saved snapshot ]]--

local function ScanEquipment()
	local equip = player.equip
	wipe(equip)
	for slot = 1, 19 do
		equip[slot] = GetInventoryItemLink("player", slot)
	end
	countsCache[ns.playerName] = nil
end

function Data:GetCharacters()
	return realmChars
end

function Data:GetCharacter(name)
	return realmChars[name or ns.playerName]
end

function Data:DeleteCharacter(name)
	if name ~= ns.playerName then
		realmChars[name] = nil
		countsCache[name] = nil
	end
end

-- Decodes a saved slot: quality, count, link.
function Data:DecodeSlot(value)
	local quality, count, link = value:match("^(%d+);(%d+);(.+)$")
	return tonumber(quality), tonumber(count), link
end

local function ItemID(link)
	return tonumber(link:match("item:(%d+)"))
end

local function BuildCounts(char)
	local counts = {}
	local function Add(id, kind, amount)
		local entry = counts[id]
		if not entry then
			entry = {0, 0, 0}
			counts[id] = entry
		end
		entry[kind] = entry[kind] + amount
	end

	for bag, data in pairs(char.bags) do
		local kind = Data:IsBankBag(bag) and 2 or 1
		for slot = 1, data.size or 0 do
			local value = data[slot]
			if value then
				local _, count, link = Data:DecodeSlot(value)
				local id = link and ItemID(link)
				if id then
					Add(id, kind, count)
				end
			end
		end
	end
	for _, link in pairs(char.equip or {}) do
		local id = ItemID(link)
		if id then
			Add(id, 3, 1)
		end
	end
	return counts
end

-- Returns an iterator-friendly list of {name, class, bags, bank, equip} for an item.
function Data:GetItemCounts(itemID)
	local result
	for name, char in pairs(realmChars) do
		local counts = countsCache[name]
		if not counts then
			counts = BuildCounts(char)
			countsCache[name] = counts
		end
		local entry = counts[itemID]
		if entry then
			result = result or {}
			result[#result + 1] = {name = name, class = char.class, bags = entry[1], bank = entry[2], equip = entry[3]}
		end
	end
	return result
end


--[[ Events ]]--

local function OnBankOpened()
	if Data.atBank then return end
	Data.atBank = true
	Data:ScanAll(Data:GetBankBags())
	Fire("BANK_OPENED")
end

local function OnBankClosed()
	if not Data.atBank then return end
	Data.atBank = false
	Fire("BANK_CLOSED")
end

function Data:OnLogin()
	if not ns:IsModuleActive("bags") then return end
	self.active = true

	ns.playerName = UnitName("player")
	ns.realm = GetRealmName()

	local db = ns.db
	db.realms = db.realms or {}
	db.realms[ns.realm] = db.realms[ns.realm] or {}
	realmChars = db.realms[ns.realm]
	realmChars[ns.playerName] = realmChars[ns.playerName] or {}
	player = realmChars[ns.playerName]
	player.bags = player.bags or {}
	player.equip = player.equip or {}
	player.class = select(2, UnitClass("player"))
	player.faction = UnitFactionGroup("player")
	player.money = GetMoney()

	-- bags that no longer exist on this character (e.g. after removing a bag)
	for _, bag in ipairs(self.inventoryBags) do
		dirty[bag] = true
	end
	Flush()
	ScanEquipment()

	ns:RegisterEvent("BAG_UPDATE", function(_, bag) MarkDirty(bag) end)
	ns:RegisterEvent("BAG_UPDATE_DELAYED", Flush)
	ns:RegisterEvent("BAG_CONTAINER_UPDATE", function()
		for _, bag in ipairs(Data.inventoryBags) do
			dirty[bag] = true
		end
		Flush()
	end)
	ns:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
		if BANK_CONTAINER then
			MarkDirty(BANK_CONTAINER)
		end
		-- a bank bag may have been swapped as well
		for _, bag in ipairs(Data:GetBankBags()) do
			if bag ~= BANK_CONTAINER and (Data.live[bag] and Data.live[bag].size or 0) ~= (GetContainerNumSlots(bag) or 0) then
				MarkDirty(bag)
			end
		end
	end)
	ns:RegisterEvent("ITEM_LOCK_CHANGED", function(_, bag, slot)
		if not slot then return end
		local live = Data.live[bag]
		if live and slot <= (live.size or 0) then
			live[slot] = GetContainerItemInfo(bag, slot)
			Fire("SLOT_CHANGED", bag, slot)
		end
	end)
	ns:RegisterEvent("BAG_UPDATE_COOLDOWN", function() Fire("COOLDOWNS") end)
	ns:RegisterEvent("QUEST_ACCEPTED", function() Fire("QUESTS") end)
	ns:RegisterEvent("UNIT_QUEST_LOG_CHANGED", function(_, unit)
		if unit == "player" then
			Fire("QUESTS")
		end
	end)
	ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
		if success then
			Fire("ITEM_INFO", itemID)
		end
	end)
	ns:RegisterEvent("PLAYER_MONEY", function()
		player.money = GetMoney()
		Fire("MONEY")
	end)
	ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", ScanEquipment)
	ns:RegisterEvent("BANKFRAME_OPENED", OnBankOpened)
	ns:RegisterEvent("BANKFRAME_CLOSED", OnBankClosed)
	if Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker then
		-- fallback in case BANKFRAME_OPENED is not fired; wait a frame so bank data is ready
		ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
			if kind == Enum.PlayerInteractionType.Banker then
				C_Timer.After(0, OnBankOpened)
			end
		end)
		ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
			if kind == Enum.PlayerInteractionType.Banker then
				OnBankClosed()
			end
		end)
	end
end
