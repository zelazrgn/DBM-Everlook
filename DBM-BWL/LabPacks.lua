local mod	= DBM:NewMod("LabPacks", "DBM-BWL", 1)
local L		= mod:GetLocalizedStrings()

local GreaterPolymorphIcon1 = 5
local GreaterPolymorphIcon2 = 3

mod:SetRevision("20200527025231")
mod:SetCreatureID(13996, 12457, 12461, 99999)--99999 to prevent mod from ending combat after one of each talon guard type die. Mod will effectively ALWAYS wipe, but it has disabled stats/reporting so irrelevant
mod:SetModelID(13996)
mod:RegisterCombat("combat")
mod.noStatistics = true
mod:SetUsedIcons(GreaterPolymorphIcon1, GreaterPolymorphIcon2)

mod.vb.numPoly = 0

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 22274",
	"SPELL_AURA_REMOVED 22274"
)

local warningPolymorph	= mod:NewTargetNoFilterAnnounce(22274, 2)
local warnVuln			= mod:NewAnnounce("WarnVulnerable", 1, false)

mod:AddSetIconOption("SetIconOnPolymorph", 22274, false, false, {GreaterPolymorphIcon1, GreaterPolymorphIcon2})
mod:AddBoolOption("WarnGreaterPolymorphChat", false)
mod:AddNamePlateOption("NPAuraOnVulnerable", 22277)

local vulnerabilities = {
	-- [guid] = school
}
--redudnant, but fuck it, thie code in this mod is already shit
local lastAnnounce = {
	-- [guid] = school
}

--Constants
local vulnMobs = {
	[12461] = true,--"Death Talon Overseer"
}

-- https://wow.gamepedia.com/COMBAT_LOG_EVENT
local spellInfo = {
	[2] =	{"Holy",	{r=255, g=230, b=128},	"135924"},-- Smite
	[4] =	{"Fire",	{r=255, g=128, b=0},	"135808"},-- Pyroblast
	[8] =	{"Nature",	{r=77, g=255, b=77},	"136006"},-- Wrath
	[16] =	{"Frost",	{r=128, g=255, b=255},	"135846"},-- Frostbolt
	[32] =	{"Shadow",	{r=128, g=128, b=255},	"136197"},-- Shadow Bolt
	[64] =	{"Arcane",	{r=255, g=128, b=255},	"136096"},-- Arcane Missiles
}

local vulnSpells = {
	--No Holy?
	[22277] = 4,--Fire
	[22280] = 8,--Nature
	[22278] = 16,--Frost
	[22279] = 32,--Shadow
	[22281] = 64,--Arcane
}

--Local Functions
-- in theory this should only alert on a new vulnerability on your target or when you change target
local function update_vulnerability(self)
	local target = UnitGUID("target")
	local spellSchool = vulnerabilities[target]
	local cid = self:GetCIDFromGUID(target)
	if not spellSchool or not vulnMobs[cid] then
		return
	end

	local info = spellInfo[spellSchool]
	if not info then return end
	local name = L[info[1]] or info[1]

	if not lastAnnounce[target] or lastAnnounce[target] ~= name then
		warnVuln.icon = info[3]
		warnVuln:Show(name)
		lastAnnounce[target] = name
		if self.Options.NPAuraOnVulnerable then
			DBM.Nameplate:Hide(true, target, 22277, 135924)
			DBM.Nameplate:Hide(true, target, 22277, 135808)
			DBM.Nameplate:Hide(true, target, 22277, 136006)
			DBM.Nameplate:Hide(true, target, 22277, 135846)
			DBM.Nameplate:Hide(true, target, 22277, 136197)
			DBM.Nameplate:Hide(true, target, 22277, 136096)
			DBM.Nameplate:Show(true, target, 22277, tonumber(info[3]))
		end
	end
end

local function check_spell_damage(self, guid, amount, spellSchool, critical)
	local cid = self:GetCIDFromGUID(guid)
	if cid ~= 12460 and cid ~= 12461 then
		return
	end
	if amount > (critical and 1600 or 800) then
		if not vulnerabilities[guid] or vulnerabilities[guid] ~= spellSchool then
			vulnerabilities[guid] = spellSchool
			update_vulnerability(self)
		end
	end
end

local function check_target_vulns(self)
	local target = UnitGUID("target")
	local cid = self:GetCIDFromGUID(target)
	if not vulnMobs[cid] then
		return
	end

	local spellId = select(10, DBM:UnitBuff("target", 22277, 22280, 22278, 22279, 22281)) or 0
	local vulnSchool = vulnSpells[spellId]
	if vulnSchool then
		return check_spell_damage(self, target, 10000, vulnSchool)
	end
end

function mod:OnCombatStart()
	self.vb.numPoly = 0

	table.wipe(vulnerabilities)
	if self.Options.WarnVulnerable then--Don't register high cpu combat log events if option isn't enabled
		self:RegisterShortTermEvents(
			"SPELL_DAMAGE",
			"PLAYER_TARGET_CHANGED"
		)
		check_target_vulns(self)
		if self.Options.NPAuraOnVulnerable then
			DBM:FireEvent("BossMod_EnableHostileNameplates")
		end
	end
end

function mod:OnCombatEnd()
	table.wipe(vulnerabilities)
	self:UnregisterShortTermEvents()
	if self.Options.NPAuraOnVulnerable  then
		DBM.Nameplate:Hide(true, nil, nil, nil, true, true)--isGUID, unit, spellId, texture, force, isHostile, isFriendly
	end
end

function mod:SPELL_DAMAGE(_, _, _, _, destGUID, _, _, _, _, _, spellSchool, amount, _, _, _, _, _, critical)
	check_spell_damage(self, destGUID, amount, spellSchool, critical)
end

function mod:PLAYER_TARGET_CHANGED()
	check_target_vulns(self)
end

do
	local GreaterPolymorph = DBM:GetSpellInfo(22274)

	local icon = nil

	function mod:SPELL_AURA_APPLIED(args)
		if args.spellName == GreaterPolymorph and args:IsDestTypePlayer() then
			self.vb.numPoly = self.vb.numPoly + 1
			warningPolymorph:Show(args.destName)
			if self.Options.SetIconOnPolymorph then
				icon = self.vb.numPoly == 1 and GreaterPolymorphIcon1 or GreaterPolymorphIcon2
				self:SetIcon(args.destName, icon)
			end
			if self.Options.WarnGreaterPolymorphChat then
				SendChatMessage("DISPEL: " .. args.destName .. "!", "RAID")
			end
		end
	end

	function mod:SPELL_AURA_REMOVED(args)
		self.vb.numPoly = self.vb.numPoly - 1
		if args.spellName == GreaterPolymorph and args:IsDestTypePlayer() then
			if self.Options.SetIconOnPolymorph then
				local target = args.destName
				local uId = DBM:GetRaidUnitId(target)
				if uId or UnitExists(target) then
					uId = uId or target
					local currentIcon = self:GetIcon(uId)
					if currentIcon == GreaterPolymorphIcon1 or currentIcon == GreaterPolymorphIcon2 then
						if self.iconRestore[uId] then
							self:SetIcon(target, self.iconRestore[uId])
							self.iconRestore[uId] = nil
						else
							self:RemoveIcon(target)
						end
					end
				end
			end
		end
	end
end
