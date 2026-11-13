--[[
	Chat names: the class icon and the level of who speaks, before their name.
	  * the class comes from the GUID of each chat line (read once per player);
	  * the level from what the game already tells without asking: group, guild,
	    friends, /who results, target, mouseover and nameplates. Players seen nowhere
	    show only the icon until then.
	Cost per line: one plain find in ChatFrames' AddMessage wrapper, a table lookup
	and a prefix string built once per player (rebuilt only when it changes).
	Secret lines and the history restored after /reload are left untouched.
--]]

local _, ns = ...

local ChatNames = ns:NewModule("ChatNames")

local issecretvalue = issecretvalue or function() return false end
local settings

local classOf = {} -- "Name" -> class file ("MAGE")
local levelOf = {} -- "Name" -> level
local prefixOf = {} -- "Name" -> icon and level ready to insert; false = nothing known
local seenGUID = {} -- GUIDs whose class is already read
local iconOf = {} -- class file -> texture string

local function Short(name)
	return name:match("^[^%-]+") or name
end


--[[ Prefix ]]--

local function Icon(class)
	local icon = iconOf[class]
	if icon == nil then
		local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		icon = coords and ("|TInterface\\TargetingFrame\\UI-Classes-Circles:0:0:0:0:256:256:%d:%d:%d:%d|t"):format(
			coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256) or false
		iconOf[class] = icon
	end
	return icon or ""
end

local function Level(level)
	local color = GetQuestDifficultyColor(level)
	return ("|cff%02x%02x%02x%d|r"):format(color.r * 255, color.g * 255, color.b * 255, level)
end

local function Prefix(name)
	local prefix = prefixOf[name]
	if prefix == nil then
		local class, level = classOf[name], levelOf[name]
		prefix = false
		if class or level then
			prefix = (class and Icon(class) or "") .. (level and Level(level) or "") .. " "
		end
		prefixOf[name] = prefix
	end
	return prefix
end

-- Puts the prefix before the first player link (the one who speaks), outside the
-- color code that wraps it so the name keeps its class color.
function ChatNames.Decorate(text)
	if not settings.playerInfo then return text end
	local start = text:find("|Hplayer:", 1, true)
	if not start then return text end
	local name = text:match("^[^:|]+", start + 9)
	local prefix = name and Prefix(Short(name))
	if not prefix then return text end
	local before = text:sub(math.max(1, start - 40), start - 1)
	local color = before:match("|c%x%x%x%x%x%x%x%x$") or before:match("|cn[^:|]+:$")
	if color then
		start = start - #color
	end
	return text:sub(1, start - 1) .. prefix .. text:sub(start)
end


--[[ Learning ]]--

local function SetClass(name, class)
	if classOf[name] ~= class then
		classOf[name] = class
		prefixOf[name] = nil
	end
end

local function SetLevel(name, level)
	if type(level) == "number" and level > 0 and levelOf[name] ~= level then
		levelOf[name] = level
		prefixOf[name] = nil
	end
end

-- A chat line: its GUID gives the class (arg12, the 10th after the author).
local function LearnFromLine(_, _, _, author, ...)
	local guid = select(10, ...)
	if type(guid) ~= "string" or issecretvalue(guid) or seenGUID[guid] then return false end
	local _, class, _, _, _, name = GetPlayerInfoByGUID(guid)
	if class and not issecretvalue(class) then
		seenGUID[guid] = true
		name = (name and not issecretvalue(name) and name ~= "") and name
			or (type(author) == "string" and not issecretvalue(author) and author)
		if name then
			SetClass(Short(name), class)
		end
	end
	return false
end

local function LearnUnit(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	local name = UnitName(unit)
	local level = UnitLevel(unit)
	if not name or issecretvalue(name) or issecretvalue(level) then return end
	local _, class = UnitClass(unit)
	if class and not issecretvalue(class) then
		SetClass(name, class)
	end
	SetLevel(name, level)
end

local function LearnGroup()
	local prefix, count = "party", GetNumSubgroupMembers()
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers()
	end
	for i = 1, count do
		LearnUnit(prefix .. i)
	end
	LearnUnit("player")
end

-- The guild roster event comes often while the guild window is open: read it at
-- most every 20 seconds.
local GUILD_INTERVAL = 20
local guildReadAt, guildPending = 0, false

local function LearnGuild()
	guildPending = false
	guildReadAt = GetTime()
	if not IsInGuild() then return end
	for i = 1, GetNumGuildMembers() do
		local name, _, _, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
		if name then
			name = Short(name)
			SetLevel(name, level)
			if class then SetClass(name, class) end
		end
	end
end

local function GuildChanged()
	if guildPending then return end
	guildPending = true
	C_Timer.After(math.max(1, GUILD_INTERVAL - (GetTime() - guildReadAt)), LearnGuild)
end

local function LearnFriends()
	if not C_FriendList or not C_FriendList.GetNumFriends then return end
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.name and info.connected then
			SetLevel(Short(info.name), info.level)
		end
	end
end

local function LearnWho()
	if not C_FriendList or not C_FriendList.GetNumWhoResults then return end
	for i = 1, C_FriendList.GetNumWhoResults() do
		local info = C_FriendList.GetWhoInfo(i)
		local name = info and (info.fullName or info.name)
		if name then
			name = Short(name)
			SetLevel(name, info.level)
			if info.filename then SetClass(name, info.filename) end
		end
	end
end


--[[ Module ]]--

local EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

function ChatNames:OnInitialize()
	settings = ns.db.chat
end

function ChatNames:OnLogin()
	-- a filter runs before the line is written, so even the first line of someone gets its icon
	local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if addFilter then
		local tracked = ns:Track("chat:names", LearnFromLine) -- /fh mem
		for _, event in ipairs(EVENTS) do
			addFilter(event, tracked)
		end
	end

	ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() LearnUnit("target") end)
	ns:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() LearnUnit("mouseover") end)
	ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) LearnUnit(unit) end)
	ns:RegisterEvent("UNIT_LEVEL", function(_, unit) LearnUnit(unit) end)
	ns:RegisterEvent("GROUP_ROSTER_UPDATE", function() ns:Defer("chat-names-group", LearnGroup) end)
	ns:RegisterEvent("GUILD_ROSTER_UPDATE", GuildChanged)
	ns:RegisterEvent("FRIENDLIST_UPDATE", LearnFriends)
	ns:RegisterEvent("WHO_LIST_UPDATE", LearnWho)
	ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
		-- level colors are relative to yours: all prefixes are rebuilt
		SetLevel(UnitName("player"), level)
		wipe(prefixOf)
	end)

	LearnGroup()
	LearnFriends()
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	end
end
