--[[
	Merchant helpers

	Junk: gray items plus items the player marked (Alt+click in the bags), minus gray
	items the player chose to keep. Sold from the "sell junk" button, or on its own
	when a merchant opens (option), in small batches so the server accepts every sale.

	Repair: when a merchant that repairs opens, guild funds first (if allowed and
	enough), then the player's money.

	On opening a merchant the steps run in order: sell, repair, restock, so the money
	from the junk pays the repair. Holding Shift while opening skips all of them.
	If Leatrix Plus has the same option on, ForeverHub leaves that step to it.

	Restock: per character list of item -> amount to keep in the bags. When a
	merchant that sells one of them opens, the missing amount is bought.
--]]

local _, ns = ...
local L = ns.L

local Merchant = ns:NewModule("Merchant")
Merchant.atMerchant = false

local C_Container = C_Container
local GetContainerNumSlots, GetContainerItemInfo = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local SELL_BATCH, SELL_DELAY = 8, 0.25

local settings, restock -- ns.db.bags, this character's restock list


--[[ Junk ]]--

function Merchant:IsJunk(info)
	if not info or not info.itemID or info.hasNoValue then return false end
	local id = info.itemID
	if settings.junkMarked[id] then return true end
	return info.quality == 0 and not settings.junkKeep[id]
end

local function SellPrice(info)
	local price = select(11, GetItemInfo(info.hyperlink or info.itemID))
	return (price or 0) * (info.stackCount or 1)
end

-- Every junk slot in the bags, with the total vendor value.
function Merchant:GetJunk()
	local slots, value = {}, 0
	for bag = 0, NUM_BAGS do
		for slot = 1, GetContainerNumSlots(bag) or 0 do
			local info = GetContainerItemInfo(bag, slot)
			if self:IsJunk(info) then
				slots[#slots + 1] = {bag, slot}
				value = value + SellPrice(info)
			end
		end
	end
	return slots, value
end

local selling

-- silent: no message when there is nothing to sell. onDone: called when the sale ends.
function Merchant:SellJunk(silent, onDone)
	if selling or not self.atMerchant then return end
	local slots, value = self:GetJunk()
	if #slots == 0 then
		if not silent then
			ns:Print(L.JUNK_NONE)
		end
		if onDone then onDone() end
		return
	end

	selling = true
	local index = 1
	local function Step()
		-- outside a merchant, "using" an item would equip or consume it
		if not Merchant.atMerchant then
			selling = false
			return
		end
		for _ = 1, SELL_BATCH do
			local entry = slots[index]
			if not entry then
				selling = false
				ns:Print(L.JUNK_SOLD:format(#slots, GetMoneyString(value, true)))
				-- give the server a moment to credit the money before repairing
				if onDone then C_Timer.After(SELL_DELAY, onDone) end
				return
			end
			local info = GetContainerItemInfo(entry[1], entry[2])
			if info and not info.isLocked and Merchant:IsJunk(info) then
				C_Container.UseContainerItem(entry[1], entry[2])
			end
			index = index + 1
		end
		C_Timer.After(SELL_DELAY, Step)
	end
	Step()
end

-- Alt+click in the bags: gray items toggle "keep", others toggle "junk".
function Merchant:ToggleJunk(bag, slot)
	local info = GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then return end
	local id, link = info.itemID, info.hyperlink or ""
	if info.quality == 0 then
		settings.junkKeep[id] = not settings.junkKeep[id] or nil
		ns:Print((settings.junkKeep[id] and L.JUNK_KEEP or L.JUNK_UNKEEP):format(link))
	else
		settings.junkMarked[id] = not settings.junkMarked[id] or nil
		ns:Print((settings.junkMarked[id] and L.JUNK_MARKED or L.JUNK_UNMARKED):format(link))
	end
	if ns.Bags and ns.Bags.active then
		ns.Bags:UpdateItems()
	end
end


--[[ Restock ]]--

local function MerchantItem(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then
			return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
		end
	end
	local _, _, price, stackCount, numAvailable, _, _, extendedCost = GetMerchantItemInfo(index)
	return price, stackCount, numAvailable, extendedCost
end

local function Restock()
	if not ns.db.merchant.restockEnabled or not next(restock) then return end

	local bought = {}
	for index = 1, GetMerchantNumItems() do
		local id = GetMerchantItemID and GetMerchantItemID(index)
		if not id then
			local link = GetMerchantItemLink(index)
			id = link and tonumber(link:match("item:(%d+)"))
		end
		local want = id and restock[id]
		local need = want and want - GetItemCount(id)
		if need and need > 0 then
			local price, stackCount, numAvailable, extendedCost = MerchantItem(index)
			stackCount = math.max(stackCount or 1, 1)
			if price and price > 0 and not extendedCost then
				-- merchants sell in batches of stackCount; round up to whole batches
				local amount = math.ceil(need / stackCount) * stackCount
				if numAvailable and numAvailable >= 0 then
					amount = math.min(amount, numAvailable * stackCount)
				end
				local affordable = math.floor(GetMoney() / (price / stackCount))
				amount = math.min(amount, math.floor(affordable / stackCount) * stackCount)

				local maxStack = math.max(GetMerchantItemMaxStack(index) or stackCount, stackCount)
				local chunk = math.floor(maxStack / stackCount) * stackCount
				local remaining = amount
				while remaining > 0 do
					local quantity = math.min(remaining, chunk)
					BuyMerchantItem(index, quantity)
					remaining = remaining - quantity
				end
				if amount > 0 then
					bought[#bought + 1] = amount .. "x " .. (GetMerchantItemLink(index) or id)
				end
			end
		end
	end
	if #bought > 0 then
		ns:Print(L.RESTOCKED:format(table.concat(bought, ", ")))
	end
end

-- /fh restock [item] [amount]
local function RestockCommand(rest)
	local id = tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)%s"))
	local amount = tonumber(rest:match("(%d+)%s*$"))
	if not id or not amount or rest:match("^%d+$") then
		ns:Print(L.RESTOCK_HELP)
		if next(restock) then
			for itemID, want in pairs(restock) do
				local link = select(2, GetItemInfo(itemID)) or ("item " .. itemID)
				print(("  %s: |cffffffff%d|r"):format(link, want))
			end
		else
			print("  " .. L.RESTOCK_EMPTY)
		end
		return
	end
	restock[id] = amount > 0 and amount or nil
	local link = select(2, GetItemInfo(id)) or ("item " .. id)
	ns:Print(amount > 0 and L.RESTOCK_SET:format(link, amount) or L.RESTOCK_REMOVED:format(link))
end


--[[ Repair ]]--

local function RepairOwn(cost)
	if GetMoney() >= cost then
		RepairAllItems()
		ns:Print(L.REPAIRED:format(GetMoneyString(cost, true)))
	else
		ns:Print(L.REPAIR_NO_MONEY:format(GetMoneyString(cost, true)))
	end
end

local function Repair()
	if not ns.db.merchant.autoRepair or ns:LeatrixHas("AutoRepairGear") then return end
	if not Merchant.atMerchant or not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost, needed = GetRepairAllCost()
	if not needed or not cost or cost <= 0 then return end

	local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
	if ns.db.merchant.guildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
		and (limit == -1 or limit >= cost) then -- -1: no limit (guild master)
		-- the guild bank balance is unknown until the bank is opened, so try and check
		RepairAllItems(true)
		C_Timer.After(0.5, function()
			if not Merchant.atMerchant then return end
			local left = GetRepairAllCost()
			if left and left > 0 then
				RepairOwn(left)
			else
				ns:Print(L.REPAIRED_GUILD:format(GetMoneyString(cost, true)))
			end
		end)
		return
	end
	RepairOwn(cost)
end


--[[ Module ]]--

-- Sell, then repair, then restock.
local function OnMerchantShow()
	if IsShiftKeyDown() then return end
	local function AfterSale()
		Repair()
		Restock()
	end
	if ns.db.merchant.autoSell and not ns:LeatrixHas("AutoSellJunk") then
		Merchant:SellJunk(true, AfterSale)
	else
		AfterSale()
	end
end

function Merchant:OnInitialize()
	settings = ns.db.bags
end

local function SetAtMerchant(value)
	if Merchant.atMerchant == value then return end
	Merchant.atMerchant = value
	if ns.Bags and ns.Bags.active then
		ns.Bags:UpdateItems()
	end
end

function Merchant:OnLogin()
	local key = UnitName("player") .. "-" .. GetRealmName()
	ns.db.merchant.restock[key] = ns.db.merchant.restock[key] or {}
	restock = ns.db.merchant.restock[key]

	ns:RegisterEvent("MERCHANT_SHOW", function()
		SetAtMerchant(true)
		OnMerchantShow()
	end)
	ns:RegisterEvent("MERCHANT_CLOSED", function() SetAtMerchant(false) end)

	ns:RegisterCommand("junk", function() Merchant:SellJunk() end, "Sell junk (at a merchant)")
	ns:RegisterCommand("restock", RestockCommand, "Items to keep stocked: /fh restock [item link] [amount]")
end
