--[[
	Gold of the session and of the day: gained, spent, net and net gold per hour.
	The day is kept per character in the saved variables and restarts at midnight
	(local time). Shown in the bags' money tooltip and with /fh gold.
--]]

local _, ns = ...
local L = ns.L

local Gold = ns:NewModule("Gold")

local settings, record -- ns.db.gold, this character's day record
local session = {gained = 0, spent = 0}
local sessionStart, lastMoney

local function Today()
	local day = date("%Y-%m-%d")
	if record.day ~= day then
		record.day, record.gained, record.spent = day, 0, 0
	end
	return record
end

local function OnMoney()
	local money = GetMoney()
	local delta = money - lastMoney
	lastMoney = money
	if delta == 0 then return end

	local today = Today()
	if delta > 0 then
		session.gained = session.gained + delta
		today.gained = today.gained + delta
	else
		session.spent = session.spent - delta
		today.spent = today.spent - delta
	end
end

local function Money(value)
	return GetMoneyString(math.abs(value), true)
end

-- Net amount with a sign and color: green for profit, red for loss.
local function Net(value)
	if value > 0 then
		return "|cff40ff40+|r" .. Money(value)
	elseif value < 0 then
		return "|cffff4040-|r" .. Money(value)
	end
	return Money(0)
end

function Gold:GetSession()
	local elapsed = GetTime() - sessionStart
	local net = session.gained - session.spent
	local perHour = elapsed >= 60 and net / elapsed * 3600 or nil
	return session.gained, session.spent, net, perHour, elapsed
end

function Gold:AddTooltipLines(tooltip)
	if not settings.show then return end
	local gained, spent, net, perHour = self:GetSession()
	local today = Today()

	tooltip:AddLine(" ")
	tooltip:AddLine(L.GOLD_SESSION)
	tooltip:AddDoubleLine(L.GOLD_GAINED, Money(gained), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine(L.GOLD_SPENT, Money(spent), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine(L.GOLD_NET, Net(net), 1, 1, 1, 1, 1, 1)
	if perHour then
		tooltip:AddDoubleLine(L.GOLD_PER_HOUR, Net(math.floor(perHour)), 1, 1, 1, 1, 1, 1)
	end
	tooltip:AddLine(" ")
	tooltip:AddLine(L.GOLD_TODAY)
	tooltip:AddDoubleLine(L.GOLD_GAINED, Money(today.gained), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine(L.GOLD_SPENT, Money(today.spent), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine(L.GOLD_NET, Net(today.gained - today.spent), 1, 1, 1, 1, 1, 1)
end

local function PrintSummary()
	local gained, spent, net, perHour = Gold:GetSession()
	local today = Today()
	ns:Print(L.GOLD_SESSION)
	print(("  %s: %s  ·  %s: %s  ·  %s: %s"):format(L.GOLD_GAINED, Money(gained), L.GOLD_SPENT, Money(spent), L.GOLD_NET, Net(net)))
	if perHour then
		print(("  %s: %s"):format(L.GOLD_PER_HOUR, Net(math.floor(perHour))))
	end
	print(("  %s — %s: %s  ·  %s: %s  ·  %s: %s"):format(L.GOLD_TODAY, L.GOLD_GAINED, Money(today.gained),
		L.GOLD_SPENT, Money(today.spent), L.GOLD_NET, Net(today.gained - today.spent)))
end

function Gold:OnInitialize()
	settings = ns.db.gold
end

function Gold:OnLogin()
	local key = UnitName("player") .. "-" .. GetRealmName()
	settings.days[key] = settings.days[key] or {}
	record = settings.days[key]
	Today()

	sessionStart, lastMoney = GetTime(), GetMoney()
	ns:RegisterEvent("PLAYER_MONEY", OnMoney)
	ns:RegisterCommand("gold", PrintSummary, "Gold gained and spent this session and today")
end
