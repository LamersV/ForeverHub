--[[
	Bags - Blizzard integration

	Blizzard's bag frames keep working as the "state" of the inventory: every way the
	game opens or closes bags (keybinds, bag bar, merchants, mail...) still runs, but
	the frames live under a hidden parent and our window mirrors whether any is open.
	Only secure hooks are used, so no Blizzard code is replaced.

	The bank frame is parented to an invisible, tiny frame instead of a hidden one so
	its OnShow/OnHide (which talk to the server) keep running normally.
--]]

local _, ns = ...
local Bags, Data = ns.Bags, ns.BagData

local Hooks = ns:NewModule("BagHooks")

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local invisibleParent = CreateFrame("Frame", nil, UIParent)
invisibleParent:SetAlpha(0)
invisibleParent:SetScale(0.001)

local blizzardBags = {}
local syncing = false
local useBlizzardBank = false

local KEYRING_CONTAINER = KEYRING_CONTAINER or -2


--[[ Inventory ]]--

local function IsInventoryFrame(frame)
	if frame == ContainerFrameCombinedBags then return true end
	local bag = frame:GetID()
	return bag == KEYRING_CONTAINER or (bag >= 0 and bag <= Data.numBags)
end

local function AnyBlizzardBagOpen()
	for i = 1, #blizzardBags do
		local frame = blizzardBags[i]
		if frame:IsShown() and IsInventoryFrame(frame) then
			return true
		end
	end
	return false
end

local function Sync()
	local open = AnyBlizzardBagOpen()
	if open ~= (Bags:IsShown("inventory") and true or false) then
		syncing = true
		if open then
			Bags:Show("inventory")
		else
			Bags:Hide("inventory")
		end
		syncing = false
	end
end

local function TakeOver(frame)
	frame:SetParent(hiddenParent)
	hooksecurefunc(frame, "Show", Sync)
	hooksecurefunc(frame, "Hide", Sync)
	hooksecurefunc(frame, "SetShown", Sync)
	blizzardBags[#blizzardBags + 1] = frame
end


--[[ Bank ]]--

local function CloseBank()
	if C_Bank and C_Bank.CloseBankFrame then
		C_Bank.CloseBankFrame()
	elseif CloseBankFrame then
		CloseBankFrame()
	end
end

function Bags:UseBlizzardBank()
	if not BankFrame or not Data.atBank then return end
	useBlizzardBank = true
	BankFrame:SetParent(UIParent)
	-- the game may have closed its (invisible) window while ours stayed open
	if not BankFrame:IsShown() then
		BankFrame:Show()
	end
	self:Hide("bank")
end

-- Back to our window after buying a bank slot; Blizzard's stays open, invisible, so the
-- visit goes on.
local function BackToOurBank()
	if not useBlizzardBank then return end
	useBlizzardBank = false
	BankFrame:SetParent(invisibleParent)
	if Data.atBank then
		Data:ScanAll(Data:GetBankBags())
		Bags:Show("bank")
	end
end

local function OnBankShown()
	if not useBlizzardBank then
		Bags:Show("bank")
	end
end

local function OnBankHidden()
	if useBlizzardBank then
		useBlizzardBank = false
		BankFrame:SetParent(invisibleParent)
		-- Closing Blizzard's window ends the visit (BANK_CLOSED follows). If the bank is
		-- still open a moment later, it was only the game's window manager: ours comes back.
		C_Timer.After(0.3, function()
			if Data.atBank and not useBlizzardBank then
				Bags:Show("bank")
			end
		end)
		return
	end
	-- Blizzard's (invisible) bank window can be closed by the game's window manager, for
	-- example when another window opens on the same side, while the bank is still open.
	-- Ours stays then; BANK_CLOSED closes it when the visit really ends.
	if not Data.atBank then
		Bags:Hide("bank")
	end
end


--[[ Our windows closing ]]--

function Bags:OnFrameHidden(kind)
	if syncing then return end
	if kind == "inventory" then
		if AnyBlizzardBagOpen() then
			CloseAllBags()
		end
	elseif kind == "bank" and Data.atBank and not useBlizzardBank then
		CloseBank()
	end
end


--[[ Module ]]--

function Hooks:OnLogin()
	if not Bags.active then return end

	if ContainerFrameCombinedBags then
		TakeOver(ContainerFrameCombinedBags)
	end
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame then
			TakeOver(frame)
		end
	end

	if BankFrame then
		BankFrame:SetParent(invisibleParent)
		BankFrame:HookScript("OnShow", OnBankShown)
		BankFrame:HookScript("OnHide", OnBankHidden)
	end

	-- a bank slot was bought in Blizzard's window: back to ours, where the bag goes in
	for _, event in ipairs({"BANK_TABS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED"}) do
		pcall(ns.RegisterEvent, ns, event, function()
			if useBlizzardBank then C_Timer.After(0.3, BackToOurBank) end
		end)
	end

	Data:RegisterListener(function(event)
		if event == "BANK_OPENED" then
			OnBankShown()
		elseif event == "BANK_CLOSED" and not useBlizzardBank then
			Bags:Hide("bank")
		end
	end)

	-- Blizzard bags may already be flagged open (e.g. after a reload)
	Sync()
end
