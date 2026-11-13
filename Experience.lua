--[[
	Experience: a small movable line with level progress, XP per hour, the time
	left to the next level and rested XP. Rates count from login (right-click
	resets them). Hidden at the level cap.
--]]

local _, ns = ...
local L = ns.L

local Experience = ns:NewModule("Experience")

local frame, settings, ticker
local sessionStart, gained = 0, 0
local lastXP, lastMax

local function MaxLevel()
	if GetMaxLevelForPlayerExpansion then
		return GetMaxLevelForPlayerExpansion()
	end
	return MAX_PLAYER_LEVEL or 60
end

local function AtCap()
	return UnitLevel("player") >= MaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
end

local function FormatTime(seconds)
	seconds = math.floor(seconds)
	if seconds >= 3600 then
		return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return ("%d min"):format(math.max(1, math.floor(seconds / 60)))
end

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(value)) or tostring(math.floor(value))
end

local function Rate()
	local elapsed = GetTime() - sessionStart
	if gained <= 0 or elapsed < 30 then return end
	return gained / elapsed * 3600
end

local function Update()
	if not frame or not frame:IsShown() then return end
	local current, maximum = UnitXP("player"), UnitXPMax("player")
	if maximum <= 0 then return end

	local parts = {L.XP_LEVEL:format(UnitLevel("player"), current / maximum * 100)}
	local rate = Rate()
	if rate then
		parts[#parts + 1] = L.XP_RATE:format(Number(rate))
		parts[#parts + 1] = L.XP_TO_LEVEL:format(FormatTime((maximum - current) / rate * 3600))
	end
	local rested = GetXPExhaustion() or 0
	if rested > 0 then
		parts[#parts + 1] = L.XP_RESTED:format(rested / maximum * 100)
	end
	-- quests already done: what handing them in would give
	if ns.db.qol.readyXP and ns.Quests then
		local xp = ns.Quests:ReadyXP()
		if xp > 0 then
			parts[#parts + 1] = L.XP_READY:format(xp / maximum * 100)
		end
	end
	frame.Text:SetText(table.concat(parts, "  ·  "))
	frame:SetSize(frame.Text:GetStringWidth() + 16, 20)
end

local function OnXPUpdate()
	local current, maximum = UnitXP("player"), UnitXPMax("player")
	if lastXP then
		if current >= lastXP then
			gained = gained + (current - lastXP)
		else
			-- leveled up: the rest of the old level plus the new progress
			gained = gained + (lastMax - lastXP) + current
		end
	end
	lastXP, lastMax = current, maximum
	Update()
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(L.XP_TITLE)
	local current, maximum = UnitXP("player"), UnitXPMax("player")
	GameTooltip:AddDoubleLine(L.XP_CURRENT, ("%s / %s"):format(Number(current), Number(maximum)), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L.XP_MISSING, Number(maximum - current), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L.XP_SESSION, Number(gained), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L.XP_SESSION_TIME, FormatTime(GetTime() - sessionStart), 1, 1, 1, 1, 1, 1)
	if ns.db.qol.readyXP and ns.Quests then
		local xp, count = ns.Quests:ReadyXP()
		if count > 0 then
			local after = current + xp >= maximum and L.XP_READY_LEVEL or Number(maximum - current - xp)
			GameTooltip:AddDoubleLine(L.XP_READY_TIP:format(count), Number(xp), 1, 1, 1, 0.4, 1, 0.4)
			GameTooltip:AddDoubleLine(L.XP_READY_AFTER, after, 1, 1, 1, 1, 1, 1)
		end
	end
	GameTooltip:AddLine(L.XP_HINT, 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

local function Create()
	frame = CreateFrame("Frame", "ForeverHubExperience", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
	frame:SetBackdropColor(0, 0, 0, 0.45)

	frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Text:SetPoint("CENTER")

	if not ns:ApplyPosition(ns.db.positions, "ForeverHubExperience", frame) then
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 130)
	end

	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		ns:SavePosition(ns.db.positions, "ForeverHubExperience", self)
	end)
	frame:SetScript("OnMouseUp", function(self, mouse)
		if mouse == "RightButton" then
			Experience:ResetSession()
		end
	end)
	frame:SetScript("OnEnter", OnEnter)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	frame:SetScript("OnShow", function()
		Update()
		ticker = ticker or C_Timer.NewTicker(5, ns:Track("experience:tick", Update))
	end)
	frame:SetScript("OnHide", function()
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
	end)
	frame:Hide()
end

function Experience:UpdateText()
	Update()
end

function Experience:ResetSession()
	sessionStart, gained = GetTime(), 0
	lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
	Update()
end

function Experience:ResetPosition()
	ns.db.positions.ForeverHubExperience = nil
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 130)
	end
end

function Experience:Refresh()
	local show = settings.show and not AtCap()
	if show and not frame then
		Create()
	end
	if frame then
		frame:SetShown(show)
	end
end

function Experience:OnInitialize()
	settings = ns.db.xp
end

function Experience:OnLogin()
	self:ResetSession()
	ns:RegisterEvent("PLAYER_XP_UPDATE", OnXPUpdate)
	ns:RegisterEvent("UPDATE_EXHAUSTION", Update)
	ns:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(0, function() Experience:Refresh() end) end)
	self:Refresh()
end
