local Challenge = select(2, ...)
Challenge = LibStub("AceAddon-3.0"):NewAddon(Challenge, "LootAppraiser Challenge", "AceEvent-3.0", "AceConsole-3.0", "AceSerializer-3.0", "LibSink-2.0", "AceBNComm-1.0")

local LibStub = LibStub
local AceGUI = LibStub("AceGUI-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local LibCompress = LibStub:GetLibrary("LibCompress")
local LibCompressEncode = LibCompress:GetAddonEncodeTable("\000", "%z")

local LibParse = LibStub:GetLibrary("LibParse")
local LibWindow = LibStub("LibWindow-1.1")

local LA = LibStub("AceAddon-3.0"):GetAddon("LootAppraiser", true)

local GetAddOnMetadata = C_AddOns.GetAddOnMetadata
local xDebugMode = false

-- Lua APIs
local tostring, pairs, ipairs, table, tonumber, select, time, math, floor, date, print, type, string, fastrandom, sort, error, unpack = 
      tostring, pairs, ipairs, table, tonumber, select, time, math, floor, date, print, type, string, fastrandom, sort, error, unpack

-- wow APIs
local GetUnitName, CreateFrame, UIParent, UIErrorsFrame, GameFontNormalLarge, GameFontNormal, GameTooltip, UIDropDownMenu_AddButton, GetItemInfo, GetMapInfo, GetBestMapForUnit, GetRealmName, GetChatWindowInfo, UnitIsAFK, IsShiftKeyDown, UnitFactionGroup = 
      GetUnitName, CreateFrame, UIParent, UIErrorsFrame, GameFontNormalLarge, GameFontNormal, GameTooltip, UIDropDownMenu_AddButton, GetItemInfo, C_Map.GetMapInfo, C_Map.GetBestMapForUnit, GetRealmName, GetChatWindowInfo, UnitIsAFK, IsShiftKeyDown, UnitFactionGroup

-- BNet API
local BNGetFriendAccountInfo,           BNGetAccountInfoByID,           BNGetFriendGameAccountInfo,           BNGetGameAccountInfoByID,           BNGetFriendNumGameAccounts,           BNGetFriendIndex, BNGetNumFriends, BNGetInfo = 
      C_BattleNet.GetFriendAccountInfo, C_BattleNet.GetAccountInfoByID, C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetGameAccountInfoByID, C_BattleNet.GetFriendNumGameAccounts, BNGetFriendIndex, BNGetNumFriends, BNGetInfo

local _G = _G      
--local UIDROPDOWNMENU_INIT_MENU =
--      UIDROPDOWNMENU_INIT_MENU

Challenge.METADATA = {
	NAME = GetAddOnMetadata(..., "Title"), 
	VERSION = GetAddOnMetadata(..., "Version")
}

Challenge.TEAM_BUILDING = {
	["free"] = "free",
	["premade"] = "premade"
}

Challenge.RECONNECT_BEHAVIOR = {
	["automatic"] = "Automatic reconnect (no popups or questions)",
	["popup"] = "Shows a popup with the possibility to say 'no thx'"
}

-- internal/private constants
local p = {
	prefix = "LAC.v1.3_p2",	-- msg prefix for communication over bnet

	action = {
		accept 				= "accept",
		accept_confirmation	= "accept_confirmation", 
		cancel 				= "cancel",
		decline 			= "decline",
		invite 				= "invite",
		invite_confirmation = "invite_confirmation",
		ready 				= "ready",
		ready_confirmation	= "ready_confirmation",
		start 				= "start",
		start_confirmation	= "start_confirmation",
		update_liv 			= "update_liv",
		ranking 			= "ranking", 
		--rankingadd          = "rankingadd",
		reconnect           = "reconnect",
		request4invite      = "request4invite",
	},

	challengeUI = {
		width = 405,
		posChangeWidth = 16,
		posWidth = 40,
		nameWidth = 170,
		livWidth = 130,
	},

	mviUI = {
		width = 405,
	},

	itemDrops = 5,

	reconnect = {
		maxOffset = 15,
	},

	minimumLAversion = "1.6.10",
}

local host = {
	--challengeID = nil,		-- unique ID of the hosted challenge
	--payload = {},				-- challenge data
	--invitations = {},			-- invitations

	--acceptedInvitations = {},	-- accepted invitations
	--declinedInvitations = {},	-- declined invitations
	--readyCheck = false,			-- ready check send
	--readyCheckConfirmed = {},	-- ready check confirmed
	--start = false,
	--rows = {},				-- rows for CHALLENGE_UI
	--sendInvite = false,		-- send invite loop is running
}

local participant = {
	--invitations = {},			-- invitations
	--challengeID = nil,		-- unique ID of a running challenge
	--payload = {},				-- challenge data
	--frame = nil,
	--readyCheck = false,		-- ready check received
	--ranking = {},
	--start = false,
}


local reusableOptions = {
	["desc"] = { 
		type = "input", order = 30, multiline = 4, width = "full", name = "Description", --desc = "Description", 
		validate = function(info, value)
			--if string.len(value) == 0 then
			--	UIErrorsFrame:AddMessage("|cffff0000LootAppraiser Challenge:|r 'Description' is mandatory.")
			--	return false
			--end
			return true
		end,
	},

	["parameterGrp"] = { type = "group", order = 40, inline = true, name = "Parameter", 
		args = {
			duration = { type = "input", order = 5, width = "half", name = "Duration", desc = "Challenge duration in minutes",
				get = function(info) return Challenge.db.profile.challenge[info[#info]] or 60 end,
				validate = function(info, value)
					if tonumber(value) == nil then
						UIErrorsFrame:AddMessage("|cffff0000LootAppraiser Challenge:|r 'Duration' must be numeric.")
						return false
					end
					return true
				end,
			},
			durationMins = { type = "description", order = 6, fontSize = "medium", name = " min", width = "half", },
			tsmBlacklist = { type = "description", order = 7, fontSize = "medium", name = "      TSM Blacklist deactivated!", width = "double", },
			qualityFilter = { type = "select", order = 10, name = "Quality Filter", desc = "Items below the selected quality will not show in the loot collected list", values = LA.QUALITY_FILTER, },
			priceSource = { type = "select", order = 20, name = "Price Source", desc = "TSM predefined price sources for item value calculation.", width = "double", 
				values = function() return LA.TSM:GetAvailablePriceSources() end, 
			},						
		},
		plugins = {},
	},

	["alias"] = { type = "input", order = 90, width = "half", name = "Name/Alias", desc = "The name (alias) of the challenge host", 
		get = function() 
			if Challenge.db.profile.challenge.alias ~= nil and Challenge.db.profile.challenge.alias ~= "" then
				return Challenge.db.profile.challenge.alias
			else
				return GetUnitName("player", true)
			end
		end,
		validate = function(info, value)
			if string.len(value) < 3 or string.len(value) > 25 then
				UIErrorsFrame:AddMessage("|cffff0000LootAppraiser Challenge:|r 'Name/Alias' must be between 3 and 25 characters.")
				return false
			end
			return true
		end,
	},

	["cancelChallenge"] = { type = "execute", order = 110, width = "half", name = "Cancel", desc = "Cancel the current challenge.",
		func = function() Challenge:Host_SendCancel() end,
		disabled = function()
			-- cancel is enabled
			-- * when a challendID is registered
			if host.sendInvite then return true end
			if host.challengeID ~= nil then return false end
			return true
		end,
	},

	["inspiredBy"] = { type = "description", order = 200, fontSize = "small", name = "\n ", width = "full", }, 
	["banner"] = { type = "description", order = 210, width = "full", name = "",
		image = function()
			return "Interface\\AddOns\\LootAppraiser_Challenge\\Media\\banner_aexitus" , 480, 120
		end,
	},
}


local challengeOptions = { 
	type = "group", name = "LootAppraiser Challenge " .. Challenge.METADATA.VERSION, childGroups = "tab", inline = true,
	get = function(info) return Challenge.db.profile.challenge[info[#info]] or "" end,
	set = function(info, value) Challenge.db.profile.challenge[info[#info]] = value end,
	args = {
		invitationsGrp = { type = "group", order = 10, name = "Invitations", args = {
			noOpenInvitations = { type = "description", order = 10, fontSize = "medium", name = "No open invitations.", width = "double", },
		}, plugins = {}, },
		hostGrp = { type = "group", order = 50, name = "Host", desc ="Host a Challenge", childGroups = "tab",
			args = {
				openChallengeGrp = { type = "group", order = 10, name = "Open", desc = "A challenge open to all bnet friends.", 
					disabled = function() 
						if not Challenge.mode or Challenge.mode == "open" then return false end
						return true
					end,
					args = {
						desc = { type = "description", order = 10, fontSize = "medium", name = "Start a challenge open to all bnet friends.", width = "full", },

						description = reusableOptions["desc"],
						parameterGrp = reusableOptions["parameterGrp"],
						alias = reusableOptions["alias"],
						sendInvite = { type = "execute", order = 100, name = "(Re)Send Invite", desc = "(Re)Send an invitation to every bnet friend.",
							func = function() 
								-- validate
								local duration = Challenge.db.profile.challenge.duration
									LA:D("  duration=" .. tostring(Challenge.db.profile.challenge.duration))
								if not duration or duration == "" then
									LA:D("  duration=" .. tostring(Challenge.db.profile.challenge.duration))
									UIErrorsFrame:AddMessage("|cffff0000LootAppraiser Challenge:|r Duration is mandatory")
									return
								end

								-- send invite
								Challenge:Host_SendInvite("open") 
							end,
							disabled = function()
								-- invite is disabled
								-- * after start
								-- * during send invite
								if host.start then return true end
								if host.sendInvite then return true end
								return false
							end
						},
						cancelChallenge = reusableOptions["cancelChallenge"],

						inspiredBy = reusableOptions["inspiredBy"],
						banner = reusableOptions["banner"],
					},
				},
				privateChallengeGrp = { type = "group", order = 20, name = "Private ", desc = "A private challenge with manual invitation of bnet friends.", 
					disabled = function() 
						if not Challenge.mode or Challenge.mode == "private" then return false end
						return true
					end,
					args = {
						desc = { type = "description", order = 10, fontSize = "medium", name = "Start a private challenge with manual invitation of bnet friends (right click on bnet list).", width = "full", },					

						description = reusableOptions["desc"],
						parameterGrp = reusableOptions["parameterGrp"],
						alias = reusableOptions["alias"],
						sendInvite = { type = "execute", order = 100, name = "Private Challenge", desc = "Open a private challenge.",
							func = function() Challenge:Host_SendInvite("private") end,
							disabled = function()
								-- invite is disabled
								-- * after start
								-- * during send invite
								if host.start then return true end
								if host.sendInvite then return true end
								return false
							end
						},
						cancelChallenge = reusableOptions["cancelChallenge"],

						inspiredBy = reusableOptions["inspiredBy"],
						banner = reusableOptions["banner"],
					},
				},
				teamChallengeGrp = { type = "group", order = 30, name = "Team ", desc = "A challenge for teams of any size.", 
					disabled = function() 
						if not Challenge.mode or Challenge.mode == "team" then return false end
						return true
					end,
					args = {
						desc = { type = "description", order = 10, fontSize = "medium", name = "Start a team challenge (open to all bnet friends) for teams of any size.", width = "full", },					
						
						description = reusableOptions["desc"],
						parameterGrp = reusableOptions["parameterGrp"],

						teamBuildingOpt = { type = "select", order = 84, width = "half", name = "Team building", desc = "How the teams will be build?", values = Challenge.TEAM_BUILDING, 
							--get = function(info) return Challenge.db.profile.challenge[info[#info]] or "" end,
							--set = function(info, value) Challenge.db.profile.challenge[info[#info]] = value end,
						},
						team = { type = "input", order = 85, width = "normal", name = "Teamname", desc = "The team name.", 
							hidden = function()
								local teamBuildingOpt = Challenge.db.profile.challenge.teamBuildingOpt or "free"
								if teamBuildingOpt == "free" then
									return false
								end
								return true
							end,
							get = function() 
								if Challenge.db.profile.challenge.team ~= nil and Challenge.db.profile.challenge.team ~= "" then
									return Challenge.db.profile.challenge.team
								else
									return "Team " .. GetUnitName("player", true) -- generate a default teamname
								end
							end,
							validate = function(info, value)
								if string.len(value) < 3 or string.len(value) > 25 then
									UIErrorsFrame:AddMessage("|cffff0000LootAppraiser Challenge:|r 'Teamname' must between 3 and 25 characters.")
									return false
								end
								return true
							end,
						},
						premadeTeam = { type = "select", order = 85, width = "normal", name = "Premade Teams", desc = "A list of premade teams.", 
							values = function()
								return Challenge:getActivePremadeGroups()
							end,
							hidden = function()
								local teamBuildingOpt = Challenge.db.profile.challenge.teamBuildingOpt or "free"-- default is free
								if teamBuildingOpt == "premade" then
									return false
								end
								return true
							end,
						},
						alias = reusableOptions["alias"],
							blankLine = { type = "description", order = 99, fontSize = "medium", name = "", width = "full", },					

						sendInvite = { type = "execute", order = 100, name = "(Re)Send Invite", desc = "(Re)Send an invitation to every bnet friend.",
							func = function() 
								-- validate
								local teamBuildingOpt = Challenge.db.profile.challenge.teamBuildingOpt or "free" -- default is free
								if teamBuildingOpt == "premade" then
									LA:D("  premadeTeam=" .. tostring(Challenge.db.profile.challenge.premadeTeam))
									local premadeTeam = Challenge.db.profile.challenge.premadeTeam
									if not premadeTeam or premadeTeam == "" then
										UIErrorsFrame:AddMessage("|cffff0000LootAppraiser Challenge:|r Select a premade team from the list.")
										return
									end
								end

								-- send invite
								Challenge:Host_SendInvite("team") 
							end,
							validate = function(info, value)
								LA:D("  validate: value=" .. tostring(value))
							end,
							disabled = function()
								-- invite is disabled
								-- * after start
								-- * during send invite
								if host.start then return true end
								if host.sendInvite then return true end
								return false
							end,
						},
						cancelChallenge = reusableOptions["cancelChallenge"],

						inspiredBy = reusableOptions["inspiredBy"],
						banner = reusableOptions["banner"],
					},
				},
			},
			plugins = {},
		},
		configGrp = { type = "group", order = 100, name = "Options", childGroups = "tab", 
			args = {
				generalGrp = { type = "group", order = 10, name = "General",
					get = function(info) return Challenge.db.profile.challenge.general[info[#info]] end,
					set = function(info, value) Challenge.db.profile.challenge.general[info[#info]] = value end,				
					args = {
						request4InviteGrp = { type = "group", order = 10, name = "Request for invite |cffff0000(host only)|r ", inline = true,
							args = {
								description = { type = "description", order = 10, fontSize = "medium", name = "Allow 'request for invite' to join an already running challenge.", width = "full" },
								allowRequest4Invite = { type = "toggle", order = 20, name = "Allow 'request for invite'", width = "full" },	
							}, plugins = {}, 
						},
						mostValuableItemsTotalGrp = { type = "group", order = 20, name = "Most Valuable Items Overall |cffff0000(host only)|r", inline = true,
							args = {
								description = { type = "description", order = 10, fontSize = "medium", name = "Show the most valuable items of all participants in an additonal window.", width = "full" },
								enableMVItems = { type = "toggle", order = 20, name = "Enable most valuable items overall", width = "full" },	
								mvItemCount = { type = "range", order = 30, name = "Item count", min = 3, max = 10, step = 1, width = "normal", 
									disabled = function()
										return not (Challenge.db.profile.challenge.general.enableMVItems == true)
									end,
								},
							}, plugins = {}, 
						},
						reconnectGrp = { type = "group", order = 30, name = "Reconnect behavior ", inline = true,
							args = {
								description = { type = "description", order = 10, fontSize = "medium", name = "If you get a dc or have to reload, LootAppraiser Challenge will try to reconnect you to the running challenge in the here selected way...", width = "full" },
								reconnectBehavior = { type = "select", order = 20, name = "", width = "full", style = "radio",
									values = Challenge.RECONNECT_BEHAVIOR,
								},								
							}, plugins = {},
						},
						uiScalingGrp = { type = "group", order = 40, name = "UI Scaling ", inline = true,
							args = {
								description = { type = "description", order = 10, fontSize = "medium", name = "Put your mouse over the title of a LootAppraiser Challenge window, hold the ALT key and use your mouse wheel.", width = "full" },
							}, plugins = {},
						},
					}, plugins = {}, 
				},
				teamGrp = { type = "group", order = 20, name = "Team Challenge",
					args = {
						premadeTeamsGrp = { type = "group", order = 10, name = "Premade Teams |cffff0000(host only)|r ", inline = true,
							get = function(info) return Challenge.db.profile.challenge.config.premadeTeam[info[#info]] end,
							set = function(info, value) Challenge.db.profile.challenge.config.premadeTeam[info[#info]] = value end,	
							args = {
								description = { type = "description", order = 10, fontSize = "medium", name = "Create premade teams for team challenges. Participants can only join this teams and can't make own teams (if the option 'premade groups' is selected).", width = "full" },
								teamName = { type = "input", order = 20, name = "Teamname", width = "normal", 
									set = function(info, value) 
										Challenge:PremadeTeams_Create(value)
									end,
								},
								teams = { type = "group", order = 40, name = "", inline = true, 
									hidden = function()
										if not Challenge.premadeTeamsInit then
											Challenge.premadeTeamsInit = true

											LA:D("hidden called " .. tostring(time()))
											Challenge:PremadeTeams_PrepareTeamList() 
										end
										return false
									end,
									get = function(info) 
										--LA:D("get:")
										--LA:print_r(info[#info])
										local value = Challenge.db.profile.challenge.config.premadeTeam.teams[info[#info]]
										--LA:D("     value=" .. tostring(value))
										return Challenge.db.profile.challenge.config.premadeTeam.teams[info[#info]]
									end,
									set = function(info, value) Challenge.db.profile.challenge.config.premadeTeam.teams[info[#info]] = value end,	
									args = { 
										-- add dynamic content
									}, plugins = {}, 
								},
							}, plugins = {}, 
						},
					}, plugins = {}, 
				},
			}, plugins = {}, 
		},
		--debugGrp = { type = "group", order = 150, name = "Debug", hidden = function() return not Challenge:isDebugOutputEnabled() end, 
		--	args = {
		--		bnetTestGrp = { type = "group", order = 10, name = "BattleNet Test", inline = true,
		--			get = function(info) return Challenge.db.profile.challenge.bnetTest[info[#info]] end,
		--			set = function(info, value) Challenge.db.profile.challenge.bnetTest[info[#info]] = value end,
		--			args = {
		--				description = { type = "description", order = 10, fontSize = "medium", name = "BNet Message Test. Be careful because this test can disconnect you.", width = "full" },
		--				msgSize = { type = "range", order = 20, name = "Message size", desc = "Message size (x'100 byte)", min = 100, max = 6000, step = 100, width = "normal", },
		--				msgCount = { type = "range", order = 30, name = "Message count", desc = "Number of messages to send with the defined size.", min = 1, max = 50, step = 1, width = "normal", },
		--				test = { type = "execute", order = 40, name = "Test", desc = "Test",
		--					func = function() Challenge.bNetTest() end,
		--				},
		--					emptyLine1 = { type = "description", order = 50, name = " ", width = "full" },
		--			},
		--		},
		--	}, plugins = {}, 
		--},
	},
}


function Challenge:PremadeTeams_PrepareTeamList() 
	self:D("PremadeTeams_PrepareTeamList")

	local teams = Challenge.db.profile.challenge.config.premadeTeam.teams or {}

	local teamsSorted = {}
	for teamName, active in pairs(teams) do
		table.insert(teamsSorted, teamName)
	end

	sort(teamsSorted)

	for _, teamName in pairs(teamsSorted) do
		--self:D("k=%s, team=%s", tostring(k), tostring(team))

		self:PremadeTeams_Create(teamName, teams[teamName])
	end

	self:updateUI()
end


function Challenge:PremadeTeams_Create(teamName, value)
	self:D("PremadeTeams_Create: %s=%s", tostring(teamName), tostring(value))

	-- always remove the teamName from input field
	Challenge.db.profile.challenge.config.premadeTeam.teamName = nil

	-- update ui
	AceConfigRegistry:NotifyChange("LootAppraiser Challenge")

	if not teamName or teamName == "" then return end

	-- only add if not already added
	local args = challengeOptions.args.configGrp.args.teamGrp.args.premadeTeamsGrp.args.teams.args
	if not args[teamName] then
		local teamCount = LA:tablelength(args)

		--self:D("  count=" .. tostring(teamCount))

		-- add new team to grp
		local teamDesc = { type = "toggle", order = (10*teamCount), fontSize = "medium", name = teamName, width = "double" }
		local teamDelete = { type = "execute", order = (10*teamCount)+1, name = "", desc = "Remove this premade team from the list.", width = "half", imageWidth = 10, imageHeight = 10,
			image = function () return "Interface\\BUTTONS\\UI-GroupLoot-Pass-Up" end,
			func = function() 
				--self:DeleteParticipant(toonID, host.acceptedInvitations)
				--self:D(" delete pressed...")

				args[teamName] = nil
				args[teamName .. "Del"] = nil

				Challenge.db.profile.challenge.config.premadeTeam.teams[teamName] = nil
			end,
		}

		args[teamName] = teamDesc
		args[teamName .. "Del"] = teamDelete
		if value ~= nil then
			Challenge.db.profile.challenge.config.premadeTeam.teams[teamName] = value
		else
			Challenge.db.profile.challenge.config.premadeTeam.teams[teamName] = true
			
			-- force recreate of team list (sorting)
			Challenge.premadeTeamsInit = false
			challengeOptions.args.configGrp.args.teamGrp.args.premadeTeamsGrp.args.teams.args = {}

			self:updateUI()
		end
	else
		self:D("  not added")
	end
end


function Challenge:getActivePremadeGroups()
	local teams = Challenge.db.profile.challenge.config.premadeTeam.teams or {}
	--LA:D("teams:")
	--LA:print_r(teams)

	local sortedTeams = {}
	for teamName, active in pairs(teams) do
		if active then
			table.insert(sortedTeams, teamName)
		end
	end
	sort(sortedTeams)

	--LA:D("sortedTeams:")
	--LA:print_r(sortedTeams)

	local activeTeams = {}
	for _, teamName in pairs(sortedTeams) do
		activeTeams[teamName] = teamName
	end 
	
	--LA:D("activeTeams:")
	--LA:print_r(activeTeams)

	return activeTeams
end

--[[-------------------------------------------------------------------------------------
-- AceAddon-3.0 standard methods
---------------------------------------------------------------------------------------]]
function Challenge:OnInitialize()
	self:D("OnInitialize()")

	-- loot appraiser version check (e.g. 2016.v1.6.3)
	local laMajor, laMinor, laMicro = string.match(LA.METADATA.VERSION, "^%d+.v(%d+)%p(%d+)%p(%d+)$")
	local preparedLAVersion = laMajor*10000 + laMinor*100 + laMicro

	local major, minor, micro = string.match(p.minimumLAversion, "^(%d+)%p(%d+)%p(%d+)$")
	local preparedMinVersion = major*10000 + minor*100 + micro

	self:D("  la:" .. tostring(preparedLAVersion) .. " vs. min:" .. tostring(preparedMinVersion))

	if preparedMinVersion > preparedLAVersion then
		-- prepare infobox
		local VERSIONCHECKUI = AceGUI:Create("Window")
		VERSIONCHECKUI:Hide()
		VERSIONCHECKUI:SetLayout("Flow")
		VERSIONCHECKUI:SetTitle("LootAppraiser Challenge: version check")
		VERSIONCHECKUI:SetPoint("CENTER")
		VERSIONCHECKUI:SetWidth(350)
		VERSIONCHECKUI:SetHeight(110)
		VERSIONCHECKUI:EnableResize(false)
		VERSIONCHECKUI:SetCallback("OnClose",
			function(widget) 
				AceGUI:Release(widget)
				VERSIONCHECKUI = nil
			end
		)

		-- challenge text
		local text = AceGUI:Create("LALabel")
		text:SetText("Your version of LootAppraiser is too old for LootAppraiser Challenge. Go to Curse and download the latest version of LootAppraiser.\n\nCurrent LootAppraiser version: " .. LA.METADATA.VERSION .. "")
		text:SetFont(GameFontNormal:GetFont())
		text:SetWidth(340)
		VERSIONCHECKUI:AddChild(text)

		VERSIONCHECKUI:Show()

		-- disable addon
		self:SetEnabledState(false)
		return
	end

	-- init db
	self:initDB()
end


--local bnetCheckTotal = 0
function Challenge:OnEnable()
	self:Print("ENABLED.")

	-- register options table...
	AceConfigRegistry:RegisterOptionsTable("LootAppraiser Challenge", challengeOptions --[[, "/lax"]])
	self.configFrame = AceConfigDialog:AddToBlizOptions("LootAppraiser Challenge", "Challenge", "LootAppraiser")

	AceConfigDialog:SetDefaultSize("LootAppraiser Challenge", 600, 590)

	-- ...and add slash command for the options table
	self:RegisterChatCommand("lac", "chatCmdChallengeUI")
	--self:RegisterChatCommand("lax", "ChatCommand")

	-- TODO remove
	self:RegisterChatCommand("lad", Challenge.addParticipant)
	self:RegisterChatCommand("lar", Challenge.addRndValue)
	--[[
	self:RegisterChatCommand("lat", Challenge.bNetTest)
	]]
	self:RegisterChatCommand("lactest", 
		function()
			self:D("money to string:")
			self:D("    " .. tostring(Challenge.FormatTextMoney(12345) ))
			self:D("    " .. tostring(Challenge.FormatTextMoney(12300) ))
			self:D("    " .. tostring(Challenge.FormatTextMoney(10000) ))
			self:D("    " .. tostring(Challenge.FormatTextMoney(0) ))
			self:D("    " .. tostring(Challenge.FormatTextMoney(10000) ))
			self:D("    " .. tostring(Challenge.FormatTextMoney(100000) ))
			self:D("    " .. tostring(Challenge.FormatTextMoney(1000000) ))
			self:D("    " .. tostring(Challenge.FormatTextMoney(10000000) ))

			self:D("is soulbound:")
			self:D("     " .. tostring(Challenge.IsSoulbound(2996))) -- Leinenstoffballen
			self:D("     " .. tostring(Challenge.IsSoulbound(9470))) -- Maske des schlechten Mojo (BOP)
			self:D("     " .. tostring(Challenge.IsSoulbound(8623))) -- Leinenstoffballen
			--Challenge.IsSoulbound(itemID)
		end
	)

	-- ...bnet addon msg
	self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
	--self:RegisterComm(p.prefix, "OnBnChatMsgAddon")

	-- register this as module for LootAppraiser
	self.module = {
		name = Challenge.METADATA.NAME,
		icon = {
			tooltip = {
				"|cffffffff" .. Challenge.METADATA.NAME .. " " .. Challenge.METADATA.VERSION .. "|r",
				"|cFFFFFFCCShift Right-Click|r to open the challenge options window",
				"|cFFFFFFCCShift Left-Click|r to open the challenge window",
			},
			action = {
				openChallengeConfig = {
					button = "RightButton",
					modifier = "Shift",
					callback = Challenge.Callback_OpenChallengeConfig,
				},
				openChallengeWindow = {
					button = "LeftButton",
					modifier = "Shift",
					callback = Challenge.Callback_OpenChallengeWindow,
				},
			},
		},
		callback = {
			itemDrop = Challenge.Callback_ItemDrop,
			settingsChangeAllowed = Challenge.Callback_SettingsChangeAllowed,
		},
	}
	LA:RegisterModule(self.module)
end


function Challenge.OnAddonLoaded() 
	Challenge:RegisterComm(p.prefix, "OnBnChatMsgAddon")
end


function Challenge:OnDisable()
	-- nothing to do
end


function Challenge.Callback_OpenChallengeConfig()
	local self = Challenge

	self:D("Callback_OpenChallengeConfig")
    Settings.OpenToCategory("LootAppraiser")
end


function Challenge.Callback_OpenChallengeWindow()
	local self = Challenge

	self:D("Callback_OpenChallengeWindow")

	self:chatCmdChallengeUI()
end

local testItems = {45553,24257,12611,15079,32403,82972,12614,29506,32398,47582,75100,85827,82974,32420,43871,85830,5770,75077,82971,32393,20478,22756,12632,14106,47596,85788,18511,29498,47583,56548,43495,22191,44742,82970,44930,45558,32390,7928,15066,25687,7959,32395,16982,82437,82438,47581,19043,17014,16979,45554,18506,19692,19050,15802,85849,20539,43592,47598,20551,29497,43591,85825,30042,15085,42103,19690,43593,85829,47573,42113,14146,42111,25682,19057,43587,86313,15047,23511,49895,42101,85840,23763,32400,43590,23512,82439,98612,32402,87566,45567,43502,49893,86314,49897,47600,32396,86311,15051,10021,47587,47597,42100,3853,12636,47595,43481,29512,22758,12624,30044,98608,85822,69945,23747,47579,49890,19694,85823,10588,19051,43588,41610,16980,43586,17721,45562,16984,7935,87561,49899,23509,32389,25680,25695,32401,54506,47601,15058,25681,41985,25697,85850,45566,54503,71980,20550,30034,23510,54504,25685,86312,12794,15052,21278,32584,98611,32391,15050,98603,49892,85787}
function Challenge.addParticipant()
	local size = #testItems
	if host.rows then
		local value = math.random(1, 1000)
		local counter = LA:tablelength(host.rows)

		local grp = {}
		grp["liv"] = value
		grp["name"] = "Dummy " .. tostring(counter)
		grp["realm"] = "RealmName"
		grp["afk"] = false
		local mostValueableItems = {
			{["id"] = testItems[fastrandom(1, size)], ["gv"] = fastrandom(1000, 10000)},
			{["id"] = testItems[fastrandom(1, size)], ["gv"] = fastrandom(1000, 10000)},
			{["id"] = testItems[fastrandom(1, size)], ["gv"] = fastrandom(1000, 10000)},
			{["id"] = testItems[fastrandom(1, size)], ["gv"] = fastrandom(1000, 10000)},
			{["id"] = testItems[fastrandom(1, size)], ["gv"] = fastrandom(1000, 10000)}
		}
		sort(mostValueableItems, 
			function(a, b) 
				return a.gv > b.gv
			end
		)
		grp["mostValueableItems"] = mostValueableItems

		local toonID = tostring(time())
		host.rows[toonID] = grp

		local team = "Team "
		if counter%2 == 0 then
			team = team .. "even"
		else
			team = team .. "odd"
		end

		local teamMembers = host.teamNames[team] or {}
		table.insert(teamMembers, toonID)

		host.teamNames[team] = teamMembers
	end
end


function Challenge.addRndValue()
	if host.rows then
		for k, grp in pairs(host.rows) do
			local value = math.random(500, 1500)

			grp["liv"] = grp["liv"] + value
		end
	end
end
--[[
]]

--[[-------------------------------------------------------------------------------------
-- callback for loot appraiser - settings change allowed
---------------------------------------------------------------------------------------]]
function Challenge.Callback_SettingsChangeAllowed(name)
	Challenge:D("Challenge.Callback_SettingsChangeAllowed: name=" .. tostring(name))

	participant.challenge = participant.challenge or {}

	-- no challenge is running -> return true
	if not host.start and not participant.challenge.start then return true end

	-- challenge is running -> check for locked settings
	Challenge.lockedLASettings = Challenge.lockedLASettings or { ["qualityFilter"] = true, ["source"] = true, ["tsmGroupEnabled"] = true }

	return not Challenge.lockedLASettings[name]
end


--[[-------------------------------------------------------------------------------------
-- callback for loot appraiser - noteworthy item
---------------------------------------------------------------------------------------]]
function Challenge.Callback_ItemDrop(itemID, value, itemData)
	Challenge:D("Challenge.Callback_ItemDrop: itemID=%s, value=%s", tostring(itemID), tostring(value))

	participant.challenge = participant.challenge or {}

	if not host.start and not participant.challenge.start then return end

	-- filter soulbound items
	--local itemLink = select(2, GetItemInfo(itemID))
	if Challenge.IsSoulbound(itemID) then
		Challenge:D("  ignore soulbound item: " .. tostring(itemID))
		return
	end

	local mapAreas, --[[lastItems,]] mostValueableItems
	if host.start then
		local grp = host.rows[0]

		-- map area
		grp.mapAreas = grp.mapAreas or {}
		mapAreas = grp.mapAreas

		-- most valued items
		grp.mostValueableItems = grp.mostValueableItems or {}
		mostValueableItems = grp.mostValueableItems
	else
		participant.challenge = participant.challenge or {}

		-- map area
		participant.challenge.mapAreas = participant.challenge.mapAreas or {}
		mapAreas = participant.challenge.mapAreas

		-- most valued items
		participant.challenge.mostValueableItems = participant.challenge.mostValueableItems or {}
		mostValueableItems = participant.challenge.mostValueableItems
	end

	-- record the current mapArea as loot location
	local mapAreaID = GetBestMapForUnit("player") -- current map
	
	local counter = mapAreas[tostring(mapAreaID)] or 0
	counter = counter + 1

	mapAreas[tostring(mapAreaID)] = counter

	-- prepare table
	-- callback value is in copper, we only need the gold portion
	local goldValue = floor(value/10000)
	local payload = {["id"] = itemID, ["gv"] = goldValue}

	-- prepare most valued items
	table.insert(mostValueableItems, payload)

	sort(mostValueableItems, 
		function(a, b) 
			return a.gv > b.gv
		end
	)

	if #mostValueableItems > p.itemDrops then
		table.remove(mostValueableItems, #mostValueableItems) -- remove last
	end
end


--[[-------------------------------------------------------------------------------------
-- chat cmd /lac : open challenge ui
---------------------------------------------------------------------------------------]]
function Challenge:chatCmdChallengeUI()
	self:D("Challenge:chatCmdChallengeUI")
	participant.challenge = participant.challenge or {}

	-- no challenge is running -> no challenge ui
	if not host.start and not participant.challenge.start then return end

	if self.CHALLENGE_UI then
		self.CHALLENGE_UI:Show()
	else
		self:prepareChallengeUI()
	end

	if host.start and self.MVI_UI and Challenge.db.profile.challenge.general.enableMVItems == true then
		self.MVI_UI:Show()
	end

	self:refreshChallengeUI()
end


function Challenge.OnBnChatMsgAddon(event, prefix, message, egal, senderToonID)
	if prefix ~= p.prefix then return end -- msg is not for loot appraiser -> skip

	local self = Challenge

	senderToonID = tonumber(senderToonID) -- why is senderToonID a string?!?

	--Challenge:D("  msg length: " .. tostring(#message))

	local tokens = Challenge.split(message, "\001")
	local v = {}
	for i=1, #tokens do
		local temp = LibParse:JSONDecode(tokens[i])
		table.insert(v, temp)
	end

	local success, challengeID, action, payload = true, unpack(v)
	if success then
		if action == p.action.invite then
			self:Participant_RecievedInvitation(challengeID, payload, senderToonID)

		elseif action == p.action.invite_confirmation then
			self:Host_RecievedInviteConfirmation(challengeID, payload, senderToonID)

		elseif action == p.action.accept then
			self:Host_RecievedAccept(challengeID, payload, senderToonID)

		elseif action == p.action.accept_confirmation then
			self:Participant_RecievedAcceptConfirmation(challengeID, payload, senderToonID)

		elseif action == p.action.start then
			self:Participant_RecievedStart(challengeID, payload, senderToonID)

		elseif action == p.action.start_confirmation then
			self:Host_RecievedStartConfirmation(challengeID, payload, senderToonID)

		elseif action == p.action.cancel then
			self:Participant_RecievedCancel(challengeID, payload, senderToonID)

		elseif action == p.action.decline then
			self:Host_RecievedDecline(challengeID, payload, senderToonID)

		elseif action == p.action.ready then
			self:Participant_RecievedReadyCheck(challengeID, payload, senderToonID)

		elseif action == p.action.ready_confirmation then
			self:Host_RecievedReadyCheckConfirmation(challengeID, payload, senderToonID)

		elseif action == p.action.update_liv then
			self:Host_RecievedUpdateLiv(challengeID, payload, senderToonID)

		--elseif action == "test" then
		--	self:Host_RecievedTest(challengeID, payload)
	
		elseif action == p.action.ranking then
			self:Participant_RecieveRanking(challengeID, payload, senderToonID)

		--elseif action == p.action.rankingadd then
		--	self:Participant_RecieveRankingAdditions(challengeID, payload, senderToonID)
	
		elseif action == p.action.reconnect then
			self:Participant_RecieveReconnect(challengeID, payload, senderToonID)
	
		elseif action == p.action.request4invite then
			self:Host_ReceiveRequest4Invite(challengeID, payload, senderToonID)

		else
			self:D("    invalid action '%s' for challengeID %s" ,tostring(action), tostring(challengeID))
		end
	else
		self:D("    invalid message: %s", tostring(challengeID))
	end
end


--[[
function Challenge.bNetTest()
	-- prepare bNet message
	local msgSize = Challenge.db.profile.challenge.bnetTest.msgSize or 100
	local msgCount = Challenge.db.profile.challenge.bnetTest.msgCount or 1

	local battleTag = "sanpan#1545"
	local toonName = "Encut"
	local toonID = Challenge:getToonId(battleTag, toonName)

	local text = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"

	local payload = ""
	for count = 1, msgSize/100, 1 do
		payload = payload .. text
	end

	for count = 1, msgCount, 1 do

		--table.insert(payload, "vv" .. tostring(count))
		--payload["key" .. tostring(count)] = "value" .. tostring(count)
		--payload[1] = payload[1] .. text
		--payload = payload .. text

		print("### round " .. tostring(count) .. " with " .. tostring(#payload) .. " bytes ###")

		--local serData = Challenge:Serialize(count, payload)
		--Challenge:SendCommMessage(p.prefix, serData, toonID)

		Challenge:sendBnetMsg(toonID, "12345", "test", payload)
	end

	Challenge.totalMsgLength = 0
end


local msgCountRecieved = 0
function Challenge:Host_RecievedTest(challengeID, payload)
	Challenge:D("Host_RecievedTest: challengeID=%s", challengeID)

	msgCountRecieved = msgCountRecieved + 1

	self:D("- " .. tostring(msgCountRecieved) .. ": " .. string.len(payload))
end
]]


--[[-------------------------------------------------------------------------------------
-- send an invitation to every bnet friend
--
-- host -> participant(s)
---------------------------------------------------------------------------------------]]
function Challenge:Host_SendInvite(mode)
	self:D("Challenge:Host_SendInvite")

	if host.sendInvite then return end -- prevent double click

	self.mode = mode -- set mode and lock other modes with this

	host.sendInvite = true

	-- save host battleTag
	host.toonName = GetUnitName("player", true)

	-- init tables (if necessary)
	host.invitations = host.invitations or {}
	host.acceptedInvitations = host.acceptedInvitations or {}
	host.declinedInvitations = host.declinedInvitations or {}
	host.readyCheckConfirmed = host.readyCheckConfirmed or {}
	host.teamNames = host.teamNames or {}

	-- create new challendeID if necessary
	host.challengeID = host.challengeID or "LAC:" .. tostring(time()) .. ":" .. select(2, BNGetInfo())

	-- prepare payload 
	local payload = {
		alias = self.db.profile.challenge.alias or host.toonName,
		desc = self.db.profile.challenge.description or "-no description-",
		duration = self.db.profile.challenge.duration,
		qf = self.db.profile.challenge.qualityFilter,
		ps = self.db.profile.challenge.priceSource,
		m = mode,

		version = self.METADATA.VERSION
	}

	-- if mode = team add the host team to the list
	if self.mode == "team" then
		local teamBuildingOpt = self.db.profile.challenge.teamBuildingOpt or "free"

		-- premade
		if teamBuildingOpt == "premade" then
			local premadeTeam = self.db.profile.challenge.premadeTeam
			if not host.teamNames[premadeTeam] then
				host.teamNames[premadeTeam] = {0} -- toonID is always the host
			end

			payload.teams = Challenge:getActivePremadeGroups()
		-- free
		else
			local teamName = self.db.profile.challenge.team or ("Team " .. host.toonName)
			if not host.teamNames[teamName] then
				host.teamNames[teamName] = {0} -- toonID is always the host
			end
		end
	else
		host.teamNames = {}
	end

	host.payload = payload -- save payload

	if self.mode ~= "private" then -- skip invite for mode = private
		for friendIndex = 1, BNGetNumFriends() do
			--local _, _, battleTag, _, _, _, _, isOnline = BNGetFriendInfo(friendIndex)
			local accountInfo = BNGetFriendAccountInfo(friendIndex)
			if accountInfo then
				local battleTag = accountInfo.battleTag -- TODO
				local isOnline = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline -- TODO

				if isOnline then
					local inviteSend = false
					for toonIndex = 1, BNGetFriendNumGameAccounts(friendIndex) do
						--local _, toonName, client, _, _, _, _, _, _, _, _, _, _, _, _, toonID = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
						local gameAccountInfo = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
						if gameAccountInfo then
							local client = gameAccountInfo.clientProgram -- TODO
							local toonName = gameAccountInfo.characterName -- TODO
							local toonID = gameAccountInfo.gameAccountID -- TODO
							if client == "WoW" then
								self:D("  invite send to battleTag=%s, toonID=%s (toonName=%s)", battleTag, toonID, toonName)
								self:sendBnetMsg(toonID, host.challengeID, p.action.invite, payload) -- send invite
							end
						end
					end
				end
			end
		end
	end
	
	host.sendInvite = false

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- handle action 'request4invite'
-- * sends an invite back to the requester
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Host_ReceiveRequest4Invite(challengeID, payload, senderToonID)
	self:D("Challenge:Host_ReceiveRequest4Invite")

	if not host.challengeID then return end -- no running challenge

	if self.db.profile.challenge.general.allowRequest4Invite ~= true then return end -- request for invite is not enabled

	if host.mode == "private" then return end -- private challenge is always host triggered

	--self:D("  invite send to battleTag=%s, toonID=%s (toonName=%s)", battleTag, toonID, toonName)
	self:sendBnetMsg(senderToonID, host.challengeID, p.action.invite, host.payload) -- send invite
end


--[[-------------------------------------------------------------------------------------
-- handle action 'invite'
-- * decline if we host our own challenge
-- * if we have already informations about this challenge
--   -> do nothing
-- * if we have a entry from the same battleTag with a different challengeID 
--   -> remove old invitation
-- * add invitations to list
-- * pronounce the new invitation
--
-- host -> participant
---------------------------------------------------------------------------------------]]
function Challenge:Participant_RecievedInvitation(challengeID, payload, senderToonID)
	self:D("Challenge:Participant_RecievedInvitation")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	-- we host our own challenge -> decline this invitation
	if host.challengeID then
		self:D("  we host our own challenge -> decline invitation from %s", (payload["alias"] or "unknown"))

		payload = {
			alias = self.db.profile.challenge.alias or GetUnitName("player", true)
		}

		self:D("  decline send to %s", tostring(senderToonID))
		self:sendBnetMsg(senderToonID, challengeID, p.action.decline, payload)
		return
	end

	-- init tables (if needed)
	participant.invitations = participant.invitations or {}

	-- entry for this invitation already exists?
	if participant.invitations[challengeID] ~= nil then
		self:D("  challenge invitation already registered")
		-- TODO 20160427 overwrites already accepted invitations and messed up the  challenge data
		--participant.invitations[challengeID] = payload 

		-- update ui
		self:updateUI()
		return
	end

	-- entry from the same battleTag with different challengeID already exists?
	participant.challenge = participant.challenge or {}

	for savedChallengeID, savedPayload in pairs(participant.invitations) do
		if savedPayload["toonID"] == senderToonID then
			self:D("  remove existing invitation with challengeID %s from same toonID %s" , savedChallengeID, tostring(senderToonID))
			participant.invitations[savedChallengeID] = nil

			if participant.challenge.challengeID == savedChallengeID then
				self:D("  reset running challengeID %s", savedChallengeID)
				participant.challenge = {}
			end
		end
	end

	-- we are already in a running challenge
	-- TODO: flag needed

	-- confirm invitation
	payload["toonID"] = senderToonID -- save for later use

	-- add new invitation
	participant.invitations[challengeID] = payload

	-- alias should never be empty
	local alias = self.db.profile.challenge.alias or GetUnitName("player", true)
	if alias == "" then
		alias = GetUnitName("player", true) -- force unit name if saved alias is empty
	end

	local confirmationPayload = {
		alias = alias,
		version = self.METADATA.VERSION
	}

	self:sendBnetMsg(senderToonID, challengeID, p.action.invite_confirmation, confirmationPayload)

	-- pronounce new invitation
	self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r new invitation from |cff00ff00" .. payload["alias"] .. "|r received.")

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- receive the invite confirmation
-- * validate challengID
-- * save confirmation
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Host_RecievedInviteConfirmation(challengeID, payload, senderToonID) 
	self:D("Challenge:Host_RecievedInviteConfirmation")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	-- validation
	if not self:validChallengeID(challengeID, nil, nil, senderToonID) then return end

	self:D("  add toonID %s with alias %s to host.invitations", tostring(senderToonID), payload.alias)

	-- prepare toon payload
	--local _, _, _, realm, _, faction = BNGetGameAccountInfo(senderToonID)
	local gameAccountInfo = BNGetGameAccountInfoByID(senderToonID)
	if gameAccountInfo then
		local realm = gameAccountInfo.realmName -- TODO
		local faction = gameAccountInfo.factionName -- TODO
		host.invitations[senderToonID] = {
			alias = payload.alias, -- from confirmation
			realm = realm,
			faction = faction,
			version = payload.version -- from confirmation
		}
	end

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- send an accept to the host
-- * send accept
-- * change invitation status
--   -> accepted invitation to pending
--   -> all other invitations to blocked
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Participant_SendAccept(challengeID, toonIDHost)
	self:D("Challenge.Participant_SendAccept")
	self:D("  challengeID=%s, toonIDHost=%s", challengeID, toonIDHost)

	-- prepare table
	participant.challenge = {}

	-- change invitation status and copy challenge data
	for savedChallengeID, savedPayload in pairs(participant.invitations) do
		if challengeID == savedChallengeID then
			savedPayload["status_accept"] = "pending"
			
			participant.challenge.challengeID = savedChallengeID
			participant.challenge.payload = savedPayload

			self.mode = savedPayload["m"] or "open"
		else
			savedPayload["status_accept"] = "blocked"
		end
	end

	-- prepare payload (needed for teamname)
	local team = self.db.profile.challenge.team or ("Team " .. GetUnitName("player", true))
	if participant.challenge.payload.teams then

	end

	-- alias should never be empty
	local alias = self.db.profile.challenge.alias or GetUnitName("player", true)
	if alias == "" then
		alias = GetUnitName("player", true) -- force unit name if saved alias is empty
	end

	local payload = {
		team = team,
		alias = alias,
	}

	-- send accept
	self:sendBnetMsg(toonIDHost, challengeID, p.action.accept, payload)

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- handler action 'accept'
-- * validate challengeID
-- * add participant to list of accepted invitations
-- * pronounce new accepted invitation
-- * send accept confirmation back to sender
-- 
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Host_RecievedAccept(challengeID, payload, senderToonID)
	self:D("Challenge:Host_RecievedAccept")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	-- validation
	if not self:validChallengeID(challengeID, nil, nil, senderToonID) then return end

	-- add to acceptedInvitations list
	host.acceptedInvitations[senderToonID] = host.invitations[senderToonID] or host.declinedInvitations[senderToonID]

	-- and overwrite alias (if necessary)
	if payload.alias and payload.alias ~= "" then
		host.acceptedInvitations[senderToonID].alias = payload.alias
	end

	-- handle team challenge
	if self.mode == "team" and host.teamNames then
		local team = payload["team"]

		-- step 1: remove the toonID from team if it is already registered
		self:removeToonIDFromTeam(senderToonID)

		-- step 1: add team (if not already added) and member
		local teamMembers = host.teamNames[team] or {}
		table.insert(teamMembers, senderToonID)

		host.teamNames[team] = teamMembers
	end

	-- removed from invitations and declinedInvitations lists
	host.invitations[senderToonID] = nil
	host.declinedInvitations[senderToonID] = nil

	-- pronounce new acceptance
	self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r invitation |cff00ff00accepted|r from " .. host.acceptedInvitations[senderToonID].alias .. ".")

	-- if the challenge is already running
	-- * put participant into list 'readyCheckConfirmed'
	-- * add row
	-- * send back a payload with the rest time
	local payload2send = {}
	if host.start then
		payload2send.restTime = self.challengeEndTime - time()

		host.readyCheckConfirmed[senderToonID] = host.acceptedInvitations[senderToonID]

		local grp = {
			liv = 0,
			name = host.acceptedInvitations[senderToonID].alias,
			realm = host.acceptedInvitations[senderToonID].realm,
		}
		host.rows[senderToonID] = grp
	end

	-- send accept confirmation
	self:sendBnetMsg(senderToonID, challengeID, p.action.accept_confirmation, payload2send)

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- handle action 'accept_confirmation'
-- * change invitation status
--   -> accepted invitation to confirmed
--
-- host -> participant
---------------------------------------------------------------------------------------]]
function Challenge:Participant_RecievedAcceptConfirmation(challengeID, payload, senderToonID)
	self:D("Challenge:Participant_RecievedAcceptConfirmation")
	self:D("  challengeID=%s", challengeID)
	self:D("  payload=")
	LA:print_r(payload)

	participant.challenge = participant.challenge or {}

	if participant.challenge.challengeID == challengeID then
		for savedChallengeID, savedPayload in pairs(participant.invitations) do
			if savedChallengeID == challengeID then
				savedPayload["status_accept"] = "confirmed"
			end
		end
	else
		self:D("  received confirmation (%s) is not for the requested challenge (%s)", tostring(challengeID), tostring(participant.challenge.challengeID))
	end

	-- if accept confirmation has a rest time we join a already running challenge
	-- * force start
	-- * change challenge end time
	if payload.restTime then
		self:Participant_RecievedStart(challengeID, payload, senderToonID)

		local currentSession = LA:getCurrentSession()
		self.challengeEndTime = currentSession["start"] + payload.restTime
	end

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- send cancel to every bnet friend
-- * send cancel
-- * reset the host data
-- 
-- host -> participant
---------------------------------------------------------------------------------------]]
function Challenge:Host_SendCancel()
	self:D("Challenge:Host_SendCancel")

	self.mode = nil

	-- cancel challenge control frame
	if self.challengeControlFrame then
		self.challengeControlFrame:SetScript("OnUpdate", nil) -- stop sending liv
		self.challengeControlFrame = nil
	end	
	
	-- send cancel to every bnet friend
	self:sendBnetMsgCancel(host.challengeID)

	-- reset data
	self:resetHostData()

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- handle action 'cancel'
-- * if confirmed
--   -> remove data
-- * remove invitation from list
-- * reopen all other invitations
--
-- host -> participant
---------------------------------------------------------------------------------------]]
function Challenge:Participant_RecievedCancel(challengeID)
	self:D("Challenge:Participant_RecievedCancel")
	self:D("  challengeID=%s", challengeID)

	participant.challenge = participant.challenge or {}

	-- if already confirmed than remove saved data
	if participant.challenge.challengeID == challengeID then
		-- pronounce cancelation
		self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r challenge from " .. participant.challenge.payload["alias"] .. " |cffff0000canceled|r.")

		participant.challenge = {}

		-- stop liv updates
		if self.challengeControlFrame then
			self.challengeControlFrame:SetScript("OnUpdate", nil) -- stop sending liv
			self.challengeControlFrame = nil
		end
	end

	-- remove invitation from list and...
	participant.invitations = participant.invitations or {}
	participant.invitations[challengeID] = nil

	-- ...reopen all other invitations
	for _, savedPayload in pairs(participant.invitations) do
		savedPayload["status_accept"] = nil
	end

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- send decline to the host
-- * send decline
-- * change invitation status
--   -> declined invitation to declined
--   -> all other invitations to open
-- 
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Participant_SendDecline(challengeID, toonIDHost)
	self:D("Challenge:Participant_SendDecline")
	self:D("  challengeID=%s, toonIDHost=%s", challengeID, toonIDHost)

	-- send decline
	self:sendBnetMsg(toonIDHost, challengeID, p.action.decline)

	-- set invitation status to declined
	local challengePayload = participant.invitations[challengeID]
	if challengePayload["status_accept"] == "confirmed" then
		-- reopen all invitations
		for savedChallengeID, savedPayload in pairs(participant.invitations) do
			savedPayload["status_accept"] = "open"
		end
	end
	challengePayload["status_accept"] = "declined"

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- hable action 'decline'
-- * validate challengeID
-- * add participant to list of declined invitations
-- * pronounce new declined invitation
--
-- TODO should we also send a confirmation back to the client? not sure...
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Host_RecievedDecline(challengeID, payload, toonIDSender)
	self:D("Challenge:Host_RecievedDecline")
	self:D("  challengeID=%s, toonIDSender=%s", challengeID, tostring(toonIDSender))

	-- validation
	if not self:validChallengeID(challengeID, nil, nil, toonIDSender) then return end

	-- add to declinedInvitations
	host.declinedInvitations[toonIDSender] = host.invitations[toonIDSender] or host.acceptedInvitations[toonIDSender]
	
	-- remove from other lists
	host.acceptedInvitations[toonIDSender] = nil
	host.readyCheckConfirmed[toonIDSender] = nil
	host.invitations[toonIDSender] = nil

	-- remove from teamlist (if necessary)
	if self.mode == "team" then
		self:removeToonIDFromTeam(toonIDSender)
	end

	-- pronounce new decline
	if host.declinedInvitations[toonIDSender] and host.declinedInvitations[toonIDSender].alias then
		self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r invitation |cffff0000declined|r from " .. host.declinedInvitations[toonIDSender].alias .. ".")
	end

	-- copy the decline to the row if the challenge is already running
	if host.rows and host.rows[toonIDSender] then
		host.rows[toonIDSender].decline = true
	end

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- remove the given toonID from teams
---------------------------------------------------------------------------------------]]
function Challenge:removeToonIDFromTeam(toonID)
	host.teamNames = host.teamNames or {}

	for name, members in pairs(host.teamNames) do
		for i = 1, #members do
			if members[i] == toonID then
				--LA:D("  found toonID %s in team %s", tostring(toonID), name)

				table.remove(members, i)

				--LA:D("  size of the team after remove: %s", tostring(#members))

				if #members == 0 then
					--LA:D("  team is empty -> remove")

					host.teamNames[name] = nil
				end
			end
		end
	end
end


--[[-------------------------------------------------------------------------------------
-- send ready check to all paticipants
-- * send ready check to every accepted invitation
-- 
-- host -> participants
---------------------------------------------------------------------------------------]]
function Challenge:Host_SendReadyCheck()
	self:D("Challenge:Host_SendReadyCheck")

	if host.readyCheck then return end

	host.readyCheck = true

	-- no confirmation checks on this side (host) so we can send the ready check multiple 
	-- times if needed
	for toonID, payload in pairs(host.acceptedInvitations) do
		self:D("  ready check send to toonID %s", tostring(toonID))
		self:sendBnetMsg(toonID, host.challengeID, p.action.ready)
	end

	host.readyCheck = false

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- handle action 'ready'
-- * show ready check ui (if not already done)
--
-- host -> participant
---------------------------------------------------------------------------------------]]
function Challenge:Participant_RecievedReadyCheck(challengeID, payload, senderToonID)
	self:D("Challenge:Participant_RecievedReadyCheck")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	participant.challenge = participant.challenge or {}

	-- looks like an old or other challenge sends a ready check
	if participant.challenge.challengeID ~= challengeID then return end

	-- ready check already received?
	if participant.challenge.readyCheck then return end

	local alias = participant.challenge.payload["alias"]

	-- pronounce ready check
	self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r ready check from |cff00ff00" .. alias .. "|r.")

	participant.challenge.readyCheck = true

	-- open up a confirmation dialog
	local READYCHECKUI = AceGUI:Create("Window")
	READYCHECKUI:Hide()
	READYCHECKUI:SetLayout("Flow")
	READYCHECKUI:SetTitle("LootAppraiser Challenge: Ready check")
	READYCHECKUI:SetPoint("CENTER")
	READYCHECKUI:SetWidth(350)
	READYCHECKUI:SetHeight(180)
	READYCHECKUI:EnableResize(false)
	READYCHECKUI:SetCallback("OnClose",
		function(widget) 
			-- only close, don't release
			participant.challenge.readyCheck = false
		end
	)

	-- challenge text
	local text = AceGUI:Create("LALabel")
	text:SetText("Ready check from " .. alias .. ". \n\nIf you click 'Yes' the host receives 'ready', LootAppraiser opens up in pause mode and the given challenge settings will be set.\n'No' will send 'not ready' back to the host.\n\nReady?\n")
	text:SetFont(GameFontNormal:GetFont())
	text:SetWidth(340)
	READYCHECKUI:AddChild(text)
	
	-- Button: Yes
	local btnYes = AceGUI:Create("Button")
	btnYes:SetPoint("CENTER")
	btnYes:SetAutoWidth(true)
	btnYes:SetText("Yes" .. " ")
	btnYes:SetCallback("OnClick", 
		function()
			self:onBtnReadyCheckYes(senderToonID)

            READYCHECKUI:Release()
            READYCHECKUI = nil
		end
	)
	READYCHECKUI:AddChild(btnYes)
	
	-- Button: No
	local btnNo = AceGUI:Create("Button")
	btnNo:SetPoint("CENTER")
	btnNo:SetAutoWidth(true)
	btnNo:SetText("No" .. " ")
	btnNo:SetCallback("OnClick", 
		function()
			participant.challenge.readyCheck = false

            READYCHECKUI:Release()
            READYCHECKUI = nil
		end
	)	
	READYCHECKUI:AddChild(btnNo)

	READYCHECKUI:Show()
end


--[[-------------------------------------------------------------------------------------
-- handle button 'yes' from ready check ui
---------------------------------------------------------------------------------------]]
function Challenge:onBtnReadyCheckYes(senderToonID)
	self:D("Challenge:onBtnReadyCheckYes")

    -- overwrite the settings with the given options
    LA.db.profile.general.qualityFilter = participant.challenge.payload["qf"] -- keep it for compatinility reasons with older LA versions
    LA.db.profile.notification.qualityFilter = participant.challenge.payload["qf"]
    LA.db.profile.pricesource.source = participant.challenge.payload["ps"]
	
	LA:StartSession(true)	-- start session
    LA:ShowMainWindow(true)	-- open main ui 
    LA:NewSession()			-- force new session in case a session is already running
    LA:pauseSession()		-- and pause session

    -- send ready check confirmation back to host
    self:sendBnetMsg(senderToonID, participant.challenge.challengeID, p.action.ready_confirmation)
end


--[[-------------------------------------------------------------------------------------
-- handle action 'ready_confirmation'
-- * pronounce new ready check confirmation
-- * add client to ready check confirmed list
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Host_RecievedReadyCheckConfirmation(challengeID, payload, senderToonID)
	self:D("Challenge:Host_RecievedReadyCheckConfirmation")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	-- validate
	if host.challengeID ~= challengeID then return end

	host.readyCheckConfirmed[senderToonID] = host.acceptedInvitations[senderToonID]

	-- pronounce ready check confirmation
	self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r ready check from |cff00ff00" .. host.readyCheckConfirmed[senderToonID].alias .. "|r confirmed.")

	-- update ui
	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- send start to the participants
-- * send start to every client on the accepted invitation list
--   -> remove and cancel every client which is not in the list ready check confirmed
-- * prepare and display the challenge ui
--
-- host -> participant
---------------------------------------------------------------------------------------]]
function Challenge:Host_SendStart()
	self:D("Challenge:Host_SendStart")

	host.start = true

	self.startConfirmed = self.startConfirmed or {}

	-- accepted but not confirmed will be removed from the list
	for toonID, payload in pairs(host.acceptedInvitations) do

		-- ready check not confirmed -> remove participant
		if host.readyCheckConfirmed[toonID] == nil then
			host.acceptedInvitations[toonID] = nil

			self:sendBnetMsg(toonID, host.challengeID, p.action.cancel)

		-- send start
		else
			self:D("  start send to toonID %s", tostring(toonID))

			self:sendBnetMsg(toonID, host.challengeID, p.action.start)

			-- add to map to manage resend start
			self.startConfirmed[toonID] = 0 -- value is retry count
		end
	end

	-- update ui
	self:updateUI()

	-- open loot appraiser on host
    LA.db.profile.general.qualityFilter = host.payload["qf"] -- keep it for compatinility reasons with older LA versions
    LA.db.profile.notification.qualityFilter = host.payload["qf"]
    LA.db.profile.pricesource.source = host.payload["ps"]
    LA:refreshStatusText()

	LA:StartSession(true)	-- start session
    LA:ShowMainWindow(true)	-- open main ui
    LA:NewSession()			-- force new session in case a session is already running

	-- prepare rows
	host.rows = {} -- clean empty list
	for toonID, payload in pairs(host.readyCheckConfirmed) do
		local grp = {
			liv = 0,
			name = payload.alias,
			realm = payload.realm,
		}

		host.rows[toonID] = grp
	end

	-- force a new UI
	if self.CHALLENGE_UI then
		AceGUI:Release(self.CHALLENGE_UI)
		self.CHALLENGE_UI = nil
	end

	self:prepareChallengeUI()

	-- and add the host
	local grp = {
		liv = 0,
		name = host.payload.alias,
		realm = GetRealmName()
	}

	host.rows[0] = grp -- toolID 0 is host

	-- calc challenge end
    local currentSession = LA:getCurrentSession()
    self.durationInSec = host.payload["duration"]*60
    self.challengeEndTime = currentSession["start"] + self.durationInSec

    self:D("  start=%s, end=%s after %s mins", date("!%X", currentSession["start"]), date("!%X", self.challengeEndTime), host.payload["duration"])    

    -- on update frame
    local resendInviteTotal = 0
    local checkReconnectTotal = 0 -- check every 10 seconds for reconnects

    self.challengeControlFrame = CreateFrame("Frame", nil, UIParent)
    self.challengeControlFrame:SetScript("OnUpdate", 
		function(event, elapsed)
		    -- resend invite
			resendInviteTotal = resendInviteTotal + elapsed
			if resendInviteTotal >= 3 then
				resendInviteTotal = 0

				if LA:tablelength(self.startConfirmed) > 0 then 
					for toonID, counter in pairs(self.startConfirmed) do
						if counter > 5 then
							self:D("  5 start retries -> give up")
							self.startConfirmed[toonID] = nil
						else
							self:D("  start send to toonID %s (%s)", tostring(toonID), tostring(counter + 1))
							self.startConfirmed[toonID] = counter + 1

							self:sendBnetMsg(toonID, host.challengeID, p.action.start)
						end
					end
				end
			end

		    -- challenge end
    		if time() >= self.challengeEndTime then
    			-- stop updates
			    if self.challengeControlFrame then
					self.challengeControlFrame:SetScript("OnUpdate", nil)
					self.challengeControlFrame = nil
				end

			    LA:pauseSession() -- and pause session

			    -- push last liv
			    local currentSession = LA:getCurrentSession()
				if currentSession then
					local grp = host.rows[0]

					grp.liv = floor(currentSession["liv"]/10000)
					grp.afk = UnitIsAFK("player")
					grp.finalLiv = true
				end

    			self.mode = nil

				self:refreshChallengeUITimer()
				self:updateUI()
    		end

    		-- reconnect to missing players
    		checkReconnectTotal = checkReconnectTotal + elapsed
    		if time() < self.challengeEndTime and checkReconnectTotal > 10 then
    			checkReconnectTotal = 0

    			-- go over all participants/rows and look for lastUpdate
    			local rows = self:getRowData()

				for toonID, grp in pairs(rows) do
					local lastUpdate = grp.lastUpdate or time()
					if lastUpdate <= (time() - 60) and not grp.decline then -- if we have no update inbetween the last 60 seconds -> reconnect
						self:D("  ### missing update")

						-- save current liv
						grp.preDcLiv = grp.liv

						-- add current rest time to the payload
						local restTime = self.challengeEndTime - time()
						self:D("  challengeEndTime=" .. tostring(self.challengeEndTime) .. ", restTime=" .. tostring(restTime))

						local payload = host.payload
						payload.challengeEndTime = self.challengeEndTime
						payload.restTime = restTime

						self:sendBnetMsg(toonID, host.challengeID, p.action.reconnect, host.payload)
					--else
					--	self:D("  ### update in time")
					end
				end
    		end
		end
	)

	self.CHALLENGE_UI:Show()

	self:refreshChallengeUI()
end


--[[-------------------------------------------------------------------------------------
-- handle action 'reconnect'
-- * same stuff as action 'start'
--
-- host -> participant
---------------------------------------------------------------------------------------]]
local updateLivTotal = 20 -- force send update liv immediatly
local updateLivOffset = fastrandom(0, 10) or 0 -- with this rnd offset we send liv every 20-30 seconds
function Challenge:Participant_RecieveReconnect(challengeID, payload, senderToonID)
	self:D("Participant_RecieveReconnect")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	participant.challenge = participant.challenge or {}

	-- if the player has a challengID we have already reconnected or he is
	-- participant in another challenge -> do nothing harmful
	if participant.challenge.challengeID ~= nil then return end

	local reconnectBehavior = self.db.profile.challenge.general.reconnectBehavior or "automatic" -- default value
	if reconnectBehavior == "popup"  then
		if self.reconnectPopupIsOpen then return end

		self.reconnectPopupIsOpen = true

		-- open up a confirmation dialog
		local READYCHECKUI = AceGUI:Create("Window")
		READYCHECKUI:Hide()
		READYCHECKUI:SetLayout("Flow")
		READYCHECKUI:SetTitle("LootAppraiser Challenge: Reconnect")
		READYCHECKUI:SetPoint("CENTER")
		READYCHECKUI:SetWidth(350)
		READYCHECKUI:SetHeight(180)
		READYCHECKUI:EnableResize(false)
		READYCHECKUI:SetCallback("OnClose",
			function(widget) 
				READYCHECKUI:Release()

				self.reconnectPopupIsOpen = nil
			end
		)

		-- challenge text
		local text = AceGUI:Create("LALabel")
		text:SetText("Reconnect from " .. payload.alias .. " received. \n\nIf you click 'Yes' you will be reconnected to the running challenge.\n'No' or closing this window will remove you from challenge.\n\nReconnect?\n")
		text:SetFont(GameFontNormal:GetFont())
		text:SetWidth(340)
		READYCHECKUI:AddChild(text)
		
		-- Button: Yes
		local btnYes = AceGUI:Create("Button")
		btnYes:SetPoint("CENTER")
		btnYes:SetAutoWidth(true)
		btnYes:SetText("Yes" .. " ")
		btnYes:SetCallback("OnClick", 
			function()
				self:processReconnect(challengeID, payload, senderToonID)

	            READYCHECKUI:Release()
	            READYCHECKUI = nil

				self.reconnectPopupIsOpen = nil
			end
		)
		READYCHECKUI:AddChild(btnYes)
		
		-- Button: No
		local btnNo = AceGUI:Create("Button")
		btnNo:SetPoint("CENTER")
		btnNo:SetAutoWidth(true)
		btnNo:SetText("No" .. " ")
		btnNo:SetCallback("OnClick", 
			function()
				-- send cancel
				self:sendBnetMsg(senderToonID, challengeID, p.action.decline)

	            READYCHECKUI:Release()
	            READYCHECKUI = nil

				self.reconnectPopupIsOpen = nil
			end
		)	
		READYCHECKUI:AddChild(btnNo)

		READYCHECKUI:Show()
	else
		self:processReconnect(challengeID, payload, senderToonID) 
	end
end


function Challenge:processReconnect(challengeID, payload, senderToonID)
	self:D("processReconnect")

	participant.challenge.challengeID = challengeID
	participant.challenge.payload = payload
	participant.challenge.payload.toonID = senderToonID

	-- pronounce challenge reconnect
	self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r reconnect to challenge from |cff00ff00" .. participant.challenge.payload["alias"] .. "|r.")
	self:D("  send liv every %s seconds", (20 + updateLivOffset))

	participant.challenge.start = true

	participant.isReconnect = true

    -- overwrite the settings with the given options (and refresh ui)
    LA.db.profile.general.qualityFilter = participant.challenge.payload["qf"] -- keep it for compatinility reasons with older LA versions
    LA.db.profile.notification.qualityFilter = participant.challenge.payload["qf"]
    LA.db.profile.pricesource.source = participant.challenge.payload["ps"]
    LA:refreshStatusText()

	LA:StartSession(true)	-- start session
    LA:ShowMainWindow(true)	-- open main ui
    LA:NewSession()			-- force new session in case a session is already running

    -- calc end time (not from duration, restTime is what we need)
    local currentSession = LA:getCurrentSession()
    self.durationInSec = participant.challenge.payload["duration"]*60
    self.challengeEndTime = currentSession["start"] + payload.restTime - 5 -- 5 seconds penalty/recalc time

    -- compensate if the off is bigger than p.reconnect.maxOffset -> not working because the servertime off between players
    --if self.challengeEndTime > (payload.challengeEndTime + p.reconnect.maxOffset) then
    --	self.challengeEndTime = payload.challengeEndTime + p.reconnect.maxOffset
    --end

	self:D("  challengeEndTime=" .. tostring(self.challengeEndTime) .. ", restTime=" .. tostring(payload.restTime))
    self:D("  start=%s, end=%s after %s mins", date("!%X", currentSession["start"]), date("!%X", self.challengeEndTime), participant.challenge.payload["duration"])

    -- on update frame
    self.challengeControlFrame = CreateFrame("Frame",nil,UIParent)
    self.challengeControlFrame:SetScript("OnUpdate", 
		function(event, elapsed)
			updateLivTotal = updateLivTotal + elapsed
    		if updateLivTotal >= (20 + updateLivOffset) then -- TODO
		        updateLivTotal = 0
		        updateLivOffset = fastrandom(0, 10) or 0 -- new offset

    			self:Participant_SendUpdateLiv(false)
		    end

		    -- challenge end
    		if time() >= self.challengeEndTime then    			
			    LA:pauseSession() -- and pause session

			    if self.challengeControlFrame then
					self.challengeControlFrame:SetScript("OnUpdate", nil) -- stop sending liv
					self.challengeControlFrame = nil
				end

    			self:Participant_SendUpdateLiv(true) -- last update

    			self.mode = nil

				self:refreshChallengeUI()
    			self:refreshChallengeUITimer()
				self:updateUI()
    		end
		end
	)

	-- force a new UI
	if self.CHALLENGE_UI then
		AceGUI:Release(self.CHALLENGE_UI)
		self.CHALLENGE_UI = nil
	end

	self:prepareChallengeUI()

	self:refreshChallengeUI()
end


--[[-------------------------------------------------------------------------------------
-- handle action 'start'
-- * pronounce challenge start
-- * set defined parameters (quality filter and price source)
-- * open loot appraiser
-- * start new session
-- * prepare push liv frame (push every 20 seconds the current liv)
--
-- host -> participant
---------------------------------------------------------------------------------------]]
function Challenge:Participant_RecievedStart(challengeID, payload, senderToonID)
	self:D("Challenge:Participant_RecievedStart")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	participant.challenge = participant.challenge or {}

	-- looks like a old challenge sends a start
	if participant.challenge.challengeID ~= challengeID then return end

	-- send confirmation back to host
	self:sendBnetMsg(senderToonID, challengeID, p.action.start_confirmation, {})

	-- pronounce challenge start
	self:Pour("|cFFFFFFCCLootAppraiser Challenge:|r start challenge from |cff00ff00" .. participant.challenge.payload["alias"] .. "|r.")
	self:D("  send liv every %s seconds", (20 + updateLivOffset))

	participant.challenge.start = true

    -- overwrite the settings with the given options (and refresh ui)
    LA.db.profile.general.qualityFilter = participant.challenge.payload["qf"] -- keep it for compatinility reasons with older LA versions
    LA.db.profile.general.notification = participant.challenge.payload["qf"]
    LA.db.profile.pricesource.source = participant.challenge.payload["ps"]
    LA:refreshStatusText()

	LA:StartSession(true)	-- start session
    LA:ShowMainWindow(true)	-- open main ui
    LA:NewSession()			-- force new session in case a session is already running

    -- calc end time
    local currentSession = LA:getCurrentSession()
    self.durationInSec = participant.challenge.payload["duration"]*60
    self.challengeEndTime = currentSession["start"] + self.durationInSec

    self:D("  start=%s, end=%s after %s mins", date("!%X", currentSession["start"]), date("!%X", self.challengeEndTime), participant.challenge.payload["duration"])

    -- on update frame
    self.challengeControlFrame = CreateFrame("Frame",nil,UIParent)
    self.challengeControlFrame:SetScript("OnUpdate", 
		function(event, elapsed)
			updateLivTotal = updateLivTotal + elapsed
    		if updateLivTotal >= (20 + updateLivOffset) then -- TODO
		        updateLivTotal = 0
		        updateLivOffset = fastrandom(0, 10) or 0 -- new offset

    			self:Participant_SendUpdateLiv(false)
		    end

		    -- challenge end
    		if time() >= self.challengeEndTime then    			
			    LA:pauseSession() -- and pause session

			    if self.challengeControlFrame then
					self.challengeControlFrame:SetScript("OnUpdate", nil) -- stop sending liv
					self.challengeControlFrame = nil
				end

    			self:Participant_SendUpdateLiv(true) -- last update

    			self.mode = nil

				self:refreshChallengeUI()
    			self:refreshChallengeUITimer()
				self:updateUI()
    		end
		end
	)

	-- force a new UI
	if self.CHALLENGE_UI then
		AceGUI:Release(self.CHALLENGE_UI)
		self.CHALLENGE_UI = nil
	end

	self:prepareChallengeUI()

	self:refreshChallengeUI()
end


--[[-------------------------------------------------------------------------------------
-- handle action 'start_confirmation'
-- * remove entry from table
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Host_RecievedStartConfirmation(challengeID, payload, senderToonID)
	self:D("Challenge:Host_RecievedStartConfirmation")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	self.startConfirmed = self.startConfirmed or {}

	-- remove entry from table
	if self.startConfirmed[senderToonID] then
		self:D("  remove " .. tostring(senderToonID) .. " from table")
		self.startConfirmed[senderToonID] = nil
	else
		self:D("  id " .. tostring(senderToonID) .. " not found in table")
	end
end


--[[-------------------------------------------------------------------------------------
-- handle 'Participant_SendUpdateLiv'
-- * get liv from current session
--   -> if session not found we send a decline to the host
-- * send update liv to host
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Participant_SendUpdateLiv(finalLiv)
	self:D("Challenge:Participant_SendUpdateLiv: finalLiv=%s", tostring(finalLiv))

	local toonID = participant.challenge.payload["toonID"]

	-- send current looted item value to host
	local currentSession = LA:getCurrentSession()
	if not currentSession then
		-- no session is running -> send decline to host
		self:sendBnetMsg(toonID, participant.challenge.challengeID, p.action.decline)
		return
	end

    -- prepare payload
	local payload = {
		liv = floor(currentSession["liv"]/10000), -- only gold value
		afk = UnitIsAFK("player"),
		mapAreas = participant.challenge.mapAreas or {},
		--lastItems = participant.challenge.lastItems or {},
		mostValueableItems = participant.challenge.mostValueableItems or {},

		isReconnect = participant.isReconnect
	}

	if finalLiv then
		payload["final"] = true
	end

	self:D("  toonID=" .. tostring(toonID) .. ", challengeID=" .. tostring(participant.challenge.challengeID))
	self:sendBnetMsg(toonID, participant.challenge.challengeID, p.action.update_liv, payload)
end


--[[-------------------------------------------------------------------------------------
-- handle action 'update_liv'
-- * validate challengeID
--
-- participant -> host
---------------------------------------------------------------------------------------]]
function Challenge:Host_RecievedUpdateLiv(challengeID, payload, senderToonID)
	self:D("Challenge:Host_RecievedUpdateLiv")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	self:D("  payload=")
	LA:print_r(payload)

	-- validation
	if not self:validChallengeID(challengeID, nil, nil, senderToonID) then return end

	-- get grp for senderToonID
	host.rows = host.rows or {}
	local grp = host.rows[senderToonID]
	if grp == nil then
		return
	end
	
	-- update data

	-- this is a reconnected player -> add liv from before to the current liv
	if payload.isReconnect == true then
		self:D("  update liv from a reconnected player!")
		grp.dcLiv = grp.preDcLiv
	end

	local newLiv = payload.liv
	if grp.dcLiv then
		newLiv = newLiv + grp.dcLiv
	end

	self:D("  senderToonID=%s; newLiv=%s", tostring(senderToonID), newLiv)
	grp.liv = newLiv

	grp.afk = payload.afk or false

	if payload.final == true then
		grp.finalLiv = true
	end
	grp.mapAreas = payload.mapAreas or nil
	grp.mostValueableItems = payload.mostValueableItems or nil

	grp.lastUpdate = time() -- save current time as last update time

	-- send ranking - prepare new table
	local ranking = {}
	for key, grp in pairs(host.rows) do
		local newGrp = {
			n = string.sub(grp.name, 1, 25),  -- only the first 25 characters
			r = grp.realm,

			l = grp.liv,
			f = grp.finalLiv,

			a = grp.afk,

			ma = grp.mapAreas,
			mvi = grp.mostValueableItems,

			p = grp.posChg
		}

		ranking[key] = newGrp
	end

	-- add team data if necessary
	local payload2send = {}
	if self.mode == "team" then
		table.insert(payload2send, ranking)
		table.insert(payload2send, host.teamNames)
	else
		payload2send = ranking
	end

	self:sendBnetMsg(senderToonID, challengeID, p.action.ranking, payload2send)
end


function Challenge:Participant_RecieveRanking(challengeID, payload, senderToonID)
	self:D("Challenge:Participant_RecieveRanking")
	self:D("  challengeID=%s, senderToonID=%s", challengeID, tostring(senderToonID))

	--LA:print_r(payload)
	self:D("  mode=" .. tostring(self.mode))

	participant.challenge = participant.challenge or {}

	local receivedRanking = nil

	-- we are currently in reconnect state and receive a ranking -> reconnect success!
	if participant.isReconnect == true then
		participant.isReconnect = nil
	end

	-- a team challenge sends 2 tables with ranking and teamdata
	if self.mode == "team" then
		receivedRanking = payload[1]
		participant.challenge.teamNames = payload[2] -- TODO uuurgs!!!
	else
		receivedRanking = payload
	end

	-- prepare ranking
	local ranking = {}
	for key, grp in pairs(receivedRanking) do
		local newGrp = {
			name = grp.n,
			realm = grp.r,

			liv = grp.l,
			finalLiv = grp.f,

			afk = grp.a,

			mapAreas = grp.ma,
			mostValueableItems = grp.mvi,

			posChg = grp.p
		}

		ranking[key] = newGrp
	end

	--LA:print_r(ranking)

	participant.challenge.ranking = ranking

	if not self.CHALLENGE_UI then
		self:prepareChallengeUI()
	end

	self:refreshChallengeUI()
end


--[[-------------------------------------------------------------------------------------
-- prepare the challenge ui
---------------------------------------------------------------------------------------]]
local challengeUILivUpdate = 0
local challengeUITimerUpdate = 0

local mviUIScale = 1
function Challenge:prepareChallengeUI()
	if self.CHALLENGE_UI then
		return
	end

	self:D("  prepare new CHALLENGE_UI")

	self.CHALLENGE_UI = AceGUI:Create("LAWindow")	
	self.CHALLENGE_UI:Hide()
	self.CHALLENGE_UI:SetStatusTable(self.db.profile.challengeUI)
	self.CHALLENGE_UI:SetTitle("LootAppraiser Challenge " .. self.METADATA.VERSION)
	self.CHALLENGE_UI:SetLayout("flow")
	self.CHALLENGE_UI:SetWidth(p.challengeUI.width)
	if self.CHALLENGE_UI.frame.SetResizeBounds then -- WoW 10.0
		self.CHALLENGE_UI.frame:SetResizeBounds(p.challengeUI.width, 120, p.challengeUI.width, 0)
	else
		self.CHALLENGE_UI.frame:SetMinResize(p.challengeUI.width, 120) -- TODO 
		self.CHALLENGE_UI.frame:SetMaxResize(p.challengeUI.width, 0)
	end
	self.CHALLENGE_UI:EnableResize(true)

	-- remember mode
	self.CHALLENGE_UI.mode = self.mode

	-- add header
	local headerGrp = AceGUI:Create("SimpleGroup")
	headerGrp:SetLayout("flow")
	headerGrp:SetFullWidth(true)

	-- timer
	self.durationInSec = self.durationInSec or 0

	self.CHALLENGE_TIMER = AceGUI:Create("LALabel")
	self.CHALLENGE_TIMER:SetWordWrap(false)
	self.CHALLENGE_TIMER:SetJustifyH("CENTER")
	self.CHALLENGE_TIMER:SetFont(self:GetTimerFont())
	self.CHALLENGE_TIMER:SetText("|cFFFFFFCC" .. date("!%X", self.durationInSec) .. "|r")
	self.CHALLENGE_TIMER:SetFullWidth(true)
    self.CHALLENGE_TIMER.frame:SetScript("OnUpdate", 
		function(event, elapsed)
		    challengeUITimerUpdate = challengeUITimerUpdate + elapsed
		    if challengeUITimerUpdate >= 1 then
		    	challengeUITimerUpdate = 0

		    	-- only update if challenge is running
		    	if self.challengeEndTime and time() <= self.challengeEndTime then
		    		self:refreshChallengeUITimer()
		    	end
		    end
		end
	)
	headerGrp:AddChild(self.CHALLENGE_TIMER)
	self.CHALLENGE_UI:AddChild(headerGrp)

	-- tab or normal mode
	if self.mode == "team" then
		local tabGroup = AceGUI:Create("TabGroup")
		tabGroup:SetLayout("flow")
		tabGroup:SetFullWidth(true)
		tabGroup:SetFullHeight(true)
		tabGroup:SetTabs({{text="Team", value="team"}, {text="Individual", value="individual"}})
		tabGroup:SetCallback("OnGroupSelected", Challenge.ChallengeUI_SelectGroup)
		tabGroup:SelectTab("team")

		self.CHALLENGE_UI:AddChild(tabGroup)
	else
		local simpleGroup = AceGUI:Create("SimpleGroup")
		simpleGroup:SetLayout("flow")
		simpleGroup:SetFullWidth(true)
		simpleGroup:SetFullHeight(true)

		self.CHALLENGE_UI:AddChild(simpleGroup)

		self:prepareChallengeUIContentContainer(simpleGroup)
	end

    -- register on update event (every 10 sec.)
    self.CHALLENGE_UI.frame:SetScript("OnUpdate", 
		function(event, elapsed)
			challengeUILivUpdate = challengeUILivUpdate + elapsed
    		if challengeUILivUpdate >= 10 then
		        challengeUILivUpdate = 0
    			
    			self:refreshChallengeUI()
		    end
		end
	)

	self.CHALLENGE_UI:Show()

	-- prepare most valueable items overall ui (host only) --
	if host.start then
		if self.MVI_UI then
			self.MVI_UI:Hide()
			AceGUI:Release(self.MVI_UI)
			self.MVI_UI = nil
		end

		self.MVI_UI = AceGUI:Create("LAWindow")	
		self.MVI_UI:Hide()
		self.MVI_UI:SetStatusTable(self.db.profile.mviUIx)
		self.MVI_UI:SetTitle("Most Valuable Items Overall")
		self.MVI_UI:SetLayout("flow")
		self.MVI_UI:SetWidth(p.mviUI.width)
		if self.MVI_UI.frame.SetResizeBounds then -- WoW 10.0
			self.MVI_UI.frame:SetResizeBounds(p.mviUI.width, 120, p.mviUI.width, 0)
		else
			self.MVI_UI.frame:SetMinResize(p.mviUI.width, 120) -- TODO 
			self.MVI_UI.frame:SetMaxResize(p.mviUI.width, 0)
		end
		self.MVI_UI:EnableResize(true)	
		--[[
		self.MVI_UI.frame:SetScript("OnSizeChanged", 
			function(self, width, height)
				if self.MVI_UI then
					LA:D("### changed: " .. tostring(width) .. "x" .. tostring(height))
					mviUIScale = 1/p.mviUI.width * width
					self.MVI_UI:DoLayout()
				end
			end
		)
		]]

		local MVI_SCROLLCONTAINER = AceGUI:Create("SimpleGroup")
		MVI_SCROLLCONTAINER:SetFullWidth(true)
		MVI_SCROLLCONTAINER:SetFullHeight(true)
		MVI_SCROLLCONTAINER:SetLayout("Fill")

		self.MVI_ROWS = AceGUI:Create("ScrollFrame")
		self.MVI_ROWS:SetLayout("Flow")
		MVI_SCROLLCONTAINER:AddChild(self.MVI_ROWS)	
		self.MVI_UI:AddChild(MVI_SCROLLCONTAINER)

		if Challenge.db.profile.challenge.general.enableMVItems == true then
			self.MVI_UI:Show()
		end

		--[[
		LibWindow.RegisterConfig(self.MVI_UI.frame, self.db.profile.mviUIx)
		LibWindow.SavePosition(self.MVI_UI.frame)
		LibWindow.SetScale(self.MVI_UI.frame, 1)
		LibWindow.RestorePosition(self.MVI_UI.frame)  -- restores scale also
		LibWindow.MakeDraggable(self.MVI_UI.frame)
		--LibWindow.EnableMouseOnAlt(self.MVI_UI.frame)
		LibWindow.EnableMouseWheelScaling(self.MVI_UI.frame)

		self.MVI_UI.frame:SetScript("OnDragStop", 
			function(self)
				LA:D("### save pos")
				LibWindow.SavePosition(self)
			end
		)
		]]
	end
end



function Challenge.ChallengeUI_SelectGroup(container, event, group)
	local self = Challenge

	container:ReleaseChildren()
	--container.frame:Hide() -- TODO

	self:D("ChallengeUI_SelectGroup: group=%s", tostring(group))

	-- add base elements (header, contentContainer and footer/total)
	self:prepareChallengeUIContentContainer(container)

	if group == "team" then
		self.CHALLENGE_UI.grp = "team"
	elseif group == "individual" then
		self.CHALLENGE_UI.grp = "individual"
	end

	self:refreshChallengeUI()
end


function Challenge:prepareChallengeUIContentContainer(parent)
	-- add header
	local headerGrp = AceGUI:Create("SimpleGroup")
	headerGrp:SetLayout("flow")
	headerGrp:SetFullWidth(true)

	-- name
	local name = AceGUI:Create("LALabel")
	name:SetWordWrap(false)
	name:SetJustifyH("CENTER")
	name:SetFont(GameFontNormal:GetFont())
	name:SetText("|cFFFFFFCCName|r")
	name:SetWidth(p.challengeUI.nameWidth)
	headerGrp:AddChild(name)

	-- liv
	local gold = AceGUI:Create("LALabel")
	gold:SetJustifyH("CENTER")
	gold:SetFont(GameFontNormal:GetFont())
	gold:SetText("|cFFFFFFCCItem Value|r")
	gold:SetWidth(p.challengeUI.livWidth)
	headerGrp:AddChild(gold)

	parent:AddChild(headerGrp)

	-- add content container
	local SCROLLCONTAINER = AceGUI:Create("SimpleGroup")
	SCROLLCONTAINER:SetFullWidth(true)
	SCROLLCONTAINER:SetFullHeight(true)
	SCROLLCONTAINER:SetLayout("Fill")

	self.ROWS = AceGUI:Create("ScrollFrame")
	self.ROWS:SetLayout("Flow")
	SCROLLCONTAINER:AddChild(self.ROWS)	
	parent:AddChild(SCROLLCONTAINER)

	-- init text
	local font, fontHeight, flags = self:GetDefaultFont()

	local grp = AceGUI:Create("SimpleGroup")
	grp:SetLayout("flow")
	grp:SetFullWidth(true)
	grp:SetHeight(60)

	local text = AceGUI:Create("LALabel")
	text:SetWordWrap(false)
	text:SetJustifyH("CENTER")
	text:SetFont(font, fontHeight, flags)
	text:SetText("Waiting for sync... (20-30 sec)")
	text:SetFullWidth(true)
	grp:AddChild(text)	

	self.ROWS:AddChild(grp)
end


--[[-------------------------------------------------------------------------------------
-- refresh the challenge ui
---------------------------------------------------------------------------------------]]
function Challenge:refreshChallengeUI()
	participant.challenge = participant.challenge or {}

	if not host.start and not participant.challenge.start then return end

	local allMostValueableItems = {}

	if self.CHALLENGE_UI.mode == "team" then
		if self.CHALLENGE_UI.grp == "team" then
			Challenge:prepareRowsForTeamChallenge(allMostValueableItems)
		elseif self.CHALLENGE_UI.grp == "individual" then
			Challenge:prepareRows(allMostValueableItems)
		end
	else
		Challenge:prepareRows(allMostValueableItems)
	end

	-- ##### MOST VALUABLE ITEMS OVERALL #####
	if host.start then
		Challenge:prepareMostValuableItemsOverall(allMostValueableItems)
	end
end


--[[-------------------------------------------------------------------------------------
-- prepare ranking for mode = team
---------------------------------------------------------------------------------------]]
local countUpdate = 0
function Challenge:prepareRowsForTeamChallenge(allMostValueableItems)
	-- host or participant
	local rows = self:getRowData()
	if self.tablelength(rows) == 0 then return end

	-- host only
	if host.start then
		-- set current liv of host (only if challenge is running)
		if self.challengeEndTime and time() <= self.challengeEndTime and rows[0] then
			local currentSession = LA:getCurrentSession()
			if currentSession then
				local grp = rows[0]
				grp.liv = floor(currentSession["liv"]/10000)
				grp.afk = UnitIsAFK("player")
			end
		end
	end

	-- prepare teamlist with team members
	local teamNames = self:getTeamData()
	if self.tablelength(teamNames) == 0 then return end -- TODO error msg

	local teamranking = {}
	for teamname, members in pairs(teamNames) do
		-- prepare 'team' data
		local team = {
			name = teamname,
			liv = 0,
			members = {}
		}

		-- lookup the members from rows
		for i = 1, #members do
			local toonID = members[i]

			local memberData = rows[toonID]
			if not memberData then
				memberData = rows[tostring(toonID)]
			end

			if memberData then
				table.insert(team.members, memberData)

				-- team sum
				if memberData.liv and memberData.liv ~= 0 then
					team.liv = team.liv + memberData.liv
				end
			end
		end

		table.insert(teamranking, team)
	end

	-- sort team and team members
	sort(teamranking,
		function (a, b)
			return a.liv > b.liv
		end
	)

	for i = 1, #teamranking do
		sort(teamranking[i].members,
			function (a, b)
				return a.liv > b.liv
			end
		)
	end

	-- delete rows
	self.ROWS:ReleaseChildren()

	-- create ui	
	local goldValueTotal = 0

	for count = 1, #teamranking do
		local team = teamranking[count]

		-- font for current place
		local font, fontHeight, flags = self:GetPlaceFont(count)

		-- gold
		local goldValue = team.liv
		goldValueTotal = goldValueTotal + goldValue
		local formattedGoldValue = Challenge.FormatTextMoney(goldValue*10000, "OPT_TRIM")		

		-- ### TEAM ###
		-- add row
		local teamContainer = AceGUI:Create("SimpleGroup")
		teamContainer:SetLayout("flow")
		teamContainer:SetFullWidth(true)
		--teamContainer:SetHeight(60)
		self.ROWS:AddChild(teamContainer)

		local teamNameContainer = AceGUI:Create("SimpleGroup")
		teamNameContainer:SetLayout("flow")
		teamNameContainer:SetFullWidth(true)
		--teamNameContainer:SetHeight(60)
		teamContainer:AddChild(teamNameContainer)

		-- pos
		local pos = AceGUI:Create("LALabel")
		pos:SetWordWrap(false)
		pos:SetJustifyH("CENTER")
		pos:SetFont(font, fontHeight, flags)
		pos:SetText(self.PrepareColor(tostring(count) .. ".", count))
		pos:SetWidth(p.challengeUI.posWidth)
		teamNameContainer:AddChild(pos)		

		-- name
		local name = team.name
		--if grp.finalLiv then
		--	name = "|cff00ff00" .. name .. "|r"
		--end
		--if grp.afk then
		--	name = "|cffff0000AFK:|r " .. name
		--end

		local teamnameLabel = AceGUI:Create("LAInteractiveLabel")
		teamnameLabel:SetWordWrap(false)
		teamnameLabel:SetJustifyH("LEFT")
		teamnameLabel:SetFont(font, fontHeight, flags)
		teamnameLabel:SetText(self.PrepareColor(name, count))
		teamnameLabel:SetWidth(p.challengeUI.nameWidth + p.challengeUI.posChangeWidth - 20) -- offset for scrollbar
		teamNameContainer:AddChild(teamnameLabel)

		-- gold
		local gold = AceGUI:Create("LALabel")
		gold:SetJustifyH("RIGHT")
		gold:SetFont(font, fontHeight, flags)
		gold:SetText(self.PrepareColor(formattedGoldValue, count))
		gold:SetWidth(p.challengeUI.livWidth)
		teamNameContainer:AddChild(gold)

		local members = team.members or {}
		for i = 1, #members do
			-- team member
			local member = members[i]

			-- font for current place
			local mfont, mfontHeight, mflags = self:GetDefaultFont()

			-- gold
			local mgoldValue = member.liv
			local mformattedGoldValue = Challenge.FormatTextMoney(mgoldValue*10000, "OPT_TRIM")

			-- host only
			if host.start and Challenge.db.profile.challenge.general.enableMVItems == true then
				-- prepare a list with all most valued items
				if member.mostValueableItems and LA:tablelength(member.mostValueableItems) > 0 then
					for index = 1, #member.mostValueableItems , 1 do
						local data = member.mostValueableItems[index]
						local newData = {
							name = member.name,
							team = team.name,

							id = data.id,
							gv = data.gv
						}

						table.insert(allMostValueableItems, newData)
					end
				end
			end

			local memberContainer = AceGUI:Create("SimpleGroup")
			memberContainer:SetLayout("flow")
			memberContainer:SetFullWidth(true)
			memberContainer:SetHeight(60)
			teamContainer:AddChild(memberContainer)

			-- spacer (for pos column)
			local spacerLabel = AceGUI:Create("LAInteractiveLabel")
			spacerLabel:SetFont(mfont, mfontHeight, mflags)
			spacerLabel:SetText("")
			spacerLabel:SetWidth(p.challengeUI.posWidth)
			memberContainer:AddChild(spacerLabel)

			-- name
			local membernameLabel = AceGUI:Create("LAInteractiveLabel")
			membernameLabel:SetWordWrap(false)
			membernameLabel:SetJustifyH("LEFT")
			membernameLabel:SetFont(mfont, mfontHeight, mflags)
			membernameLabel:SetText(member.name)
			membernameLabel:SetWidth(p.challengeUI.posChangeWidth + p.challengeUI.nameWidth - 20) -- offset for scrollbar
			--membernameLabel:SetCallback("OnEnter", Challenge.showMostValuableItemsTooltip(membernameLabel, member))
			membernameLabel:SetCallback("OnEnter", 
				function()
					GameTooltip:ClearLines()
					GameTooltip:SetOwner(membernameLabel.frame, "ANCHOR_CURSOR")

					local nameLine = member.name
					if member.realm then
						nameLine = nameLine .. " - " .. member.realm
					end

					GameTooltip:AddLine(nameLine) -- name + realm

					-- most valued items
					if member.mostValueableItems and LA:tablelength(member.mostValueableItems) > 0 then
						GameTooltip:AddLine(" ") -- spacer
						GameTooltip:AddLine("Most valueable items") -- headline

						for index = 1, #member.mostValueableItems , 1 do
							local data = member.mostValueableItems[index]

							local itemLink = select(2, GetItemInfo(data["id"]))
							local fmtGoldValue = Challenge.FormatTextMoney(data["gv"]*10000, "OPT_TRIM")

							GameTooltip:AddDoubleLine(itemLink, "|cffffffff" .. fmtGoldValue .. "|r")
						end
					end

					-- areas
					if member.mapAreas and LA:tablelength(member.mapAreas) > 0 then
						GameTooltip:AddLine(" ") -- spacer

						-- full count
						local fullCount = 0
						for _, count in pairs(member.mapAreas) do
							fullCount = fullCount + count
						end	

						for mapAreaID, count in pairs(member.mapAreas) do
							local mapname = GetMapInfo(mapAreaID)
							mapName = mapName and mapName.name

							local percent = floor(100/fullCount*count)
							GameTooltip:AddDoubleLine("|cffffffff" .. tostring(mapname or mapAreaID) .. "|r", "|cffffffff" .. tostring(percent) .. "%|r")
						end
					end

					GameTooltip:Show()
				end
			)
			membernameLabel:SetCallback("OnLeave", 
				function() GameTooltip:Hide() end
			)
			memberContainer:AddChild(membernameLabel)

			-- gold
			local memberGold = AceGUI:Create("LALabel")
			memberGold:SetJustifyH("LEFT")
			memberGold:SetFont(mfont, mfontHeight, mflags)
			memberGold:SetText(mformattedGoldValue)
			memberGold:SetWidth(p.challengeUI.livWidth)
			memberContainer:AddChild(memberGold)		
		end
	end

	-- ##### TOTAL LIV #####
	local font, fontHeight, flags = self:GetDefaultFont()

	local row = AceGUI:Create("SimpleGroup")
	row:SetLayout("flow")
	row:SetFullWidth(true)
	row:SetHeight(60)

	-- name
	local name = AceGUI:Create("LALabel")
	name:SetWordWrap(false)
	name:SetJustifyH("RIGHT")
	name:SetFont(font, fontHeight, flags)
	name:SetText("total:")
	name:SetWidth(p.challengeUI.posChangeWidth + p.challengeUI.posWidth + p.challengeUI.nameWidth - 20) -- offset for scrollbar
	row:AddChild(name)

	-- gold
	local formattedGoldValue = Challenge.FormatTextMoney(goldValueTotal*10000, "OPT_TRIM")

	local gold = AceGUI:Create("LALabel")
	gold:SetJustifyH("RIGHT")
	gold:SetFont(font, fontHeight, flags)
	gold:SetText(formattedGoldValue)
	gold:SetWidth(p.challengeUI.livWidth)
	row:AddChild(gold)

	self.ROWS:AddChild(row)

	--LA:print_r(teamranking)
end

--[[-------------------------------------------------------------------------------------
-- prepare ranking for mode open, private and last man standing. mode team is handles in
-- another function
---------------------------------------------------------------------------------------]]
function Challenge:prepareRows(allMostValueableItems)

	-- host or participant
	local rows = self:getRowData()

	if self.tablelength(rows) == 0 then return end

	-- host only
	if host.start then
		-- set current liv of host (only if challenge is running)
		if time() <= self.challengeEndTime then
			local currentSession = LA:getCurrentSession()
			if currentSession then
				local grp = rows[0]
				grp.liv = floor(currentSession["liv"]/10000)
				grp.afk = UnitIsAFK("player")
			end
		end
	end

	-- sort rows
	local sortedRows = {}
	for _,v in pairs(rows) do
		table.insert(sortedRows, v)
	end

	sort(sortedRows, 
		function(a, b) 
			return a.liv > b.liv
		end
	)

	-- delete rows
	self.ROWS:ReleaseChildren()

	local count = 1
	local goldValueTotal = 0
	--local allMostValueableItems = {}
	for _, grp in pairs(sortedRows) do
		-- font for current place
		local font, fontHeight, flags = self:GetPlaceFont(count)

		-- gold
		local goldValue = grp.liv
		goldValueTotal = goldValueTotal + goldValue
		local formattedGoldValue = Challenge.FormatTextMoney(goldValue*10000, "OPT_TRIM")

		-- host only
		if host.start and Challenge.db.profile.challenge.general.enableMVItems == true then
			-- prepare a list with all most valued items
			if grp.mostValueableItems and LA:tablelength(grp.mostValueableItems) > 0 then
				for index = 1, #grp.mostValueableItems , 1 do
					local data = grp.mostValueableItems[index]
					local newData = {
						name = grp.name,

						id = data.id,
						gv = data.gv
					}

					table.insert(allMostValueableItems, newData)
				end
			end
		end

		-- calc pos data and icon
		local posLeft, posRight, posTop, posBottom = Challenge:preparePosChangeAndIcon(grp, count)

		-- add row
		local row = AceGUI:Create("SimpleGroup")
		row:SetLayout("flow")
		row:SetFullWidth(true)
		row:SetHeight(60)

		-- pos changes
		local posChange = AceGUI:Create("LALabel")
		posChange:SetWordWrap(false)
		posChange:SetJustifyH("CENTER")
		posChange:SetFont(self:GetPlaceFont(10))
		posChange:SetWidth(p.challengeUI.posChangeWidth)
		posChange:SetHeight(16)
		posChange:SetImage("Interface\\AddOns\\LootAppraiser_Challenge\\Media\\posarrows", posLeft, posRight, posTop, posBottom)
		posChange:SetImageSize(16, 16)
		row:AddChild(posChange)

		-- pos
		local pos = AceGUI:Create("LALabel")
		pos:SetWordWrap(false)
		pos:SetJustifyH("CENTER")
		pos:SetFont(font, fontHeight, flags)
		pos:SetText(self.PrepareColor(tostring(count) .. ".", count))
		pos:SetWidth(p.challengeUI.posWidth)
		row:AddChild(pos)		

		-- name
		local name = grp.name
		if grp.finalLiv then
			name = "|cff00ff00" .. name .. "|r"
		end
		if grp.afk then
			name = "|cffff0000AFK:|r " .. name
		end

		local nameWidth = p.challengeUI.nameWidth
		if self.mode == "team" then
			nameWidth = nameWidth - 20 -- offset for scrollbar
		end

		local nameLabel = AceGUI:Create("LAInteractiveLabel")
		nameLabel:SetWordWrap(false)
		nameLabel:SetJustifyH("LEFT")
		nameLabel:SetFont(font, fontHeight, flags)
		nameLabel:SetText(self.PrepareColor(name, count))
		nameLabel:SetWidth(nameWidth)
		nameLabel:SetCallback("OnEnter", 
			function()
				GameTooltip:ClearLines()
				GameTooltip:SetOwner(nameLabel.frame, "ANCHOR_CURSOR")

				local nameLine = grp.name
				if grp.realm then
					nameLine = nameLine .. " - " .. grp.realm
				end

				GameTooltip:AddLine(nameLine) -- name + realm

				-- most valued items
				if grp.mostValueableItems and LA:tablelength(grp.mostValueableItems) > 0 then
					GameTooltip:AddLine(" ") -- spacer
					GameTooltip:AddLine("Most valueable items") -- headline

					for index = 1, #grp.mostValueableItems , 1 do
						local data = grp.mostValueableItems[index]

						local itemLink = select(2, GetItemInfo(data["id"]))
						local fmtGoldValue = Challenge.FormatTextMoney(data["gv"]*10000, "OPT_TRIM")

						GameTooltip:AddDoubleLine(itemLink, "|cffffffff" .. fmtGoldValue .. "|r")
					end
				end

				-- areas
				if grp.mapAreas and LA:tablelength(grp.mapAreas) > 0 then
					GameTooltip:AddLine(" ") -- spacer

					-- full count
					local fullCount = 0
					for _, count in pairs(grp.mapAreas) do
						fullCount = fullCount + count
					end	

					for mapAreaID, count in pairs(grp.mapAreas) do
						local mapName = GetMapInfo(mapAreaID)
						mapName = mapName and mapName.name

						local percent = floor(100/fullCount*count)
						GameTooltip:AddDoubleLine("|cffffffff" .. tostring(mapName or mapAreaID) .. "|r", "|cffffffff" .. tostring(percent) .. "%|r")
					end
				end

				GameTooltip:Show()
			end
		)
		nameLabel:SetCallback("OnLeave", 
			function()
				GameTooltip:Hide()
			end
		)
		row:AddChild(nameLabel)

		-- gold
		local gold = AceGUI:Create("LALabel")
		gold:SetJustifyH("RIGHT")
		gold:SetFont(font, fontHeight, flags)
		gold:SetText(self.PrepareColor(formattedGoldValue, count))
		gold:SetWidth(p.challengeUI.livWidth)
		row:AddChild(gold)

		self.ROWS:AddChild(row)

		count = count + 1
	end

	-- ##### TOTAL LIV #####
	local font, fontHeight, flags = self:GetPlaceFont(10)

	local row = AceGUI:Create("SimpleGroup")
	row:SetLayout("flow")
	row:SetFullWidth(true)
	row:SetHeight(60)

	-- pos
	local pos = AceGUI:Create("LALabel")
	pos:SetWordWrap(false)
	pos:SetJustifyH("CENTER")
	pos:SetFont(font, fontHeight, flags)
	pos:SetText(" ")
	pos:SetWidth(p.challengeUI.posWidth)
	row:AddChild(pos)	

	-- name
	local name = AceGUI:Create("LALabel")
	name:SetWordWrap(false)
	name:SetJustifyH("RIGHT")
	name:SetFont(font, fontHeight, flags)
	name:SetText(self.PrepareColor("total:", 10))
	name:SetWidth(p.challengeUI.nameWidth)
	row:AddChild(name)

	-- gold
	local formattedGoldValue = Challenge.FormatTextMoney(goldValueTotal*10000, "OPT_TRIM")

	local gold = AceGUI:Create("LALabel")
	gold:SetJustifyH("RIGHT")
	gold:SetFont(font, fontHeight, flags)
	gold:SetText(self.PrepareColor(formattedGoldValue, 10))
	gold:SetWidth(p.challengeUI.livWidth)
	row:AddChild(gold)

	self.ROWS:AddChild(row)
end


--[[-------------------------------------------------------------------------------------
-- get the row data depending we are host or participant
---------------------------------------------------------------------------------------]]
function Challenge:getRowData()
	-- host or participant
	local rows = nil
	if host.start then
		rows = host.rows
	elseif participant.challenge.start then
		rows = participant.challenge.ranking
	else
		self:D("  no host and no participant?!?")
		return
	end

	return rows
end


--[[-------------------------------------------------------------------------------------
-- get the team data depending we are host or participant
---------------------------------------------------------------------------------------]]
function Challenge:getTeamData()
	-- host or participant
	local rows = nil
	if host.start then
		rows = host.teamNames
	elseif participant.challenge.start then
		rows = participant.challenge.teamNames
	else
		self:D("  no host and no participant?!?")
		return
	end

	return rows
end


--[[-------------------------------------------------------------------------------------
-- prepare the most valueable items overall for the additional mvi_ui
---------------------------------------------------------------------------------------]]
function Challenge:prepareMostValuableItemsOverall(allMostValueableItems) 
	-- is enabled?
	if not Challenge.db.profile.challenge.general.enableMVItems then return end

	-- list is empty?
	if #allMostValueableItems == 0 then return end

	-- only the first x most valueable items
	local mostValueableItemsTotal = {}
	--if #allMostValueableItems > 0 then
		-- sort
		sort(allMostValueableItems, 
			function(a, b) 
				return a.gv > b.gv
			end
		)

		local count = Challenge.db.profile.challenge.general.mvItemCount
		if #allMostValueableItems < count then
			count = #allMostValueableItems
		end

		for index = 1, count , 1 do
			table.insert(mostValueableItemsTotal, allMostValueableItems[index])
		end
	--end

	allMostValueableItems = nil

	-- most valued items
	if mostValueableItemsTotal and LA:tablelength(mostValueableItemsTotal) > 0 then
		-- delete rows
		self.MVI_ROWS:ReleaseChildren()

		for index = 1, #mostValueableItemsTotal , 1 do
			local data = mostValueableItemsTotal[index]
			local itemLink = select(2, GetItemInfo(data.id))

			-- add row
			local row = AceGUI:Create("SimpleGroup")
			row:SetLayout("flow")
			row:SetWidth(p.mviUI.width - 30)

			-- item
			local item = AceGUI:Create("InteractiveLabel")
			item:SetFont(self:GetDefaultFont())
			item.label:SetWordWrap(false)
			item:SetText(itemLink)
			item:SetWidth(360)
			item:SetCallback("OnEnter", 
				function()
					if itemLink then
						GameTooltip:SetOwner(item.frame, "ANCHOR_CURSOR")
						GameTooltip:SetHyperlink(itemLink)
						GameTooltip:Show()
					end
				end
			)
			item:SetCallback("OnLeave", 
				function()
					GameTooltip:Hide()
				end
			)
			row:AddChild(item)

			-- name
			local preparedText = "|cffffffff" .. data.name .. "|r" -- .. itemLink
			if data.team then
				preparedText = preparedText .. " (" .. data.team .. ")"
			end

			local nameLabel = AceGUI:Create("InteractiveLabel")
			nameLabel:SetFont(self:GetDefaultFont())
			nameLabel.label:SetWordWrap(false)
			nameLabel:SetText(preparedText)
			nameLabel:SetWidth(260)
			nameLabel:SetCallback("OnEnter", 
				function()
					if itemLink then
						GameTooltip:SetOwner(nameLabel.frame, "ANCHOR_CURSOR")
						GameTooltip:SetHyperlink(itemLink)
						GameTooltip:Show()
					end
				end
			)
			nameLabel:SetCallback("OnLeave", 
				function()
					GameTooltip:Hide()
				end
			)
			row:AddChild(nameLabel)

			-- gold			
			local formattedGoldValue = Challenge.FormatTextMoney(data.gv*10000, "OPT_TRIM")

			local gold = AceGUI:Create("LALabel")
			gold:SetJustifyH("RIGHT")
			gold:SetFont(self:GetDefaultFontX())
			gold:SetText(self.PrepareColor(formattedGoldValue, 10))
			gold:SetWidth(100)
			row:AddChild(gold)

			self.MVI_ROWS:AddChild(row)
		end
	end
end


function Challenge:GetDefaultFontX()
	local font, _, flags = GameFontNormalLarge:GetFont()
	return font, 15 * mviUIScale, flags
end


--[[-------------------------------------------------------------------------------------
-- prepare the needed attributes to show position changes on ranking list
---------------------------------------------------------------------------------------]]
function Challenge:preparePosChangeAndIcon(grp, currentPos)
	-- calc pos data    					
	grp.pos = currentPos -- set current pos
	grp.posChg = grp.posChg or 0

	if not grp.prevPos then
		grp.prevPos = grp.pos
	end

	if grp.pos ~= grp.prevPos then
		grp.posChg = grp.prevPos - grp.pos
		grp.posChgTime = time()
	else
		-- remove unchanged pos after 60 seconds
		if grp.posChgTime and (time()-grp.posChgTime) > 60 then
			grp.posChgTime = nil
			grp.posChg = 0
		end
	end

	grp.prevPos = grp.pos

	local posLeft, posRight, posTop, posBottom = 0, 0, 0, 0 -- no image

	local posChg = grp.posChg
	if posChg > 0 then
		if posChg > 5 then posChg = 5 end

		posTop, posBottom = 0, 0.5 -- green arrows

		posLeft = (posChg-1) * 0.2
		posRight = posLeft + 0.2
	elseif posChg < 0 then
		if posChg < -5 then posChg = -5 end

		posTop, posBottom = 0.5, 1 -- red arrows

		posLeft = ((posChg*-1)-1) * 0.2
		posRight = posLeft + 0.2
	end

	return posLeft, posRight, posTop, posBottom
end


--[[-------------------------------------------------------------------------------------
-- refresh the challenge ui timer
---------------------------------------------------------------------------------------]]
function Challenge:refreshChallengeUITimer()
	self.challengeEndTime =  self.challengeEndTime or 0

	local delta = self.challengeEndTime - time()
	if delta < 0 then
		delta = 0
	end

	self.CHALLENGE_TIMER:SetText("|cFFFFFFCC" .. date("!%X", delta) .. "|r")
end

--[[-------------------------------------------------------------------------------------
-- prepare options table for challenge configuration
---------------------------------------------------------------------------------------]]
function Challenge:prepareChallengeOptions()
	-- clear old entries
	challengeOptions.args.invitationsGrp.args = {} 
	challengeOptions.args.invitationsGrp.name = "Invitations"
	challengeOptions.args.invitationsGrp.desc = nil

	if self.tablelength(host.acceptedInvitations) > 0 or self.tablelength(host.declinedInvitations) > 0 or self.tablelength(host.invitations) > 0  then
		
		Challenge:prepareChallengeOptionsAcceptedInvitations()
		Challenge:prepareChallengeOptionsDeclinedInvitations()
		Challenge:prepareChallengeOptionsHostInvitations()

		challengeOptions.args.invitationsGrp.name = "Invitations (" .. self.tablelength(host.acceptedInvitations) .. "/" .. self.tablelength(host.declinedInvitations) .. "/" .. self.tablelength(host.invitations) .. ")"
		challengeOptions.args.invitationsGrp.desc = "" .. self.tablelength(host.acceptedInvitations) .. " accepted\n" .. self.tablelength(host.declinedInvitations) .. " declined\n" .. self.tablelength(host.invitations) .. " open"

	else
		if self.tablelength(participant.invitations) == 0 then
			challengeOptions.args.invitationsGrp.args["noOpenInvitations"] = { 
				type = "description", order = 10, fontSize = "medium", name = "No open invitations.", width = "double", 
			}
		end
	end

	Challenge:prepareChallengeOptionsParticipantInvitations()
end


function Challenge:prepareChallengeOptionsParticipantInvitations()
	if self.tablelength(participant.invitations) > 0 then
		local invCount = 0
		for challengeID, payload in pairs(participant.invitations) do
			if payload ~= nil then
				-- add group
				local args = challengeOptions.args.invitationsGrp.args
				local currentSize = self.tablelength(args)

				local mode = payload["m"] or "open" -- defaults always to mode = open
				local modeText = "'" .. mode .. "' challenge"
				if mode == "lms" then
					modeText = "'Last Man Standing' challenge"
				end

				local grp = {
					type = "group",
					order = 100 + (10*(currentSize+1)),
					name = "Invitation from " .. (payload["alias"] or "unknown") .. " for a " .. modeText,
					inline = true,
					args = {
						labelDesc = { type = "description", order = 10, name = "|cffffd100Description|r", fontSize = "medium", width = "full", },
						desc = { type = "description", order = 20, name = (payload["desc"] or "-no description-"), fontSize = "medium", width = "full", },
							blank3 = { type = "description", order = 30, fontSize = "small", name = "", width = "full", }, 

						labelDuration = { type = "description", order = 35, name = "|cffffd100Duration|r", fontSize = "medium", width = "half", }, 
						labelQualityFilter = { type = "description", order = 40, name = "|cffffd100Quality Filter|r", fontSize = "medium", width = "half", }, 
						labelPriceSource = { type = "description", order = 45, name = "|cffffd100Price Source|r", fontSize = "medium", width = "double", }, 

						duration = { type = "description", order = 49, name = payload["duration"] .. " min", fontSize = "medium", width = "half", },
						qualityFilter = { type = "description", order = 50, name = LA.QUALITY_FILTER[payload["qf"]], fontSize = "medium", width = "half", },
						priceSource = { type = "description", order = 55, name = LA.PRICE_SOURCE[payload["ps"]], fontSize = "medium", width = "double", },
							blank5 = { type = "description", order = 57, fontSize = "small", name = "", width = "full", }, 

						alias = { type = "input", order = 60, name = "Name / Alias", width = "normal", 
							get = function(info) 
								if self.db.profile.challenge.alias and self.db.profile.challenge.alias ~= "" then
									return self.db.profile.challenge.alias
								end
								return GetUnitName("player", true)
							end,
							set = function(info, value)
								if not value or value == "" then
									value = GetUnitName("player", true)
								end
								self.db.profile.challenge[info[#info]] = value;
							end,
						},

						accept = { type = "execute", order = 70, name = "Accept",
							func = function()
								self:Participant_SendAccept(challengeID, payload.toonID)
							end,
							disabled = function()
								if not payload["status_accept"] then return false end
								if payload["status_accept"] == "pending" then return false end
								if payload["status_accept"] == "confirmed" then return true end
								if payload["status_accept"] == "blocked" then return true end
								if payload["status_accept"] == "declined" then return false end
							end
						},
						decline = { type = "execute", order = 80, name = "Decline",
							func = function()
								self:Participant_SendDecline(challengeID, payload.toonID)
							end,
							disabled = function()
								if not payload["status_accept"] then return false end
								if payload["status_accept"] == "pending" then return false end
								if payload["status_accept"] == "confirmed" then return false end
								if payload["status_accept"] == "blocked" then return true end
								if payload["status_accept"] == "declined" then return true end
							end
						},
							blank6 = { type = "description", order = 100, fontSize = "small", name = "", width = "full", }, 
						labelStatus = { type = "description", order = 110, name = "Status: ", fontSize = "medium", width = "half", }, 
						status = { type = "description", order = 115, fontSize = "medium", width = "double", 
							name = function()
								if not payload["status_accept"] then return "Open" end
								if payload["status_accept"] == "pending" then return "|cff0000ffPending|r" end
								if payload["status_accept"] == "confirmed" then return "|cff00ff00Confirmed|r" end
								if payload["status_accept"] == "blocked" then return "|cff0000ffBlocked|r" end
								if payload["status_accept"] == "declined" then return "|cffff0000Declined|r" end
							end, 
						},
					},
					plugins = {},		
				}

				-- if mode = 'team' add an additional textfield/dropdown and a blank line (fullsize) before the buttons
				if mode == "team" then
					-- attention: never change order!

					-- add dropdown for premade teams
					if payload.teams then						
						grp.args["team"] = { type = "select", order = 59, width = "normal", name = "Premade Teams", desc = "A list of premade teams.", 
							get = function(info) 
								if self.db.profile.challenge.team and self.db.profile.challenge.team ~= "" then
									return self.db.profile.challenge.team
								end
								return "Team " .. GetUnitName("player", true) -- generate a teamname
							end,
							set = function(info, value)
								if not value or value == "" then
									value = "Team " .. GetUnitName("player", true)
								end
								self.db.profile.challenge[info[#info]] = value;
							end,
							values = function()
								return payload.teams
							end,
						}

					-- add input field for teamname
					else
						grp.args["team"] = { type = "input", order = 59, name = "Teamname", desc = "The teamname. Must be unique per team.", width = "normal", 
							get = function(info) 
								if self.db.profile.challenge.team and self.db.profile.challenge.team ~= "" then
									return self.db.profile.challenge.team
								end
								return "Team " .. GetUnitName("player", true) -- generate a teamname
							end,
							set = function(info, value)
								if not value or value == "" then
									value = "Team " .. GetUnitName("player", true)
								end
								self.db.profile.challenge[info[#info]] = value;
							end,
							validate = function(info, value)
								if string.len(value) < 3 or string.len(value) > 25 then
									UIErrorsFrame:AddMessage("|cffff0000LootAppraiser Challenge:|r 'Teamname' must between 3 and 25 characters.")
									return false
								end
								return true
							end,
						}
					end
					grp.args["blank7"] = { type = "description", order = 65, fontSize = "small", name = "", width = "full", }
				end

				args[challengeID] = grp
				invCount = invCount + 1
			end
		end

		-- change tab headline
		challengeOptions.args.invitationsGrp.name = "Invitations (" .. self.tablelength(participant.invitations) .. ")"
	end
end


function Challenge:prepareChallengeOptionsDeclinedInvitations()
	local declinedInvGrp = { type = "group", order = 20, name = "|cFFFFCC00Declined Invitations|r", inline = true, args = {}, plugins = {}, }

	if self.tablelength(host.declinedInvitations) > 0 then
		declinedInvGrp.args["headerToonName"] = { type = "description", order = 1, name = "|cFFFFFFCCChar/Alias|r", fontSize = "medium", width = "double", }
		declinedInvGrp.args["headerBlank1"] = { type = "description", order = 3, name = "", fontSize = "medium", width = "half", }
		declinedInvGrp.args["headerDelete"] = { type = "description", order = 5, name = "", fontSize = "medium", width = "half", }
		declinedInvGrp.args["headerBlank2"] = { type = "description", order = 9, name = "", fontSize = "small", width = "full", }

		local rowCount = 1
		for toonID, payload in pairs(host.declinedInvitations) do
			declinedInvGrp.args["inv" .. tostring(rowCount) .. "ToonName"] = { type = "description", order = 10*(rowCount)+1, fontSize = "medium", width = "double", imageWidth = 14, imageHeight = 14, 
				image = function()
					local faction = payload.faction
					if faction == "Alliance" then
						return "Interface\\FriendsFrame\\PlusManz-Alliance" 
					elseif faction == "Horde" then
						return "Interface\\FriendsFrame\\PlusManz-Horde"
					end
					return nil
				end,
				name = function()
					local name = payload.alias
					local realm = payload.realm
					if realm ~= nil then name = name .. " - " .. realm end
					return name
				end,
			}
			declinedInvGrp.args["inv" .. tostring(rowCount) .. "Blank1"] = { type = "description", order = 10*(rowCount)+3, name = "", fontSize = "medium", width = "half", }
			declinedInvGrp.args["inv" .. tostring(rowCount) .. "Delete"] = { type = "execute", order = 10*(rowCount)+5, name = "", desc = "Remove this participant from the list (allows reinvite)", fontSize = "medium", width = "half", imageWidth = 10, imageHeight = 10,
				image = function () return "Interface\\BUTTONS\\UI-GroupLoot-Pass-Up" end,
				func = function() 
					self:DeleteParticipant(toonID, host.declinedInvitations)
				end,
			}
			declinedInvGrp.args["inv" .. tostring(rowCount) .. "Blank2"] = { type = "description", order = 10*(rowCount)+9, name = "", width = "full", fontSize = "small", }			

			rowCount = rowCount + 1
		end

		challengeOptions.args.invitationsGrp.name = "Invitations (" .. self.tablelength(host.declinedInvitations) .. ")"
	else
		declinedInvGrp.args["none"] = { type = "description", order = 10, name = "None", fontSize = "medium", width = "full", }
	end

	challengeOptions.args.invitationsGrp.args["declinedInvitationsGrp"] = declinedInvGrp
end


function Challenge:prepareChallengeOptionsHostInvitations()
	local openInvGrp = { type = "group", order = 30, name = "|cFFFFCC00Open Invitations|r", inline = true, args = {}, plugins = {}, }

	if self.tablelength(host.invitations) > 0 then
		openInvGrp.args["headerToonName"] = { type = "description", order = 1, name = "|cFFFFFFCCChar/Alias|r", fontSize = "medium", width = "double", }
		openInvGrp.args["headerVersion"] = { type = "description", order = 5, name = "Version", fontSize = "medium", width = "half", }
		openInvGrp.args["headerDelete"] = { type = "description", order = 7, name = "", fontSize = "medium", width = "half", }
		openInvGrp.args["headerBlank"] = { type = "description", order = 9, name = "", fontSize = "small", width = "full", }
		
		local rowCount = 1
		for toonID, payload in pairs(host.invitations) do

			openInvGrp.args["inv" .. tostring(rowCount) .. "ToonName"] = { type = "description", order = 10*(rowCount)+1, fontSize = "medium", width = "double", imageWidth = 14, imageHeight = 14, 
				image = function()
					local faction = payload.faction
					if faction == "Alliance" then
						return "Interface\\FriendsFrame\\PlusManz-Alliance" 
					elseif faction == "Horde" then
						return "Interface\\FriendsFrame\\PlusManz-Horde"
					end
					return nil
				end,
				name = function()
					local name = payload.alias
					local realm = payload.realm
					if realm ~= nil then name = name .. " - " .. realm end
					return name
				end,
			}
			openInvGrp.args["inv" .. tostring(rowCount) .. "Version"] = { type = "description", order = 10*(rowCount)+5, fontSize = "medium", width = "half", 
				name = function()
					local version = payload.version
					if version then return Challenge:formatVersion(version) end
					return "|cffff0000unknown|r"
				end,
			}			
			openInvGrp.args["inv" .. tostring(rowCount) .. "Delete"] = { type = "execute", order = 10*(rowCount)+7, name = "", desc = "Remove this participant from the list (allows reinvite)", fontSize = "medium", width = "half", imageWidth = 10, imageHeight = 10,
				image = function () return "Interface\\BUTTONS\\UI-GroupLoot-Pass-Up" end,
				func = function() 
					self:DeleteParticipant(toonID, host.invitations)
				end,
			}
			openInvGrp.args["inv" .. tostring(rowCount) .. "Blank"] = { type = "description", order = 10*(rowCount)+9, name = "", width = "full", fontSize = "small", }			

			rowCount = rowCount + 1
		end

		challengeOptions.args.invitationsGrp.name = "Invitations (" .. self.tablelength(host.invitations) .. ")"
	else
		openInvGrp.args["none"] = { type = "description", order = 10, name = "None", fontSize = "medium", width = "full", }
	end

	challengeOptions.args.invitationsGrp.args["openInvitationsGrp"] = openInvGrp
end


function Challenge:prepareChallengeOptionsAcceptedInvitations()
	local acceptedInvGrp = { type = "group", order = 10, name = "|cFFFFCC00Accepted Invitations|r", inline = true, args = {}, plugins = {}, }

	if self.tablelength(host.acceptedInvitations) > 0 then
		-- different layout depending on mode
		if self.mode == "team" then
			-- mode team
			acceptedInvGrp.args["headerName"] = { type = "description", order = 1, name = "|cFFFFFFCCTeam|r", fontSize = "medium", width = "half", }
			acceptedInvGrp.args["headerReadyCheck"] = { type = "description", order = 5, name = "|cFFFFFFCCMember|r", fontSize = "medium", width = "half", }
			acceptedInvGrp.args["headerDelete"] = { type = "description", order = 7, name = "", fontSize = "medium", width = "half", }
			acceptedInvGrp.args["headerBlank"] = { type = "description", order = 9, name = "", fontSize = "small", width = "full", }

			local rowCount = 1
			for teamname, teamMembers in pairs(host.teamNames) do
				-- add a row with the teamname
				acceptedInvGrp.args["inv" .. tostring(rowCount) .. "Teamname"] = {
					type = "description", order = 10*(rowCount)+1, name = teamname, fontSize = "large", width = "full",
				}

				-- add a row for every team member
				rowCount = rowCount + 1
				for i = 1, #teamMembers do
					local toonID  = teamMembers[i]
					local payload = host.acceptedInvitations[toonID]

					if payload then
						Challenge:addTeamMember2AcceptedList(acceptedInvGrp, rowCount, payload, toonID)

						rowCount = rowCount + 1
					else
						-- special handling for host (toonID = 0)
						if toonID == 0 then
							-- prepare payload for function call
							local payload = {
								faction = UnitFactionGroup("player"),
								alias = self.db.profile.challenge.alias,
								realm = GetRealmName(),
								host = true,
							}

							Challenge:addTeamMember2AcceptedList(acceptedInvGrp, rowCount, payload, toonID)

							rowCount = rowCount + 1
						end
					end
				end
			end
		else
			-- mode: open, private and last man standing
			acceptedInvGrp.args["headerName"] = { type = "description", order = 1, name = "|cFFFFFFCCName|r", fontSize = "medium", width = "double", }
			acceptedInvGrp.args["headerReadyCheck"] = { type = "description", order = 5, name = "", fontSize = "medium", width = "half", }
			acceptedInvGrp.args["headerDelete"] = { type = "description", order = 7, name = "", fontSize = "medium", width = "half", }
			acceptedInvGrp.args["headerBlank"] = { type = "description", order = 9, name = "", fontSize = "small", width = "full", }

			local rowCount = 1
			for toonID, payload in pairs(host.acceptedInvitations) do
				local alias = payload["alias"]

				acceptedInvGrp.args["inv" .. tostring(rowCount) .. "Name"] = { type = "description", order = 10*(rowCount)+1, fontSize = "medium", width = "double", imageWidth = 14, imageHeight = 14, 
					image = function()
						local faction = payload["faction"]
						if faction == "Alliance" then
							return "Interface\\FriendsFrame\\PlusManz-Alliance" 
						elseif faction == "Horde" then
							return "Interface\\FriendsFrame\\PlusManz-Horde" 
						else
							return nil
						end
					end,
					name = function()
						local name = payload["alias"]
						local realm = payload["realm"]
						if realm ~= nil then
							name = name .. " - " .. realm
						end
						return name
					end,
				}
				acceptedInvGrp.args["inv" .. tostring(rowCount) .. "ReadyCheck"] = { type = "description", order = 10*(rowCount)+5, name = "", fontSize = "medium", width = "half", imageWidth = 10, imageHeight = 10,
					image = function () if host.readyCheckConfirmed and host.readyCheckConfirmed[toonID] ~= nil then return "Interface\\RAIDFRAME\\ReadyCheck-Ready" end end,
				}
				acceptedInvGrp.args["inv" .. tostring(rowCount) .. "Delete"] = { type = "execute", order = 10*(rowCount)+7, name = "", desc = "Remove this participant from the list (allows reinvite)", fontSize = "medium", width = "half", imageWidth = 10, imageHeight = 10,
					image = function () return "Interface\\BUTTONS\\UI-GroupLoot-Pass-Up" end,
					func = function() 
						self:DeleteParticipant(toonID, host.acceptedInvitations)
					end,
				}
				acceptedInvGrp.args["inv" .. tostring(rowCount) .. "Blank"] = { type = "description", order = 10*(rowCount)+9, name = "", width = "full", fontSize = "small", }			

				rowCount = rowCount + 1
			end
		end

		-- button 'ready check' --
		challengeOptions.args.invitationsGrp.args["readyCheck"] = { type = "execute", order = 11, name = "Ready Check",
			func = function() self:Host_SendReadyCheck() end,
			disabled = function()
				if host.start then return true end
				if host.readyCheck then return true end
				if LA:tablelength(host.acceptedInvitations) > 0 then return false end
				return true
			end,
		}

		-- button 'start challenge' --
		challengeOptions.args.invitationsGrp.args["startChallenge"] = { type = "execute", order = 12, name = "Start Challenge",
			func = function() self:Host_SendStart() end,
			disabled = function()
				if host.start then return true end
				if self.tablelength(host.readyCheckConfirmed) > 0 then return false end
				return true
			end,
		}
	else
		acceptedInvGrp.args["none"] = { type = "description", order = 10, name = "None", fontSize = "medium", width = "full", }
	end

	challengeOptions.args.invitationsGrp.args["acceptedInvitationsGrp"] = acceptedInvGrp	
end


function Challenge:addTeamMember2AcceptedList(acceptedInvGrp, rowCount, payload, toonID)
	--acceptedInvGrp.args["inv"] = { type = "description", order = 10*(rowCount)+1, name = "", fontSize = "medium", width = "half", }
	acceptedInvGrp.args["inv" .. tostring(rowCount) .. "Name"] = { type = "description", order = 10*(rowCount)+2, fontSize = "medium", width = "double", imageWidth = 14, imageHeight = 14, 
		image = function()
			local faction = payload["faction"]
			if faction == "Alliance" then
				return "Interface\\FriendsFrame\\PlusManz-Alliance" 
			elseif faction == "Horde" then
				return "Interface\\FriendsFrame\\PlusManz-Horde" 
			else
				return nil
			end
		end,
		name = function()
			local name = payload["alias"]
			local realm = payload["realm"]
			if realm ~= nil then
				name = name .. " - " .. realm
			end
			return name
		end,
	}
	acceptedInvGrp.args["inv" .. tostring(rowCount) .. "ReadyCheck"] = { type = "description", order = 10*(rowCount)+5, name = "", fontSize = "medium", width = "half", imageWidth = 10, imageHeight = 10,
		image = function () 
			if (host.readyCheckConfirmed and host.readyCheckConfirmed[toonID] ~= nil) or payload.host then return "Interface\\RAIDFRAME\\ReadyCheck-Ready" end 
		end,
	}
	acceptedInvGrp.args["inv" .. tostring(rowCount) .. "Delete"] = { type = "execute", order = 10*(rowCount)+7, name = "", desc = "Remove this participant from the list (allows reinvite)", fontSize = "medium", width = "half", imageWidth = 10, imageHeight = 10,
		image = function () return "Interface\\BUTTONS\\UI-GroupLoot-Pass-Up" end,
		func = function() 
			self:DeleteParticipant(toonID, host.acceptedInvitations)
		end,
		hidden = function ()
			if toonID == 0 then return true else return false end
		end,
	}
	acceptedInvGrp.args["inv" .. tostring(rowCount) .. "Blank"] = { type = "description", order = 10*(rowCount)+9, name = "", width = "full", fontSize = "small", }			
end

--[[-------------------------------------------------------------------------------------
-- delete the participant with the given key from all lists so a (re)send invite should 
-- work again (it's for dudes which accept an invite and than relog or reload ;( )
---------------------------------------------------------------------------------------]]
function Challenge:DeleteParticipant(key, list)
	self:D("DeleteParticipant: key=%s", key)

	if list[key] then
		self:D("  remove key=%s from list", key)
	end

	list[key] = nil

	self:updateUI()
end


--[[-------------------------------------------------------------------------------------
-- update challenge ui (config)
---------------------------------------------------------------------------------------]]
function Challenge:updateUI()
	self:D("updateUI")

	self:prepareChallengeOptions()

	AceConfigRegistry:NotifyChange("LootAppraiser Challenge")
end


-- TODO
function Challenge:formatVersion(version)
	--local splitOne = self.split(version, "v")
	return version
end


--[[-------------------------------------------------------------------------------------
-- reset the complete host data
---------------------------------------------------------------------------------------]]
function Challenge:resetHostData()
	host = {}
end


--[[-------------------------------------------------------------------------------------
-- prepare font strings
---------------------------------------------------------------------------------------]]
function Challenge:GetPlaceOneFont()
	local font, _, flags = GameFontNormalLarge:GetFont()
	return font, 25, flags
end


function Challenge:GetPlaceTwoFont()
	local font, _, flags = GameFontNormalLarge:GetFont()
	return font, 21, flags
end


function Challenge:GetPlaceThreeFont()
	local font, _, flags = GameFontNormalLarge:GetFont()
	return font, 17, flags
end


function Challenge:GetPlaceFont(place)
	if place == 1 then
		return self:GetPlaceOneFont()
	elseif place == 2 then
		return self:GetPlaceTwoFont()
	elseif place == 3 then
		return self:GetPlaceThreeFont()
	else
		return self:GetDefaultFont()
	end
end


function Challenge:GetDefaultFont()
	local font, _, flags = GameFontNormalLarge:GetFont()
	return font, 15, flags
end


function Challenge:GetTimerFont()
	local font, _, flags = GameFontNormalLarge:GetFont()
	return font, 40, flags
end


--[[-------------------------------------------------------------------------------------
-- prepare color based on current place
---------------------------------------------------------------------------------------]]
function Challenge.PrepareColor(text, place)
	if place == 1 then
		return "|cFFFFF569" .. text .. "|r"
	elseif place == 2 then
		return "|cFFDEDEDE" .. text .. "|r"
	elseif place == 3 then
		return "|cFFFF7D0A" .. text .. "|r"
	else
		return text
	end
end


--[[-------------------------------------------------------------------------------------
-- send bnet msg
---------------------------------------------------------------------------------------]]
function Challenge:sendBnetMsg(presenceID, ...)

	local json = ""
	for n=1, select('#', ...) do
		if json ~= "" then
			json = json .. "\001"
		end
		json = json .. LibParse:JSONEncode(select(n,...))
	end

	self:SendCommMessage(p.prefix, json, presenceID)
end


--[[-------------------------------------------------------------------------------------
-- send 'cancel' for challengeID to a given toonID or every bnet friend
---------------------------------------------------------------------------------------]]
function Challenge:sendBnetMsgCancel(challengeID)
	-- send cancel: iterate over bnet friends and send cancel to every bnet with a char online
	for friendIndex = 1, BNGetNumFriends() do
		--local _, _, battleTag, _, _, _, _, isOnline = BNGetFriendInfo(friendIndex)
		local accountInfo = BNGetFriendAccountInfo(friendIndex)
		if accountInfo then
			local battleTag = accountInfo.battleTag -- TODO
			local isOnline = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline -- TODO

			if isOnline then
				for toonIndex = 1, BNGetFriendNumGameAccounts(friendIndex) do
					--local _, toonName, client, _, _, _, _, _, _, _, _, _, _, _, _, toonID = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
					local gameAccountInfo = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
					if gameAccountInfo then
						local client = gameAccountInfo.clientProgram -- TODO
						local toonName = gameAccountInfo.characterName -- TODO
						local toonID = gameAccountInfo.gameAccountID -- TODO

						if client == "WoW" then
							-- send cancel
							self:D("  cancel send to %s (%s)", battleTag, toonName)
							self:sendBnetMsg(toonID, challengeID, p.action.cancel)
						end
					end
				end
			end
		end
	end
end


--[[-------------------------------------------------------------------------------------
-- get toonID from battleTag and toonName
---------------------------------------------------------------------------------------]]
function Challenge:getToonId(searchBattleTag, searchToonName)
	--self:D("  getToonId: searchBattleTag=%s, searchToonName=%s", tostring(searchBattleTag), tostring(searchToonName))
	-- iterate over bnet friends
	for friendIndex = 1, BNGetNumFriends() do
		--local _, _, battleTag = BNGetFriendInfo(friendIndex)
		local accountInfo = BNGetFriendAccountInfo(friendIndex)
		if accountInfo then
			local battleTag = accountInfo.battleTag -- TODO
			if battleTag == searchBattleTag then
				self:D("  battleTag=%s", battleTag)

				for toonIndex = 1, BNGetFriendNumGameAccounts(friendIndex) do				
					--local _, toonName, client, _, _, _, _, _, _, _, _, _, _, _, _, toonID = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
					local gameAccountInfo = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
					if gameAccountInfo then
						local client = gameAccountInfo.clientProgram -- TODO
						local toonName = gameAccountInfo.characterName -- TODO
						local toonID = gameAccountInfo.gameAccountID -- TODO

						--self:D("    toonName=%s, client=%s, toonID=%s", toonName, client, toonID)
						if toonName == searchToonName and client == "WoW" then
							return toonID
						end
					end
				end
			end
		end
	end
end


--[[-------------------------------------------------------------------------------------
-- validate the given challengeID against the host challengeID
---------------------------------------------------------------------------------------]]
function Challenge:validChallengeID(challengeID, battleTagSender, toonNameSender, toonIDSender)
	-- no challenge is running
	local result = true
	if not host.challengeID then
		self:D("  received a message for a challenge (%s) but we have no challenge running -> send back cancel", challengeID)
		self:sendBnetMsg(toonIDSender, challengeID, p.action.cancel)

		result = false

	-- different challenge is running
	elseif host.challengeID ~= challengeID then
		self:D("  received message (%s) is not for the current challenge (%s) -> send back cancel", challengeID, host.challengeID)
		self:sendBnetMsg(toonIDSender, challengeID, p.action.cancel)

		result = false		
	end

	return result
end


--[[-------------------------------------------------------------------------------------
-- init lootappraiser db
---------------------------------------------------------------------------------------]]
function Challenge:initDB()
	self:D("initDB()")

	local parentWidth = UIParent:GetWidth()
	local parentHeight = UIParent:GetHeight()

	-- la defaults
	self.dbDefaults = {
		profile = {
			enableDebugOutput = false,

			challengeUI = { ["height"] = 400, ["top"] = (parentHeight-50), ["left"] = 50, ["width"] = 400, },
			mviUI = { ["height"] = 400, ["top"] = (parentHeight-50), ["left"] = 50, ["width"] = 400, },
			mviUIx = {},
			challenge = { 
				bnetTest = {
					msgSize = 100,
					msgCount = 1,
				},
				general = {
					enableMVItems = true,
					mvItemCount = 5,
					reconnectBehavior = "automatic",
					allowRequest4Invite = true,
				},
				config = {
					premadeTeam = {
						teams = {},					
					},
				},
			},
		},
	}
	
	-- load the saved db values
	self.db = LibStub:GetLibrary("AceDB-3.0"):New("LootAppraiserChallengeDB", self.dbDefaults, true)
end


function Challenge.tablelength(T)
	if T == nil then return 0 end
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end


function Challenge.split(str, sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, 
    	function(c) 
    		fields[#fields+1] = c 
    	end
    )
    return fields
end


function Challenge:D(msg, ...)
	if Challenge:isDebugOutputEnabled() then
        print(string.format(msg, ...))
	end
end


function Challenge:isDebugOutputEnabled()
    return xDebugMode
end

--[[-------------------------------------------------------------------------------------
-- FIXED: add challenge invite and request for invite to bnet liste context menu
---------------------------------------------------------------------------------------]]
-- local menuList = {
--     UnitPopupMenuFriend,
--     UnitPopupMenuPlayer,
--     UnitPopupMenuEnemyPlayer,
--     UnitPopupMenuParty,
--     UnitPopupMenuRaid,
--     UnitPopupMenuRaidPlayer,
--     UnitPopupMenuSelf,
--     UnitPopupMenuBnFriend,
--     UnitPopupMenuGuild,
--     UnitPopupMenuGuildOffline,
--     UnitPopupMenuChatRoster,
--     UnitPopupMenuTarget,
--     UnitPopupMenuArenaEnemy,
--     UnitPopupMenuFocus,
--     UnitPopupMenuWorldStateScore,
--     UnitPopupMenuCommunitiesGuildMember,
--     UnitPopupMenuCommunitiesWowMember,
-- }
 
 -- using mixin as blizzard recommended
-- local CustomMenuButtonMixin = CreateFromMixins(UnitPopupButtonBaseMixin)
-- function CustomMenuButtonMixin:GetText() return "LAC Invite" end
-- function CustomMenuButtonMixin:OnClick()
--     local invite = { text = "Invite", owner = which, notCheckable = 1, disabled = inviteDisabled, func = Challenge.OnClick_BNetInv, arg1 = dropdownMenu }
--     Challenge.OnClick_BNetInv(invite)
-- end
 
 -- extends every item in popup list, added custom button
-- for i,v in ipairs(menuList) do
--     local originButton = v.GetEntries
--     function v:GetEntries()
--        local buttons = originButton(self)
--        table.insert(buttons, 1, CustomMenuButtonMixin)
--        return buttons
--     end
-- end

--[[-------------------------------------------------------------------------------------
-- add challenge invite and request for invite to bnet liste context menu
---------------------------------------------------------------------------------------]]
-- function Challenge.UnitPopup_ShowMenu(dropdownMenu, which, unit, name, userData)
-- 	if(which == "BN_FRIEND" and dropdownMenu.which == "BN_FRIEND") then

-- 		--Challenge:D("Challenge.UnitPopup_ShowMenu: dropdownMenu=" .. tostring(dropdownMenu) .. ", which=" .. tostring(which) .. ", unit=" .. tostring(unit) .. ", name=" .. tostring(name) .. ", userData=" .. tostring(userData))

-- 		--local spacer = { disabled = 1, notCheckable = 1, colorCode = nil, checked = nil, hasArrow = nil }
-- 		--UIDropDownMenu_AddButton(spacer)

-- 		local headline = { text = "LootAppraiser Challenge", owner = which, notCheckable = 1, isTitle = 1 }
-- 		UIDropDownMenu_AddButton(headline)

-- 		-- invite
-- 		local inviteDisabled = 1
-- 		if host.challengeID then
-- 			inviteDisabled = nil
-- 		end

-- 		local invite = { text = "Invite", owner = which, notCheckable = 1, disabled = inviteDisabled, func = Challenge.OnClick_BNetInv, arg1 = dropdownMenu }
-- 		UIDropDownMenu_AddButton(invite)

-- 		-- request for invite
-- 		local request4InviteDisabled = nil
-- 		if host.challengeID or (participant.challenge and participant.challenge.challengeID) then
-- 			request4InviteDisabled = 1
-- 		end

-- 		local reqeustForInvite = { 
-- 			text = "Send request for invite", 
-- 			owner = which, 
-- 			notCheckable = 1, 
-- 			disabled = request4InviteDisabled, 
-- 			func = Challenge.OnClick_BNetRequest4Inv, 
-- 			arg1 = dropdownMenu 
-- 		}
-- 		UIDropDownMenu_AddButton(reqeustForInvite)
-- 	end
-- end
-- hooksecurefunc("UnitPopup_ShowMenu", Challenge.UnitPopup_ShowMenu)


--[[-------------------------------------------------------------------------------------
-- on click handler for 'send request for invite'
---------------------------------------------------------------------------------------]]
function Challenge.OnClick_BNetRequest4Inv(data, arg1)
	local self = Challenge

	self:D("OnClick_BNetRequest4Inv")

	local dropdownFrame = UIDROPDOWNMENU_INIT_MENU
	if dropdownFrame and dropdownFrame.bnetIDAccount then
		local bnetIDAccount = dropdownFrame.bnetIDAccount
		local friendIndex = BNGetFriendIndex(bnetIDAccount)

		self:sendRequest4Invite(friendIndex)
	end
end


--[[-------------------------------------------------------------------------------------
-- send a 'request for invite' to every toonID of the given friendIndex
---------------------------------------------------------------------------------------]]
function Challenge:sendRequest4Invite(friendIndex)
	--local _, _, battleTag, _, _, _, _, isOnline = BNGetFriendInfo(friendIndex)
	local accountInfo = BNGetFriendAccountInfo(friendIndex)
	if accountInfo then
		local battleTag = accountInfo.battleTag -- TODO
		local isOnline = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline -- TODO

		if isOnline then
			for toonIndex = 1, BNGetFriendNumGameAccounts(friendIndex) do
				--local _, toonName, client, _, _, _, _, _, _, _, _, _, _, _, _, toonID = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
				local gameAccountInfo = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
				if gameAccountInfo then
					local client = gameAccountInfo.clientProgram -- TODO
					local toonName = gameAccountInfo.characterName -- TODO
					local toonID = gameAccountInfo.gameAccountID -- TODO

					if client == "WoW" then
						local key = battleTag .. "@" .. toonID

						self:D("  request for invite send to battleTag=%s, toonID=%s (toonName=%s)", battleTag, toonID, toonName)
						self:sendBnetMsg(toonID, "undefined", p.action.request4invite) -- send invite
					end
				end
			end
		end	
	end
end


--[[-------------------------------------------------------------------------------------
-- on click handler 'challenge invite'
---------------------------------------------------------------------------------------]]
function Challenge.OnClick_BNetInv(data, a1)
	Challenge:D("OnClick_BNetInv")
	--Challenge:D("  a1=%s", tostring(a1))

	local dropdownFrame = UIDROPDOWNMENU_INIT_MENU
	LA:print_r(a1)
	if dropdownFrame and dropdownFrame.bnetIDAccount then
		local bnetIDAccount = dropdownFrame.bnetIDAccount
		--local battleTag = select(3, BNGetFriendInfoByID(bnetIDAccount))
		local accountInfo = BNGetAccountInfoByID(bnetIDAccount)
		if accountInfo then
			local battleTag = accountInfo.battleTag -- TODO

			Challenge:D("  bnetIDAccount=%s, battleTag=%s", bnetIDAccount, tostring(battleTag))

			for friendIndex = 1, BNGetNumFriends() do
				--local bt = select(3, BNGetFriendInfo(friendIndex))
				local accountInfo = BNGetFriendAccountInfo(friendIndex)
				if accountInfo then
					local bt = accountInfo.battleTag -- TODO
					if bt == battleTag then
						Challenge:sendInvite(friendIndex)
						break
					end
				end
			end
		end
	end
end


--[[-------------------------------------------------------------------------------------
-- send invite
---------------------------------------------------------------------------------------]]
function Challenge:sendInvite(friendIndex)
	--local _, _, battleTag, _, _, _, _, isOnline = BNGetFriendInfo(friendIndex)
	local accountInfo = BNGetFriendAccountInfo(friendIndex)
	if accountInfo then
		local battleTag = accountInfo.battleTag -- TODO
		local isOnline = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline -- TODO

		if isOnline then
			for toonIndex = 1, BNGetFriendNumGameAccounts(friendIndex) do
				--local _, toonName, client, _, _, _, _, _, _, _, _, _, _, _, _, toonID = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
				local gameAccountInfo = BNGetFriendGameAccountInfo(friendIndex, toonIndex)
				if gameAccountInfo then
					local client = gameAccountInfo.clientProgram -- TODO
					local toonName = gameAccountInfo.characterName -- TODO
					local toonID = gameAccountInfo.gameAccountID -- TODO

					if client == "WoW" then
						local key = battleTag .. "@" .. toonID

						self:D("  invite send to battleTag=%s, toonID=%s (toonName=%s)", battleTag, toonID, toonName)
						self:sendBnetMsg(toonID, host.challengeID, p.action.invite, host.payload) -- send invite
					end
				end
			end
		end
	end
end


--[[-------------------------------------------------------------------------------------
-- based on TSMAPI_FOUR.Money.ToString from TSM 4
---------------------------------------------------------------------------------------]]
function Challenge.FormatTextMoney(money, ...) 

	money = tonumber(money)
	if not money then return end

	local isNegative = money < 0
	money = abs(money)
	local gold = floor(money / COPPER_PER_GOLD)
	local goldText, copperText = "|cffffd70ag|r", "|cffeda55fc|r"

	if money == 0 then
		return tostring(0)..copperText
	end

	local text = nil

	-- gold
	if gold > 0 then
		text = tostring(gold)..goldText
	end

	if isNegative then
		return "-"..text
	else
		return text
	end
end

function Challenge.IsSoulbound(itemID, retry)
	itemID = tonumber(itemID)
	retry = retry or true

	local itemName, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemID)
	Challenge:D("itemName = " .. tostring(itemName))
	Challenge:D("bindType = " .. tostring(bindType))
	if bindType == nil and retry then
		return Challenge.IsSoulbound(itemID, false)
	end

	if bindType == 1 or bindType == 4 then
		return true
	end

	return false
end
