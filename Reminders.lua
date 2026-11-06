--[[
	Reminders, out of combat only: icons above the middle of the screen for
	  - the class buff that is missing or about to end (Arcane Intellect, Power Word:
	    Fortitude, armors, aspects, auras, blessings, shields, weapon imbues, poisons);
	  - the pet: call, revive or feed it (hunter, with its happiness), or summon the
	    last demon (warlock); the hunter's pet happiness also on the pet frame.
	A click casts the spell (a normal secure button: one click, one cast). Shift+drag
	moves the icons. They hide when combat starts and come back after it.
--]]

local _, ns = ...
local L = ns.L

local Reminders = ns:NewModule("Reminders")

local SIZE, GAP = 36, 6
local EXPIRING = 60 -- seconds left that count as "ending"

local GetSpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon

-- Per class: groups of spells (rank 1 IDs) where any one present counts. "remember"
-- casts the one the player used last; otherwise the first one known, in this order.
local BUFFS = {
	MAGE = {{1459}, {6117, 7302, 168}},
	PRIEST = {{1243}, {588}},
	DRUID = {{1126}, {467}},
	WARLOCK = {{706, 687}},
	PALADIN = {
		{19740, 19742, 20217, 19977, 20911, 1038, remember = true}, -- blessings
		{465, 7294, 19746, 19876, 19888, 19891, 20218, remember = true}, -- auras
	},
	HUNTER = {{13165, 13163, 5118, 13159, 20043, 13161, remember = true}}, -- aspects
	SHAMAN = {{324}, {8017, 8024, 8033, 8232, remember = true, weapon = true}}, -- shield, imbues
	ROGUE = {{poison = true}},
}
local POISONS_SKILL, INSTANT_POISON = 2842, 6947
local CALL_PET, REVIVE_PET, FEED_PET = 883, 982, 6991
local DEMONS = {688, 697, 712, 691} -- imp, voidwalker, succubus, felhunter

local settings, store
local class = select(2, UnitClass("player"))
local holder
local buttons = {}
local wanted = {} -- icons to show now: {icon, spell name or nil, title, label}


--[[ Reading ]]--

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function Known(id)
	return IsPlayerSpell and IsPlayerSpell(id) or (IsSpellKnown and IsSpellKnown(id))
end

-- name -> expiration time of the player's buffs; nil when the game hides them.
local auras = {}
local function ReadAuras()
	wipe(auras)
	for index = 1, 40 do
		local name, expires
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local data = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
			if not data then break end
			name, expires = data.name, data.expirationTime
		else
			local _
			name, _, _, _, _, expires = UnitBuff("player", index)
			if not name then break end
		end
		if Secret(name) or Secret(expires) then return false end
		auras[name] = expires or 0
	end
	return true
end

local function Remaining(expires)
	if not expires or expires == 0 then return nil end
	return expires - GetTime()
end

local function Clock(seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

local function Add(icon, spell, title, label)
	wanted[#wanted + 1] = {icon = icon, spell = spell, title = title, label = label}
end

-- The spell of a group to cast: the one used last when remembered, else the first known.
local function Choice(group, key)
	local last = group.remember and store.last[key]
	local first
	for _, id in ipairs(group) do
		if Known(id) then
			local name = GetSpellName(id)
			if name == last then return id, name end
			first = first or id
		end
	end
	return first, first and GetSpellName(first)
end

local function CheckBuffs()
	for index, group in ipairs(BUFFS[class] or {}) do
		local key = class .. index
		if group.poison then
			if Known(POISONS_SKILL) and GetWeaponEnchantInfo then
				local hasMain, mainLeft, _, _, hasOff, offLeft = GetWeaponEnchantInfo()
				local offWeapon = GetInventoryItemLink("player", 17)
				offWeapon = offWeapon and select(6, C_Item.GetItemInfoInstant(offWeapon)) == 2
				local missing = (GetInventoryItemLink("player", 16) and not hasMain) or (offWeapon and not hasOff)
				local ending = (hasMain and mainLeft and mainLeft < EXPIRING * 1000)
					or (offWeapon and hasOff and offLeft and offLeft < EXPIRING * 1000)
				if missing or ending then
					Add(GetItemIcon(INSTANT_POISON), nil, L.REMIND_POISON, missing and L.REMIND_MISSING or L.REMIND_ENDING)
				end
			end
		else
			local id, name = Choice(group, key)
			if id then
				local left, present
				if group.weapon then
					local hasMain, mainLeft = GetWeaponEnchantInfo()
					present = hasMain and true or false
					left = hasMain and mainLeft and mainLeft / 1000
				else
					for _, other in ipairs(group) do
						local otherName = GetSpellName(other)
						if otherName and auras[otherName] then
							present = true
							left = Remaining(auras[otherName])
							break
						end
					end
				end
				if not present then
					Add(GetSpellTexture(id), name, name, L.REMIND_MISSING)
				elseif left and left < EXPIRING then
					Add(GetSpellTexture(id), name, name, Clock(math.max(left, 0)))
				end
			end
		end
	end
end

local HAPPINESS = {L.PET_UNHAPPY, L.PET_CONTENT, L.PET_HAPPY}

local function CheckPet()
	if IsMounted() or (UnitInVehicle and UnitInVehicle("player")) then return end
	local hasPet = UnitExists("pet")
	if class == "HUNTER" and Known(CALL_PET) then
		if hasPet and UnitIsDead("pet") then
			if Known(REVIVE_PET) then
				Add(GetSpellTexture(REVIVE_PET), GetSpellName(REVIVE_PET), GetSpellName(REVIVE_PET), L.REMIND_DEAD)
			end
		elseif not hasPet then
			Add(GetSpellTexture(CALL_PET), GetSpellName(CALL_PET), GetSpellName(CALL_PET), L.REMIND_NO_PET)
			if Known(REVIVE_PET) then
				Add(GetSpellTexture(REVIVE_PET), GetSpellName(REVIVE_PET), GetSpellName(REVIVE_PET), L.REMIND_IF_DEAD)
			end
		else
			local happiness = GetPetHappiness and GetPetHappiness()
			if happiness and happiness < 3 and Known(FEED_PET) then
				Add(GetSpellTexture(FEED_PET), GetSpellName(FEED_PET), GetSpellName(FEED_PET), HAPPINESS[happiness])
			end
		end
	elseif class == "WARLOCK" and not hasPet then
		local last = store.last.demon
		local pick
		for _, id in ipairs(DEMONS) do
			if Known(id) then
				pick = pick or id
				if GetSpellName(id) == last then pick = id break end
			end
		end
		if pick then
			Add(GetSpellTexture(pick), GetSpellName(pick), GetSpellName(pick), L.REMIND_NO_PET)
		end
	end
end


--[[ Icons ]]--

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetText(self.title or "", 1, 1, 1)
	if self.spell then
		GameTooltip:AddLine(L.REMIND_CLICK, nil, nil, nil, true)
	end
	GameTooltip:AddLine(L.REMIND_MOVE, 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function GetButton(index)
	local button = buttons[index]
	if button then return button end
	button = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:RegisterForDrag("LeftButton")
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.Label:SetPoint("TOP", button, "BOTTOM", 0, -2)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnDragStart", function()
		if IsShiftKeyDown() and not InCombatLockdown() then holder:StartMoving() end
	end)
	button:SetScript("OnDragStop", function()
		holder:StopMovingOrSizing()
		holder:SetUserPlaced(false)
		ns:SavePosition(ns.db.positions, "ForeverHubReminders", holder)
	end)
	buttons[index] = button
	return button
end

local function Show()
	local count = #wanted
	for index = 1, count do
		local entry, button = wanted[index], GetButton(index)
		button.Icon:SetTexture(entry.icon)
		button.Label:SetText(entry.label or "")
		button.title, button.spell = entry.title, entry.spell
		button:SetAttribute("type", entry.spell and "spell" or nil)
		button:SetAttribute("spell", entry.spell)
		button:ClearAllPoints()
		button:SetPoint("LEFT", holder, "LEFT", (index - 1) * (SIZE + GAP), 0)
		button:Show()
	end
	for index = count + 1, #buttons do
		buttons[index]:Hide()
	end
	holder:SetWidth(math.max(1, count * (SIZE + GAP) - GAP))
	holder:SetShown(count > 0)
end

local function Update()
	if InCombatLockdown() or not holder then return end
	for index = #wanted, 1, -1 do wanted[index] = nil end
	local hidden = UnitIsDeadOrGhost("player") or UnitOnTaxi("player")
	if not hidden then
		if settings.buffReminders and ReadAuras() then CheckBuffs() end
		if settings.petReminders then CheckPet() end
	end
	Show()
end

local function Later()
	ns:Defer("reminders", Update)
end


--[[ Hunter pet happiness on the pet frame ]]--

local face
local FACES = {{0.375, 0.5625}, {0.1875, 0.375}, {0, 0.1875}} -- unhappy, content, happy

local function UpdateFace()
	if not face then return end
	local happiness = settings.petReminders and UnitExists("pet") and GetPetHappiness and GetPetHappiness()
	if happiness and FACES[happiness] then
		face:SetTexCoord(FACES[happiness][1], FACES[happiness][2], 0, 0.359375)
		face:Show()
	else
		face:Hide()
	end
end

local function CreateFace()
	-- the pet frame may already have its own
	if class ~= "HUNTER" or not PetFrame or _G.PetFrameHappiness then return end
	face = PetFrame:CreateTexture(nil, "OVERLAY")
	face:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	face:SetSize(20, 20)
	face:SetPoint("LEFT", PetFrame, "RIGHT", -6, 0)
	UpdateFace()
end


--[[ Module ]]--

function Reminders:Refresh()
	Update()
	UpdateFace()
end

function Reminders:OnInitialize()
	settings = ns.db.qol
	local key = UnitName("player") .. "-" .. GetRealmName()
	ns.db.reminders = ns.db.reminders or {}
	ns.db.reminders[key] = ns.db.reminders[key] or {last = {}}
	store = ns.db.reminders[key]
	store.last = store.last or {}
end

function Reminders:OnLogin()
	holder = CreateFrame("Frame", "ForeverHubReminders", UIParent)
	holder:SetSize(SIZE, SIZE)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	if not ns:ApplyPosition(ns.db.positions, "ForeverHubReminders", holder) then
		holder:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
	end
	holder:Hide()
	CreateFace()

	-- remembers the blessing, aura, aspect, imbue and demon used last
	ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit ~= "player" or Secret(spellID) then return end
		local name = GetSpellName(spellID)
		if not name then return end
		for index, group in ipairs(BUFFS[class] or {}) do
			if group.remember then
				for _, id in ipairs(group) do
					if GetSpellName(id) == name then store.last[class .. index] = name end
				end
			end
		end
		for _, id in ipairs(DEMONS) do
			if GetSpellName(id) == name then store.last.demon = name end
		end
	end)

	ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() holder:Hide() end)
	ns:RegisterEvent("UNIT_AURA", function(_, unit) if unit == "player" then Later() end end)
	ns:RegisterEvent("UNIT_PET", function(_, unit)
		if unit == "player" then
			Later()
			UpdateFace()
		end
	end)
	pcall(ns.RegisterEvent, ns, "UNIT_HAPPINESS", function()
		Later()
		UpdateFace()
	end)
	for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "UNIT_INVENTORY_CHANGED",
		"PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_UNGHOST", "PLAYER_ALIVE", "UNIT_HEALTH"}) do
		pcall(ns.RegisterEvent, ns, event, function(_, unit)
			if unit == nil or unit == "player" or unit == "pet" then Later() end
		end)
	end
	-- timers of buffs and weapon imbues
	C_Timer.NewTicker(1, function()
		if not InCombatLockdown() and (holder:IsShown() or settings.buffReminders) then Update() end
	end)
	Update()
end
