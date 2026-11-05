--[[
	Mover - frames that can be moved, grouped by the Blizzard addon that creates them.
	"" holds frames that exist at login.

	Each entry: frameName = true, or a list of child paths that also act as drag handles.
	Paths may use dots to reach keyed children ("QuestMapFrame.DetailsFrame").
	Frames that do not exist in this client are skipped silently.
--]]

local _, ns = ...

ns.MoverFrames = {
	[""] = {
		AddonList = true,
		BankFrame = true,
		CharacterFrame = {"PaperDollFrame", "ReputationFrame", "TokenFrame"},
		["ReputationFrame.ReputationDetailFrame"] = true,
		ChatConfigFrame = true,
		ContainerFrameCombinedBags = {"ContainerFrameCombinedBags.TitleContainer"},
		DestinyFrame = true,
		DressUpFrame = true,
		FriendsFrame = true,
		RaidInfoFrame = true,
		GameMenuFrame = {"GameMenuFrame.Header"},
		GossipFrame = true,
		GuildInviteFrame = true,
		GuildRegistrarFrame = true,
		HelpFrame = true,
		ItemTextFrame = true,
		LootFrame = true,
		MailFrame = {"SendMailFrame"},
		OpenMailFrame = {"OpenMailSender"},
		MerchantFrame = true,
		ModelPreviewFrame = true,
		PetitionFrame = true,
		PetStableFrame = true,
		QuestFrame = true,
		QuestLogPopupDetailFrame = true,
		QuickKeybindFrame = true,
		ReadyCheckFrame = true,
		SettingsPanel = true,
		SplashFrame = true,
		TabardFrame = true,
		TaxiFrame = true,
		TradeFrame = true,
		TutorialFrame = true,
		WorldMapFrame = {"QuestMapFrame"},
	},

	Blizzard_AchievementUI = {
		AchievementFrame = {"AchievementFrame.Header"},
	},
	Blizzard_AuctionHouseUI = {
		AuctionHouseFrame = true,
	},
	Blizzard_Calendar = {
		CalendarFrame = true,
		CalendarCreateEventFrame = true,
		CalendarViewEventFrame = {"CalendarViewEventFrame.HeaderFrame"},
		CalendarViewHolidayFrame = true,
	},
	Blizzard_Channels = {
		ChannelFrame = true,
	},
	Blizzard_ClickBindingUI = {
		ClickBindingFrame = true,
	},
	Blizzard_Collections = {
		CollectionsJournal = {"CollectionsJournal.TitleContainer"},
	},
	Blizzard_Communities = {
		CommunitiesFrame = true,
		["CommunitiesFrame.GuildMemberDetailFrame"] = true,
		CommunitiesGuildLogFrame = true,
		CommunitiesGuildNewsFiltersFrame = true,
		CommunitiesGuildTextEditFrame = true,
		CommunitiesSettingsDialog = true,
	},
	Blizzard_DeathRecap = {
		DeathRecapFrame = true,
	},
	Blizzard_FlightMap = {
		FlightMapFrame = true,
	},
	Blizzard_GenericTraitUI = {
		GenericTraitFrame = true,
	},
	Blizzard_GroupFinder_VanillaStyle = {
		LFGParentFrame = {"LFGBrowseFrame", "LFGListingFrame", "LFGWhoListFrame"},
	},
	Blizzard_GuildBankUI = {
		GuildBankFrame = true,
	},
	Blizzard_GuildControlUI = {
		GuildControlUI = true,
	},
	Blizzard_InspectUI = {
		InspectFrame = {"InspectPaperDollFrame", "InspectGuildFrame", "InspectPVPFrame"},
	},
	Blizzard_ItemSocketingUI = {
		ItemSocketingFrame = true,
	},
	Blizzard_ItemUpgradeUI = {
		ItemUpgradeFrame = true,
	},
	Blizzard_MacroUI = {
		MacroFrame = true,
	},
	Blizzard_PlayerSpells = {
		PlayerSpellsFrame = {"PlayerSpellsFrame.TalentsFrame.ButtonsParent"},
		HeroTalentsSelectionDialog = true,
	},
	Blizzard_Professions = {
		ProfessionsFrame = true,
		InspectRecipeFrame = true,
	},
	Blizzard_PVPMatch = {
		PVPMatchResults = true,
	},
	Blizzard_PVPUI = {
		PVPMatchScoreboard = true,
	},
	Blizzard_TimeManager = {
		TimeManagerFrame = true,
	},
	Blizzard_TokenUI = {
		CurrencyTransferMenu = true,
	},
	Blizzard_TrainerUI = {
		ClassTrainerFrame = true,
	},
	Blizzard_Transmog = {
		TransmogFrame = true,
	},
}
