----------------------------
--      Constants         --
----------------------------

local _

-- Test values
local VECTIS_ENCOUNTER_ID = 1721;
local OMEGA_VECTOR_SPELL_ID = 159113;
local LINGERING_INFECTION_SPELL_ID = 159386;

-- Actual vectis values
-- local VECTIS_ENCOUNTER_ID = 2134;
-- local OMEGA_VECTOR_SPELL_ID = 265129;
-- local LINGERING_INFECTION_SPELL_ID = 265127;

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

	-- Build the default settings array
	local DEFAULTS = {
		profile = {
			fEnableOutputMessages = true,
			fEnableSound = true,
			fEnableSay = true,
			fIgnoreMute = true,
			fShowNext = true,
			fShowDuration = true,
		}
	};
	self.db = LibStub("AceDB-3.0"):New("SufferMythicVectisDB", DEFAULTS, "default");

	-- Init stuff so we don't get nil errors
	self.iEncounterId = 0;
	self.iWrongIconCounter = 0;
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

	if self.textFrame then
		self.textFrame.text:SetText(self:GetDisplayText());
	end

	self:CheckMyRaidIcon();

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:ENCOUNTER_START
--
--		Handler for encounter starting
--
function SufferMythicVectis:ENCOUNTER_START(strEvent, arg1)

	self.iEncounterId = tonumber(arg1);

	if self.iEncounterId == VECTIS_ENCOUNTER_ID then

		self:OutputMessage("Vectis encounter started");

		self.tmOmegaVectorExpiration = nil;
		self.tmLastNextNotification = nil;
		self.tmLastWrongIconNotification = nil;
		self.tbOmegaGroup, self.tbOmegaInfo = self:GetOmegaGroup();
		self.nextSoaker = nil;

		self:ChooseNextSoaker();

		if not self.textFrame then
			self:CreateTextFrame();
		end

		self.textFrame:Show();

		if not self.ticker then
			self.ticker = C_Timer.NewTicker(0.2, function() self:OnTick() end);
		end

	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:ENCOUNTER_END
--
--		Handler for encounter ending
--
function SufferMythicVectis:ENCOUNTER_END(strEvent, arg1)

	self:OutputMessage("Vectis encounter ended");
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

		if self.tbOmegaInfo[strDestName] then
			self.tbOmegaInfo[strDestName].fHasOmegaVector = false;
		end

	elseif strEventType == "SPELL_AURA_APPLIED" and varParam1 == OMEGA_VECTOR_SPELL_ID then

		-- Update state when Omega Vector is applied
		--self:OutputMessage("Omega vector applied to " .. strDestName);

		if self.tbOmegaInfo[strDestName] then
			self.tmOmegaVectorExpiration = select(6, self:FindDebuffById(strDestName, OMEGA_VECTOR_SPELL_ID));
			self.tbOmegaInfo[strDestName].fHasOmegaVector = true;
			self:DeferredChooseNextSoakerAndNotify();
		end

		-- Raid leader should also do raid marks
		if self.iMyRank >= 2 then
			self:DeferredMarkRaid();
		end

	elseif strEventType == "UNIT_DIED" then

		-- Update state when someone dies
		if self.tbOmegaGroup[strDestName] then
			self:DeferredChooseNextSoakerAndNotify();
		end

	end

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:GetClassColoredName
--
--		Gets the name of the unit colored by its class
--
function SufferMythicVectis:GetClassColoredName(unit)

	local _, class = UnitClass(unit);
	if class then
		return RAID_CLASS_COLORS[class]:WrapTextInColorCode(UnitName(unit));
	else
		return unit;
	end
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
	self.textFrame:SetSize(300, 180);

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
	self.textFrame.text:SetText(" ");

	self.textFrame.background = self.textFrame:CreateTexture(nil, "BACKGROUND");
	self.textFrame.background:SetColorTexture(0, 0, 0, 0.5);
	self.textFrame.background:SetAllPoints();

end

---------------------------------------------------------------------------------------------------
--	SufferMythicVectis:GetDisplayText
--
--		Generate the text to display
--
function SufferMythicVectis:GetDisplayText()

	if not self.nextSoaker then
		return ""
	end

	local duration = ""
	local nextPlayer = ""
	local seperator = ""
	local now = GetTime()

	self:RefreshGroupLingeringInfectionStacks();

	if self.db.profile.fShowNext then
		nextPlayer = self:GetClassColoredName(self.nextSoaker) .. " Next"
	end

	if self.db.profile.fShowNext and self.db.profile.fShowDuration then
		seperator = ": "
	end

	if self.db.profile.fShowDuration then
		if not self.tmOmegaVectorExpiration or now > self.tmOmegaVectorExpiration then
			duration = ""; 
			seperator = "";
		else
			duration = math.floor(self.tmOmegaVectorExpiration - now) .. "s";
		end
	end

	local result = nextPlayer .. seperator .. duration .. "\n\n";
	for i,soaker in ipairs(self.tbOmegaGroup) do
		if self.tbOmegaInfo[soaker].fHasOmegaVector then
			result = string.format("%s|c%s%s: %s|r\n", result, "FFFF0000", self.tbOmegaGroup[i], self.tbOmegaInfo[soaker].iStacks)
		elseif UnitIsDeadOrGhost(soaker) then
			result = string.format("%s|c%s%s: %s|r\n", result, "FF666666", self.tbOmegaGroup[i], self.tbOmegaInfo[soaker].iStacks)
		else
			result = string.format("%s%s: %s\n", result, self:GetClassColoredName(self.tbOmegaGroup[i]), self.tbOmegaInfo[soaker].iStacks)
		end
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
			if not self.nextSoaker or
				self.tbOmegaInfo[self.nextSoaker].fHasOmegaVector or
				self.tbOmegaInfo[soaker].iStacks < self.tbOmegaInfo[self.nextSoaker].iStacks or
				(self.tbOmegaInfo[soaker].iStacks == self.tbOmegaInfo[self.nextSoaker].iStacks and self.tbOmegaInfo[soaker].iPosition < self.tbOmegaInfo[self.nextSoaker].iPosition) then

				self.nextSoaker = soaker;
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
	if self.nextSoaker == self.strPlayerName and (not self.tmLastNextNotification or GetTime() - self.tmLastNextNotification > 5) then

		self.tmLastNextNotification = GetTime();

		if self.db.profile.fEnableSound then
			self:CheckAndPlaySound("Interface\\AddOns\\WeakAuras\\PowerAurasMedia\\Sounds\\Phone.ogg");
		end

		if self.db.profile.fEnableSay then
			SendChatMessage(self.strPlayerName .." next!", "SAY");
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
		-- Increment counter
		self.iWrongIconCounter = self.iWrongIconCounter + 1;

		-- If the icon has been wrong for at least 1 second, start notifying the player every 5 seconds
		if self.iWrongIconCounter > 5 and (not self.tmLastWrongIconNotification or GetTime() - self.tmLastWrongIconNotification > 5) then

			self.tmLastWrongIconNotification = GetTime();

			if self.db.profile.fEnableSound then
				self:CheckAndPlaySound("Sound\\Doodad\\Goblin_Lottery_Open03.ogg");
			end

			if self.db.profile.fEnableSay then
				SendChatMessage(self.strPlayerName .." move to {rt" .. iIcon .. "}", "SAY");
			end

		end

	else
		-- Reset counter
		self.iWrongIconCounter = 0;
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
