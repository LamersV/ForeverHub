--[[
	/fh bankinfo: dumps how this client's bank works (bank tabs, classic bag
	slots, purchase costs, Blizzard's bank frame) into a window to copy.
	Read-only; used to support the bank of the WoW Forever client.
--]]

local _, ns = ...

local lines

local function Add(fmt, ...)
	lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
end

local function Value(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	if type(v) == "table" then
		local parts = {}
		for k, item in pairs(v) do
			parts[#parts + 1] = tostring(k) .. "=" .. (type(item) == "table" and "{...}" or tostring(item))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

-- Calls a global or C_ function by path, printing every return value.
local function Call(label, func, ...)
	if type(func) ~= "function" then
		Add("%s: (missing)", label)
		return
	end
	local results = {pcall(func, ...)}
	if not results[1] then
		Add("%s: ERROR %s", label, tostring(results[2]))
		return
	end
	local out = {}
	for i = 2, #results do
		out[#out + 1] = Value(results[i])
	end
	Add("%s: %s", label, #out > 0 and table.concat(out, " | ") or "(nothing)")
	return unpack(results, 2)
end

local function Frame(name, frame, depth)
	if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then return end
	local ok, objType = pcall(frame.GetObjectType, frame)
	if not ok then return end
	local id = frame.GetID and frame:GetID() or ""
	Add("%s%s [%s] id=%s shown=%s", ("  "):rep(depth), name, objType, tostring(id), tostring(frame:IsShown()))
	if depth >= 3 or not frame.GetChildren then return end

	-- children by parentKey, then the unnamed ones
	local keyOf = {}
	for key, value in pairs(frame) do
		if type(key) == "string" and type(value) == "table" and value ~= frame then
			keyOf[value] = key
		end
	end
	for _, child in ipairs({frame:GetChildren()}) do
		local childName = child:GetName() or keyOf[child] or "?"
		Frame(childName, child, depth + 1)
	end
end

local function Dump()
	lines = {}
	local Character = Enum and Enum.BankType and Enum.BankType.Character

	Add("== client")
	Add("build: %s", Value({GetBuildInfo()}))
	Add("WOW_PROJECT_ID=%s money=%s atBank=%s", tostring(WOW_PROJECT_ID), tostring(GetMoney()), tostring(ns.BagData and ns.BagData.atBank))

	Add("== constants")
	for _, name in ipairs({"NUM_BANKBAGSLOTS", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "BANK_CONTAINER",
		"REAGENTBANK_CONTAINER", "KEYRING_CONTAINER", "NUM_BANKGENERIC_SLOTS", "BANK_BAG", "BANK_BAG_PURCHASE"}) do
		Add("%s=%s", name, Value(_G[name]))
	end
	local constants = Constants and Constants.InventoryConstants
	Add("InventoryConstants=%s", Value(constants))
	Add("Enum.BagIndex=%s", Value(Enum and Enum.BagIndex))
	Add("Enum.BankType=%s", Value(Enum and Enum.BankType))

	Add("== classic bag slots")
	local numSlots = Call("GetNumBankSlots()", GetNumBankSlots)
	Call("GetBankSlotCost(numSlots)", GetBankSlotCost, numSlots or 0)
	Add("PurchaseSlot=%s", type(PurchaseSlot))
	Add("popup CONFIRM_BUY_BANK_SLOT=%s", tostring(StaticPopupDialogs and StaticPopupDialogs.CONFIRM_BUY_BANK_SLOT ~= nil))

	Add("== C_Bank")
	if C_Bank then
		local names = {}
		for name in pairs(C_Bank) do
			names[#names + 1] = name
		end
		table.sort(names)
		Add("functions: %s", table.concat(names, ", "))
		if Character then
			Call("FetchPurchasedBankTabIDs", C_Bank.FetchPurchasedBankTabIDs, Character)
			Call("FetchPurchasedBankTabData", C_Bank.FetchPurchasedBankTabData, Character)
			Call("CanPurchaseBankTab", C_Bank.CanPurchaseBankTab, Character)
			Call("HasMaxBankTabs", C_Bank.HasMaxBankTabs, Character)
			Call("FetchNextPurchasableBankTabData", C_Bank.FetchNextPurchasableBankTabData, Character)
			Call("FetchNextPurchasableBankTabCost", C_Bank.FetchNextPurchasableBankTabCost, Character)
			Call("CanUseBank", C_Bank.CanUseBank, Character)
			Call("FetchMaxNumBankTabs", C_Bank.FetchMaxNumBankTabs, Character)
			Call("DoesBankTypeSupportMoneyTransfer", C_Bank.DoesBankTypeSupportMoneyTransfer, Character)
			Call("FetchDepositedMoney", C_Bank.FetchDepositedMoney, Character)
		end
	else
		Add("C_Bank: (missing)")
	end

	Add("== containers (bag: slots, inventory slot)")
	for bag = -3, 20 do
		local ok, size = pcall(C_Container.GetContainerNumSlots, bag)
		local okInv, inv = pcall(C_Container.ContainerIDToInventoryID, bag)
		if (ok and size and size > 0) or (okInv and inv) then
			local link = okInv and inv and GetInventoryItemLink("player", inv)
			Add("bag %d: %s slots, inv %s %s", bag, tostring(ok and size), tostring(okInv and inv), link or "")
		end
	end

	Add("== Blizzard bank frame")
	Frame("BankFrame", BankFrame, 0)
	for _, name in ipairs({"BankSlotsFrame", "BankFramePurchaseInfo", "BankFramePurchaseButton",
		"BankFrameDetailMoneyFrame", "BankFrameMoneyFrame", "BankPanel", "AccountBankPanel"}) do
		Add("%s: %s", name, _G[name] and "exists" or "-")
	end

	Add("== bank popups and globals")
	local found = {}
	for name in pairs(StaticPopupDialogs or {}) do
		if name:find("BANK") then
			found[#found + 1] = name
		end
	end
	table.sort(found)
	Add("popups: %s", table.concat(found, ", "))
	found = {}
	for name, value in pairs(_G) do
		if type(name) == "string" and type(value) == "function" and (name:find("Bank") or name:find("PurchaseSlot")) then
			found[#found + 1] = name
		end
	end
	table.sort(found)
	Add("functions: %s", table.concat(found, ", "))

	ns.Chat:OpenCopy("Bank info", table.concat(lines, "\n"))
	lines = nil
end

ns:RegisterCommand("bankinfo", Dump, "Show how this client's bank works (to copy)")
