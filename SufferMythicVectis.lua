----------------------------
--      Constants         --
----------------------------

local _

local INITIAL_FRAME_TEXT = "Suffer Mythic Vectis\n\nWaiting for encounter to start\n\nClick to drag this frame around\nType /smvf to hide";

-- Actual vectis values
local VECTIS_ENCOUNTER_ID = 2134;
local OMEGA_VECTOR_SPELL_ID = 265129;
local LINGERING_INFECTION_SPELL_ID = 265127;
local CONTAGION_SPELL_ID = 267242;
local MYTHIC_RAID_DIFFICULTY = 16;

-- Test values, uncomment to test on Kargath
--VECTIS_ENCOUNTER_ID, OMEGA_VECTOR_SPELL_ID, LINGERING_INFECTION_SPELL_ID, CONTAGION_SPELL_ID = 1721, 159113, 159386, 158986;

------------------------------
--      Initialization      --
------------------------------

SufferMythicVectis = LibStub("AceAddon-3.0"):NewAddon("SufferMythicVectis", "AceEvent-3.0", "AceConsole-3.0")

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:OnInitialize
--
--		Called when the addon is initialized
--
function SufferMythicVectis:OnInitialize()

	-- Cache session constants
	self.strPlayerName = UnitName("player");

	-- Build the settings table
	local options = {
		type = "group",
		name = "Suffer Mythic Vectis",
		get = function(info) return self.db.profile[ info[#info] ] end,
		set = function(info, value) self.db.profile[ info[#info] ] = value end,
		args = {
			General = {
				order = 1,
				type = "group",
				name = "General Settings",
				desc = "General Settings",
				args = {

					fMythicOnly = {
						type = "toggle",
						name = "Mythic only",
						desc = "Only enable addon for Mythic Vectis",
						order = 1,
					},
					fEnableSay = {
						type = "toggle",
						name = "Enable /say",
						desc = "Uncheck to block all /say chat from this addon",
						order = 2,
					},
					fEnableSound = {
						type = "toggle",
						name = "Enable sounds",
						desc = "Uncheck to mute all sounds from this addon",
						order = 3,
					},
					fIgnoreMute = {
						type = "toggle",
						name = "Ignore mute",
						desc = "Uncheck to play sounds on the master channel (bypassing game sound mute)",
						order = 4,
					},
					fOmegaGainedWarning= {
						type = "toggle",
						name = "Omega gained sound",
						desc = "Play the same phone sound whenever you gain Omega Vector.",
						order = 5,
					},
					fOmegaDoneSound = {
						type = "toggle",
						name = "Omega done sound",
						desc = "Play the applause sound when you've dropped Omega Vector and are not next.",
						order = 6,
					},
					fSpreadWarning = {
						type = "toggle",
						name = "Spread warning",
						desc = "Warn the player when contagion is cast and the player must spread",
						order = 7,
					},
					fMarkOmegaVector = {
						type = "toggle",
						name = "Mark omega",
						desc = "(Raid lead only) Mark omega vector targets with group awareness (conflicts with DBM and BigWigs' algorithms).",
						order = 8,
					},
					fWrongMarkWarning = {
						type = "toggle",
						name = "Wrong mark warning",
						desc = "Plays a Goblin Engineering sound if your Omega Vector marker doesn't match your group's",
						order = 9,
					},
					fShowNext = {
						type = "toggle",
						name = "Show next",
						desc = "Show the next player in the text frame",
						order = 10,
					},
					fShowSpread = {
						type = "toggle",
						name = "Show spread",
						desc = "Show contagion spread status in the text frame",
						order = 11,
					},
					fShowDuration = {
						type = "toggle",
						name = "Show omega timer",
						desc = "Show Omega Vector expiration timer in text frame",
						order = 12,
					},
					btnMovableFrame = {
						type = "execute",
						func = function() SufferMythicVectis:ToggleFrameVisibility() end,
						name = "Show/Hide Frame",
						desc = "Show/Hide the text frame so you can move it around",
						order = 13,
						width = "double",
					},
				},
			},
		},
	};

	local DEFAULTS = {
		profile = {
			fEnableOutputMessages = true,
			fMythicOnly = true,
			fEnableSound = true,
			fEnableSay = true,
			fIgnoreMute = true,
			fOmegaDoneSound = true,
			fOmegaGainedWarning = true,
			fSpreadWarning = true,
			fMarkOmegaVector = true,
			fWrongMarkWarning = true,
			fShowNext = true,
			fShowSpread = true,
			fShowDuration = true,
		}
	};
	self.db = LibStub("AceDB-3.0"):New("SufferMythicVectisDB", DEFAULTS, "default");

	options.args.Profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db);
	LibStub("AceConfig-3.0"):RegisterOptionsTable("Suffer Mythic Vectis", options);
	LibStub("AceConfigDialog-3.0"):SetDefaultSize("Suffer Mythic Vectis", 640, 480);
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Suffer Mythic Vectis", nil, nil, "General");
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Suffer Mythic Vectis", "Profile", "Suffer Mythic Vectis", "Profile");
	self:RegisterChatCommand("smv", function() LibStub("AceConfigDialog-3.0"):Open("Suffer Mythic Vectis") end);
	self:RegisterChatCommand("smvf", function() SufferMythicVectis:ToggleFrameVisibility() end);


	-- Init stuff so we don't get nil errors
	self.iEncounterId = 0;
	self.iDifficultyIndex = 0;
	self.iMyGroup = -1;
	self.iMyRank = -1;
	self.tbOmegaGroup = {};
	self.tbOmegaInfo = {};
	self.fChooseNextSoakerAndNotifyQueued = false;
end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:OnEnable
--
--		Called when the addon is enabled
--
function SufferMythicVectis:OnEnable()
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
	self:RegisterEvent("ENCOUNTER_START");
	self:RegisterEvent("ENCOUNTER_END");

	self:OutputMessage("Add-on loaded");
end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:OnDisable
--
--		Called when the addon is disabled
--
function SufferMythicVectis:OnDisable()
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
	self:UnregisterEvent("ENCOUNTER_START");
	self:UnregisterEvent("ENCOUNTER_END");
end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:OnTick
--
--		Periodic callback to update the text frame
--
function SufferMythicVectis:OnTick()

	-- Break out if the encounter has ended
	if self.iEncounterId ~= VECTIS_ENCOUNTER_ID then
		return;
	end

	if self.tmContagionStart then
		self:CheckContagionStatus();
	end

	if self.db.profile.fOmegaDoneSound and self.tmNextOmegaDoneSound and GetTime() >= self.tmNextOmegaDoneSound then
		-- Don't give the applause sound if the player is next
		if self.strNextSoaker ~= self.strPlayerName then
			self:CheckAndPlaySound("Interface\\AddOns\\WeakAuras\\Media\\Sounds\\Applause.ogg");
		end
		self.tmNextOmegaDoneSound = nil;
	end

	if self.textFrame then
		self:RefreshGroupLingeringInfectionStacks();
		self.textFrame.text:SetText(self:GetDisplayText());
	end

	if self.db.profile.fWrongMarkWarning then
		self:CheckMyRaidIcon();
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:ENCOUNTER_START
--
--		Handler for encounter starting
--
function SufferMythicVectis:ENCOUNTER_START(strEvent, arg1)

	self.iEncounterId = tonumber(arg1);

	if self.iEncounterId == VECTIS_ENCOUNTER_ID then

		-- Check difficulty
		local _, _, difficultyIndex = GetInstanceInfo();
		self.iDifficultyIndex = difficultyIndex;

		if self.db.profile.fMythicOnly and self.iDifficultyIndex ~= MYTHIC_RAID_DIFFICULTY then

			-- Depending on settings, only enable functionality on mythic difficulty
			self.iEncounterId = 0;

		else

			self:OutputMessage("Vectis encounter started");

			self.tmOmegaVectorExpiration = nil;
			self.tmLastNextNotification = nil;
			self.tmLastWrongIconNotification = nil;
			self.tbOmegaGroup, self.tbOmegaInfo = self:GetOmegaGroup();
			self.strNextSoaker = nil;
			self.tmContagionStart = nil;
			self.tmWrongIconStart = nil;
			self.tmNextOmegaDoneSound = nil;

			self:ChooseNextSoaker();

			if not self.textFrame then
				self:CreateTextFrame();
			end

			self.textFrame:Show();

			if not self.ticker then
				self.ticker = C_Timer.NewTicker(0.1, function() self:OnTick() end);
			end

		end

	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:ENCOUNTER_END
--
--		Handler for encounter ending
--
function SufferMythicVectis:ENCOUNTER_END(strEvent, arg1)

	if self.iEncounterId == VECTIS_ENCOUNTER_ID then
		self:OutputMessage("Vectis encounter ended");
	end

	self.iEncounterId = 0;

	if self.textFrame then
		self.textFrame:Hide();
	end

	if self.ticker then
		self.ticker:Cancel();
		self.ticker = nil;
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:COMBAT_LOG_EVENT_UNFILTERED
--
--		Handler for combat log events.
--
function SufferMythicVectis:COMBAT_LOG_EVENT_UNFILTERED(event)

	-- Short circuit combatlog processing if we're not in the vectis encounter
	if self.iEncounterId ~= VECTIS_ENCOUNTER_ID then
		return;
	end

	iTimestamp, strEventType, fHideCaster, strSourceGuid, strSourceName, iSourceFlags, iSourceFlags2, strDestGuid, strDestName, iDestFlags, iDestFlags2, varParam1, varParam2, varParam3, varParam4, varParam5, varParam6 = CombatLogGetCurrentEventInfo()

	if strEventType == "SPELL_AURA_REMOVED" and varParam1 == OMEGA_VECTOR_SPELL_ID then

		-- Update state when Omega Vector is removed
		--self:OutputMessage("Omega vector fell off " .. strDestName);

		local isSelf = UnitIsUnit(strDestName, "player");

		if (isSelf or self.tbOmegaInfo[strDestName]) then
			-- It could be that just one stack of multiple fell off.  Double check that the unit really doesn't have any omega vectors left
			if not self:FindDebuffById(strDestName, OMEGA_VECTOR_SPELL_ID) then

				if self.tbOmegaInfo[strDestName] then
					self.tbOmegaInfo[strDestName].fHasOmegaVector = false;
				end

				if isSelf then
					-- Queue an "Omega Vector Done" sound if the player still doesn't have omega vector after 2 seconds
					self.tmNextOmegaDoneSound = GetTime() + 2;
				end
			end
		end

	elseif strEventType == "SPELL_AURA_APPLIED" and varParam1 == OMEGA_VECTOR_SPELL_ID then

		-- Update state when Omega Vector is applied
		--self:OutputMessage("Omega vector applied to " .. strDestName);

		if (UnitIsUnit(strDestName, "player")) then
			self.tmNextOmegaDoneSound = nil;

			if self.db.profile.fOmegaGainedWarning then
				self:CheckAndPlaySound("Interface\\AddOns\\WeakAuras\\PowerAurasMedia\\Sounds\\Phone.ogg");
			end
		end

		if self.tbOmegaInfo[strDestName] then
			self.tmOmegaVectorExpiration = select(6, self:FindDebuffById(strDestName, OMEGA_VECTOR_SPELL_ID));
			self.tbOmegaInfo[strDestName].fHasOmegaVector = true;
			self:DeferredChooseNextSoakerAndNotify();
		elseif not self.strNextSoaker or UnitIsDeadOrGhost(self.strNextSoaker) then
			-- Just a failsafe to reset the next soaker in case the UNIT_DIED hook didn't quite work
			self:DeferredChooseNextSoakerAndNotify();
		end

		-- Raid leader should also do raid marks
		if self.iMyRank >= 2 and self.db.profile.fMarkOmegaVector then
			self:DeferredMarkRaid();
		end

	elseif strEventType == "SPELL_CAST_START" and varParam1 == CONTAGION_SPELL_ID then

		if self:ShouldSpreadForContagion() then
			self:CheckAndPlaySound("Sound\\Creature\\HoodWolf\\HoodWolfTransformPlayer01.ogg");
			self.tmContagionStart = GetTime();
			self.iContagionNextSound = 3;
			self.fAnyoneTooClose = false;
		end

	elseif strEventType == "UNIT_DIED" then

		-- Update state when someone dies
		if self.tbOmegaGroup[strDestName] then
			self:DeferredChooseNextSoakerAndNotify();
		end

	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:GetTruncatedClassColoredName
--
--		Gets the name of the unit colored by its class (and truncated down to 8 characters)
--
function SufferMythicVectis:GetTruncatedClassColoredName(strUnit)

	local _, strClass = UnitClass(strUnit);
	local strName = self:GetTruncatedName(strUnit);
	if strClass then
		return RAID_CLASS_COLORS[strClass]:WrapTextInColorCode(strName);
	else
		return strName;
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:GetTruncatedName
--
--		Gets the name of the unit, truncated down to 8 characters
--
function SufferMythicVectis:GetTruncatedName(strUnit)

	local strName = UnitName(strUnit) or strUnit;

	if strlen(strName) > 8 then
		return strsub(strName, 1, 8);
	end

	return strName;

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:OutputMessage
--
--		Prints a message, only if the options permit it.
--
function SufferMythicVectis:OutputMessage(strMsg)

	if (self.db.profile.fEnableOutputMessages) then
		DEFAULT_CHAT_FRAME:AddMessage("|cff7fff7fSMV|r: " .. tostring(strMsg));
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:CheckAndPlaySound
--
--		Plays a sound, only if the options permit it.
--
function SufferMythicVectis:CheckAndPlaySound(strFile)

	if (self.db.profile.fEnableSound) then
		local strChannel = "SFX";
		if (self.db.profile.fIgnoreMute) then
			strChannel = "MASTER";
		end

		PlaySoundFile(strFile, strChannel);
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:FindDebuffById
--
--		Returns the UnitAura result for the given spellId
--
function SufferMythicVectis:FindDebuffById(strUnit, iSpellIdToFind)
	for i = 1, 255 do
		local strName, _, _, _, _, _, _, _, _, iSpellId = UnitAura(strUnit, i, "HARMFUL")

		if not strName then
			return
		end

		if iSpellIdToFind == iSpellId then
			return UnitAura(strUnit, i, "HARMFUL")
		end
	end
end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:GetLingeringInfectionCount
--
--		Gets the stack count of Lingering Infection
--
function SufferMythicVectis:GetLingeringInfectionCount(strUnit)

	if UnitIsVisible(strUnit) then
		strName, _, iStacks = self:FindDebuffById(strUnit, LINGERING_INFECTION_SPELL_ID);
		if strName then
			return iStacks or 1;
		end
	end

	return 0;

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:RefreshGroupLingeringInfectionStacks
--
--		Refreshes Lingering Infection stack counts for your entire group
--
function SufferMythicVectis:RefreshGroupLingeringInfectionStacks()

	for i, strName in ipairs(self.tbOmegaGroup) do
		self.tbOmegaInfo[strName].iStacks = self:GetLingeringInfectionCount(strName);
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:GetOmegaGroup
--
--		Gets all the non-tank members of your group and their info map
--
function SufferMythicVectis:GetOmegaGroup()

	local tbOmegaGroup = {};
	local tbOmegaInfo = {};

	-- First find the player in the raid
	self.iMyGroup = -1;
	for i = 1, 40 do
		local strName, iRank, iGroup = GetRaidRosterInfo(i);

		if strName and UnitIsVisible(strName) and strName == self.strPlayerName then
			self.iMyGroup = iGroup;
			self.iMyRank = iRank;
			break;
		end
	end

	--self:OutputMessage("Group number is " .. self.iMyGroup);

	-- Next add all the player's non-tank groupmates
	for i = 1, 40 do
		local strName, _, iGroup, _, _, _, _, _, _, _, _, combatRole = GetRaidRosterInfo(i);

		if iGroup == self.iMyGroup and UnitIsVisible(strName) and combatRole ~= "TANK" then
			--self:OutputMessage("Group member: " .. strName .. " #" .. i .. " " .. combatRole);

			table.insert(tbOmegaGroup, strName);

			tbOmegaInfo[strName] =
			{
				fHasOmegaVector = false,
				iStacks = 0,
				iPosition = i
			};
		end
	end

	return tbOmegaGroup, tbOmegaInfo;
end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:CreateTextFrame
--
--		Generate the text frame to show
--
function SufferMythicVectis:CreateTextFrame()

	self.textFrame = CreateFrame("Frame",nil,UIParent);
	self.textFrame:SetSize(300, 204);

	if self.db.profile.iFrameLeft and self.db.profile.iFrameTop then
		self.textFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.db.profile.iFrameLeft, self.db.profile.iFrameTop);
	else
		self.textFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	end

	self.textFrame:EnableMouse(true);
	self.textFrame:SetMovable(true);
	self.textFrame:RegisterForDrag("LeftButton");
	self.textFrame:SetScript("OnDragStart", function(self)
		if self:IsMovable() then
			self:StartMoving()
		end
	end);
	self.textFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SufferMythicVectis.db.profile.iFrameLeft = self:GetLeft()
		SufferMythicVectis.db.profile.iFrameTop = self:GetTop()
	end);
	self.textFrame:SetFrameStrata("HIGH");
	self.textFrame:Hide();

	self.textFrame.text = self.textFrame:CreateFontString(nil,"ARTWORK");
	self.textFrame.text:SetFont(GameFontNormal:GetFont(), 24, "OUTLINE");
	self.textFrame.text:SetPoint("TOPLEFT",5,-5);
	self.textFrame.text:SetPoint("BOTTOMRIGHT",-5,5);
	self.textFrame.text:SetJustifyH("LEFT");
	self.textFrame.text:SetJustifyV("TOP");
	self.textFrame.text:SetText(INITIAL_FRAME_TEXT);

	self.textFrame.background = self.textFrame:CreateTexture(nil, "BACKGROUND");
	self.textFrame.background:SetColorTexture(0, 0, 0, 0.5);
	self.textFrame.background:SetAllPoints();

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:ToggleFrameVisibility
--
--		Toggle the visibility of the frame so it can be moved around
--
function SufferMythicVectis:ToggleFrameVisibility()

	if not self.textFrame then
		self:CreateTextFrame();
		self.textFrame:Show();
	elseif self.textFrame:IsShown() then
		self.textFrame:Hide();
	else
		self.textFrame:Show();
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:GetDisplayText
--
--		Generate the text to display
--
function SufferMythicVectis:GetDisplayText()

	if not self.strNextSoaker then
		return INITIAL_FRAME_TEXT;
	end

	local strSpread = "";
	local strDuration = "";
	local strNextPlayer = "";
	local strSeperator = "";
	local tmNow = GetTime();

	if self.db.profile.fShowSpread then
		if not self.tmContagionStart then
			strSpread = "|cFF666666Spread: Not yet|r";
		elseif self.fAnyoneTooClose then
			strSpread = string.format("|cFFFF0000Spread: MORE! %ds|r", math.ceil(self.tmContagionStart + 6 - tmNow));
		else
			strSpread = string.format("|cFF12BC00Spread: OK! %ds|r", math.ceil(self.tmContagionStart + 6 - tmNow));
		end
	end

	if self.db.profile.fShowNext then
		strNextPlayer = self:GetTruncatedClassColoredName(self.strNextSoaker) .. " Next";
	end

	if self.db.profile.fShowNext and self.db.profile.fShowDuration then
		strSeperator = ": ";
	end

	if self.db.profile.fShowDuration then
		if not self.tmOmegaVectorExpiration or tmNow > self.tmOmegaVectorExpiration then
			strDuration = ""; 
			strSeperator = "";
		else
			strDuration = math.floor(self.tmOmegaVectorExpiration - tmNow) .. "s";
		end
	end

	local result = strNextPlayer .. strSeperator .. strDuration .. "\n" .. strSpread .. "\n\n";
	for i, strSoaker in ipairs(self.tbOmegaGroup) do

		local strHighlightColor = nil;
		if self.tbOmegaInfo[strSoaker].fHasOmegaVector then
			strHighlightColor = "FFFF0000";
		elseif UnitIsDeadOrGhost(strSoaker) then
			strHighlightColor = "FF666666";
		elseif self.strNextSoaker == strSoaker then
			strHighlightColor = "FF12BC00";
		end

		--for j = 1, 5 do
		if strHighlightColor then
			result = string.format("%s|c%s%s: %s|r\n", result, strHighlightColor, self:GetTruncatedName(self.tbOmegaGroup[i]), self.tbOmegaInfo[strSoaker].iStacks)
		else
			result = string.format("%s%s: %s\n", result, self:GetTruncatedClassColoredName(self.tbOmegaGroup[i]), self.tbOmegaInfo[strSoaker].iStacks);
		end
		--end
	end

	return result;

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:DeferredChooseNextSoakerAndNotify
--
--		Delay queue a ChooseNextSoakerAndNotify call.  This will give a little time for more
--		Omega Vectors to hop before deciding.  However, actual logs indicate that the hops can
--		be up to 2 seconds apart, and will get completely out of sync if a player dies.
--
function SufferMythicVectis:DeferredChooseNextSoakerAndNotify()

	if not self.fChooseNextSoakerAndNotifyQueued then
		local lambda = function()
			self.fChooseNextSoakerAndNotifyQueued = false;
			self:ChooseNextSoaker();
			self:NotifyIfNextSoaker();
		end

		C_Timer.After(0.3, lambda);
		self.fChooseNextSoakerAndNotifyQueued = true;
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:ChooseNextSoaker
--
--		Determine who is next to soak
--
function SufferMythicVectis:ChooseNextSoaker()

	-- Break out if the encounter has ended
	if self.iEncounterId ~= VECTIS_ENCOUNTER_ID then
		return;
	end

	self:RefreshGroupLingeringInfectionStacks();

	-- Choose the next soaker amongst the valid targets
	for i, soaker in ipairs(self.tbOmegaGroup) do
		if not self.tbOmegaInfo[soaker].fHasOmegaVector and UnitExists(soaker) and not UnitIsDeadOrGhost(soaker) then
			if not self.strNextSoaker or
				self.tbOmegaInfo[self.strNextSoaker].fHasOmegaVector or
				self.tbOmegaInfo[soaker].iStacks < self.tbOmegaInfo[self.strNextSoaker].iStacks or
				(self.tbOmegaInfo[soaker].iStacks == self.tbOmegaInfo[self.strNextSoaker].iStacks and self.tbOmegaInfo[soaker].iPosition < self.tbOmegaInfo[self.strNextSoaker].iPosition) then

				self.strNextSoaker = soaker;
			end
		end
	end

end
---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:NotifyIfNextSoaker
--
--		Notify the player if he is soaking next.
--
function SufferMythicVectis:NotifyIfNextSoaker()

	-- Break out if the encounter has ended
	if self.iEncounterId ~= VECTIS_ENCOUNTER_ID then
		return;
	end

	-- Notify the player if he is next at most once every 5 seconds
	if self.strNextSoaker == self.strPlayerName and (not self.tmLastNextNotification or GetTime() - self.tmLastNextNotification > 5) then

		self.tmLastNextNotification = GetTime();

		self:CheckAndPlaySound("Interface\\AddOns\\WeakAuras\\PowerAurasMedia\\Sounds\\Phone.ogg");

		if self.db.profile.fEnableSay then
			SendChatMessage(self.strPlayerName .." next!", "SAY");
		end

	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:ShouldSpreadForContagion
--
--		Returns true if the player should spread for contagion.  (Either has 6 stacks or about to)
--
function SufferMythicVectis:ShouldSpreadForContagion()

	if not self.db.profile.fSpreadWarning then
		return false;
	end

	-- Players only need to spread for contagion on Mythic difficulty
	if self.iDifficultyIndex ~= MYTHIC_RAID_DIFFICULTY then
		return false;
	end

	local iStackCount = self:GetLingeringInfectionCount("player");
	return iStackCount >= 6 or (iStackCount == 5 and self:FindDebuffById("player", OMEGA_VECTOR_SPELL_ID));

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:CheckContagionStatus
--
--		Checks and to see if the player is too close to others and plays a status sound
--		at 3, 4, 5, and 6 seconds after the start of the contagion cast.
--
function SufferMythicVectis:CheckContagionStatus()

	-- Check to see if anyone is too close
	self.fAnyoneTooClose = false;
	if not UnitIsDeadOrGhost("player") then
		for i = 1, 40 do
			local strUnit = "raid" .. i;

			if UnitExists(strUnit) and IsItemInRange(37727, strUnit) and not UnitIsUnit(strUnit, "player") and not UnitIsDeadOrGhost(strUnit) then 
				self.fAnyoneTooClose = true;
				break;
			end
		end
	end

	-- Check if it's time to play a status sound
	local tmNow = GetTime();
	if tmNow >= self.tmContagionStart + self.iContagionNextSound then

		-- End the Contagion sequence before the 7th one plays a sound
		if self.iContagionNextSound >= 7 then

			self.tmContagionStart = nil;
			self.iContagionNextSound = nil;
			self.fAnyoneTooClose = nil;

		else

			self.iContagionNextSound = self.iContagionNextSound + 1;

			if self.fAnyoneTooClose then
				self:CheckAndPlaySound("Interface\\AddOns\\WeakAuras\\Media\\Sounds\\AirHorn.ogg");
			else
				self:CheckAndPlaySound("Interface\\Addons\\WeakAuras\\PowerAurasMedia\\Sounds\\sonar.ogg");
			end

		end
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:CheckMyRaidIcon
--
--		Checks and warns the player if their raid icon is for a different group
--
function SufferMythicVectis:CheckMyRaidIcon()

	local iIcon = GetRaidTargetIndex("player");

	if iIcon and iIcon ~= self.iMyGroup and self:FindDebuffById("player", OMEGA_VECTOR_SPELL_ID) then
		local tmNow = GetTime();

		-- Start the wrong icon timer if it's not started yet
		if not self.tmWrongIconStart then
			self.tmWrongIconStart = tmNow;
		end

		-- If the icon has been wrong for at least 1 second, start notifying the player every 5 seconds
		if tmNow - self.tmWrongIconStart > 1 and (not self.tmLastWrongIconNotification or tmNow - self.tmLastWrongIconNotification > 5) then

			self.tmLastWrongIconNotification = tmNow;

			self:CheckAndPlaySound("Sound\\Doodad\\Goblin_Lottery_Open03.ogg");

			if self.db.profile.fEnableSay then
				SendChatMessage(self.strPlayerName .." move to {rt" .. iIcon .. "}", "SAY");
			end

		end

	else
		-- Reset wrong icon timer
		self.tmWrongIconStart = nil;
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:DeferredMarkRaid
--
--		Delay queue a MarkRaid call.  This will give a little time for more
--		Omega Vectors to hop before deciding.  However, actual logs indicate that the hops can
--		be up to 2 seconds apart, and will get completely out of sync if a player dies.
--
function SufferMythicVectis:DeferredMarkRaid()

	if not self.fMarkRaidQueued then
		local lambda = function()
			self.fMarkRaidQueued = false;
			self:MarkRaid();
		end

		C_Timer.After(0.29, lambda);
		self.fMarkRaidQueued = true;
	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:MarkRaid
--
--		Marks the raiders with Omega Vector.  This algorithm should be better than DBM/BigWigs
--		in that it will prefer to give Group 1 the star, Group 2 the circle, etc...
--
function SufferMythicVectis:MarkRaid()

	local tbIconAssignments = {};
	local tbNeedsIcon = {};

	-- First pass: find raiders with omega vector and try to give them the marker corresponding to
	-- their group (giving precedence to players who already had the right marker)
	for i = 1, 40 do
		local strName, _, iGroup = GetRaidRosterInfo(i);

		-- Does this raider have omega vector?
		if strName and UnitIsVisible(strName) and self:FindDebuffById(strName, OMEGA_VECTOR_SPELL_ID) then
			local iOldIcon = GetRaidTargetIndex(strName);
			local tbEntry = 
			{
				strName = strName,
				iGroup = iGroup,
				iOldIcon = iOldIcon,
			};

			if iGroup <= 4 and not tbIconAssignments[iGroup] then
				-- Try to place the entry in its group
				tbIconAssignments[iGroup] = tbEntry;
			elseif iOldIcon and iOldIcon <= 4 and iGroup == iOldIcon then
				-- Actually, dibs on this icon because I had it first
				table.insert(tbNeedsIcon, tbIconAssignments[iGroup]);
				tbIconAssignments[iGroup] = tbEntry;
			else
				table.insert(tbNeedsIcon, tbEntry);
			end

		end
	end

	-- Second pass: try to give raiders the markers they had before
	for i = #tbNeedsIcon, 1, -1 do

		local tbEntry = tbNeedsIcon[i]

		if tbEntry.iOldIcon and tbEntry.iOldIcon <= 4 and not tbIconAssignments[tbEntry.iOldIcon] then
			tbIconAssignments[tbEntry.iOldIcon] = tbEntry;
			table.remove(tbNeedsIcon, i);
		end

	end

	-- Final pass: just fill in the blanks
	for i = 1, #tbNeedsIcon do
		for j = 1, 4 do
			if not tbIconAssignments[j] then
				tbIconAssignments[j] = tbNeedsIcon[i];
				break;
			end
		end
	end

	-- OK do the markers
	for i = 1, 4 do
		local tbEntry = tbIconAssignments[i]

		if tbEntry and (not tbEntry.iOldIcon or tbEntry.iOldIcon ~= i) then
			SetRaidTarget(tbEntry.strName, i)
		end
	end

end
