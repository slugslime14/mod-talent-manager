-- TalentManager: saved talent specs for the mod-talent-manager server module.
-- Server <-> client messages are addon whispers to yourself, "CMD:payload", prefix TMGR.
-- The talent trees are read from the client's own data (GetTalentInfo and friends). A spec being edited is a
-- "draft": ranks per (tree, talent index). It can be written as the Wowhead / playerbots link format.
-- Saved specs live on the server, per character; the addon keeps the last list it was sent (TM.specs).
--
-- The window shows one character at a time: you, or one of your online altbots (TM.char). Everything about the
-- shown character is in the fields listed in STATE_KEYS; the other characters' copies wait in TM.states. Requests
-- about an altbot are sent as "@<guid>|CMD:payload" and the server tags its answers the same way. An altbot's trees,
-- live talents and glyphs come from the server, since the client only knows your own.

TalentManager = {
    PREFIX = "TMGR",
    PROTOCOL = 6,
    TIER_POINTS = 5,        -- points needed in a tree per row (PLAYER_TALENTS_PER_TIER)
    GLYPH_SLOTS = 6,
    info = nil,             -- the server's INFO: { version, maxSpecs, points, activeGroup, groups, level, class }
    trees = nil,            -- the class's talent trees, see LoadTrees
    -- The build shown in the window: { ranks = { [tree] = { [index] = rank } }, glyphs = { [socket] = id },
    -- source = "live" | "new" | "spec", specId, dirty }. "new" is a build not saved yet (New, Import).
    draft = nil,
    specs = {},             -- saved specs by list order: { id, sort, name, talents (link), glyphs, draft }
    specById = {},
    loaded = {},            -- [talent group] = id of the spec last loaded into it
    -- The class's glyphs from the server: { id, spellId, type (1 major, 2 minor, as GetGlyphSocketInfo), itemId,
    -- icon, known, name }, sorted by name.
    glyphs = nil,
    glyphById = {},
    glyphBySpell = {},
    char = nil,             -- the altbot shown: { guid, name, class, level }; nil for yourself
    live = nil,             -- an altbot's live build from the server: { talents (link), glyphs = { [socket] = id } }
    ready = nil,            -- an altbot's state got its spec list (and so its trees and live build before it)
    listeners = {},

    -- Not per character:
    characters = {},        -- you and your online altbots, from CHARS: { guid, name, class, level }, you first
    selfGuid = nil,
    states = {},            -- the characters not shown: ["self"] or [guid] = their STATE_KEYS fields
    pending = nil,          -- the guid of an altbot asked for, shown once its data is in
    classTrees = {},        -- [class id] = trees the server sent
    clientTrees = nil,      -- your class's trees from the client
}

local TM = TalentManager

-- The fields that belong to the shown character.
local STATE_KEYS = { "char", "info", "trees", "draft", "specs", "specById", "loaded", "glyphs",
    "glyphById", "glyphBySpell", "maxSpecs", "listed", "pendingSelect", "live", "ready" }

TM.CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK",
    nil, "DRUID" }

-- Tree names, backgrounds and icons by class id and tab, from TalentTab.dbc (the client only tells you your own).
local TREE_INFO = {
    [1] = { { "Arms", "WarriorArms", "Ability_Rogue_Eviscerate" },
        { "Fury", "WarriorFury", "Ability_Warrior_InnerRage" },
        { "Protection", "WarriorProtection", "INV_Shield_06" } },
    [2] = { { "Holy", "PaladinHoly", "Spell_Holy_HolyBolt" }, { "Protection", "PaladinProtection",
        "Spell_Holy_DevotionAura" }, { "Retribution", "PaladinCombat", "Spell_Holy_AuraOfLight" } },
    [3] = { { "Beast Mastery", "HunterBeastMastery", "Ability_Hunter_BeastTaming" },
        { "Marksmanship", "HunterMarksmanship", "Ability_Marksmanship" },
        { "Survival", "HunterSurvival", "Ability_Hunter_SwiftStrike" } },
    [4] = { { "Assassination", "RogueAssassination", "Ability_Rogue_Eviscerate" }, { "Combat", "RogueCombat",
        "Ability_BackStab" }, { "Subtlety", "RogueSubtlety", "Ability_Stealth" } },
    [5] = { { "Discipline", "PriestDiscipline", "Spell_Holy_WordFortitude" }, { "Holy", "PriestHoly",
        "Spell_Holy_GuardianSpirit" }, { "Shadow", "PriestShadow", "Spell_Shadow_ShadowWordPain" } },
    [6] = { { "Blood", "DeathKnightBlood", "Spell_Deathknight_BloodPresence" }, { "Frost", "DeathKnightFrost",
        "Spell_Deathknight_FrostPresence" }, { "Unholy", "DeathKnightUnholy", "Spell_Deathknight_UnholyPresence" } },
    [7] = { { "Elemental", "ShamanElementalCombat", "Spell_Nature_Lightning" }, { "Enhancement", "ShamanEnhancement",
        "Spell_Nature_LightningShield" }, { "Restoration", "ShamanRestoration", "Spell_Nature_MagicImmunity" } },
    [8] = { { "Arcane", "MageArcane", "Spell_Holy_MagicalSentry" }, { "Fire", "MageFire", "Spell_Fire_FireBolt02" },
        { "Frost", "MageFrost", "Spell_Frost_FrostBolt02" } },
    [9] = { { "Affliction", "WarlockCurses", "Spell_Shadow_DeathCoil" }, { "Demonology", "WarlockSummoning",
        "Spell_Shadow_Metamorphosis" }, { "Destruction", "WarlockDestruction", "Spell_Shadow_RainOfFire" } },
    [11] = { { "Balance", "DruidBalance", "Spell_Nature_StarFall" }, { "Feral Combat", "DruidFeralCombat",
        "Ability_Racial_BearForm" }, { "Restoration", "DruidRestoration", "Spell_Nature_HealingTouch" } },
}

local DEFAULTS = {
    point = nil,            -- the window's position: { point, x, y }
}

-- ---------------------------------------------------------------------------------------------------------------
-- Events between the files

function TM:On(event, callback)
    self.listeners[event] = self.listeners[event] or {}
    table.insert(self.listeners[event], callback)
end

-- A listener that fails is reported (the game's error handler) and the others still run. While a message about a
-- character that isn't shown is handled (TM.quiet), no events go out: the window shows someone else.
function TM:Fire(event, ...)
    if self.quiet then
        return
    end
    for _, callback in ipairs(self.listeners[event] or {}) do
        local ok, err = pcall(callback, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

function TM:Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4e96f7[Talents]|r " .. text)
end

-- A message about the character the current state belongs to: an altbot's start with its name.
function TM:Say(text)
    local name = self.char and self.char.name
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    if name and plain:sub(1, #name) ~= name then
        text = name .. ": " .. text
    end
    self:Print(text)
end

-- "your character" or the altbot's name, for tooltips.
function TM:Subject()
    return self.char and self.char.name or "your character"
end

-- "your bags" or "<altbot>'s bags".
function TM:Bags()
    return self.char and (self.char.name .. "'s bags") or "your bags"
end

-- ---------------------------------------------------------------------------------------------------------------
-- Characters: you or an altbot

local function StateKey()
    return TM.char and TM.char.guid or "self"
end
TM.StateKey = StateKey

function TM:CharacterByGuid(guid)
    for _, character in ipairs(self.characters) do
        if character.guid == guid then
            return character
        end
    end
end

local function SaveState()
    local state = {}
    for _, key in ipairs(STATE_KEYS) do
        state[key] = TM[key]
    end
    TM.states[StateKey()] = state
end

local function LoadState(key)
    local state = TM.states[key]
    if not state then
        local char = nil
        if key ~= "self" then
            char = TM:CharacterByGuid(key) or { guid = key, name = "#" .. key, class = 0, level = 0 }
        end
        state = { char = char, specs = {}, specById = {}, loaded = {}, glyphById = {}, glyphBySpell = {} }
    end
    for _, k in ipairs(STATE_KEYS) do
        TM[k] = state[k]
    end
end

-- Runs fn with the state of character `key` ("self" or a guid) in place, without drawing anything if that isn't
-- the shown character.
function TM:WithState(key, fn, ...)
    if key == StateKey() then
        return fn(...)
    end
    local shown, quiet = StateKey(), self.quiet
    SaveState()
    LoadState(key)
    self.quiet = true
    local ok, err = pcall(fn, ...)
    SaveState()
    LoadState(shown)
    self.quiet = quiet
    if not ok then
        geterrorhandler()(err)
    end
end

local function SwitchTo(key)
    TM.pending = nil
    if key == StateKey() then
        return
    end
    SaveState()
    LoadState(key)
    if not TM.draft and next(TM:LoadTrees()) then
        TM.draft = TM:LiveDraft()
    end
    TM:Fire("CHARACTER")
    TM:Fire("DRAFT")
end

local function PlayerClassId()
    local _, token = UnitClass("player")
    for id, t in pairs(TM.CLASS_TOKENS) do
        if t == token then
            return id
        end
    end
end

-- Shows you (guid nil or your own) or an altbot in the window. An altbot seen before shows at once and its data is
-- asked for again; one seen for the first time shows once the server has sent it all.
function TM:ShowCharacter(guid)
    if guid == self.selfGuid then
        guid = nil
    end
    if not guid then
        self.pending = nil
        SwitchTo("self")
        return
    end
    if guid == StateKey() then
        return
    end
    local character = self:CharacterByGuid(guid)
    self:WithState(guid, function()
        if character then
            TM.char = character
        end
        TM.listed = true
        TM:Send("HELLO")
        if not TM.trees then
            if TM.classTrees[TM.char.class] then
                TM.trees = TM.classTrees[TM.char.class]
            elseif TM.char.class == PlayerClassId() then
                TM.trees = TM:ClientTrees()
            else
                TM:Send("TREES")
            end
        end
        TM:Send("LIVE")
        TM:Send("GLYPHS")
        TM:Send("LIST")
    end)
    local state = self.states[guid]
    if state and state.ready then
        SwitchTo(guid)
    else
        self.pending = guid
        self.pendingSince = GetTime()
        self:Fire("CHARACTER")
    end
end

-- The talent group, group count, point total and glyph sockets of the shown character.
function TM:ActiveGroup()
    if self.char then
        return self.info and self.info.activeGroup or 1
    end
    return GetActiveTalentGroup(false, false)
end

function TM:NumGroups()
    if self.char then
        return self.info and self.info.groups or 1
    end
    return GetNumTalentGroups(false, false)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Talent trees

-- Each tree: { index, name, icon, background, talents = { [index] = talent }, order = { talent, ... } (row, then
-- column: the link order), maxTier }.
-- Each talent: { tree, index, id, name, icon, tier, column, maxRank, prereqs = { talent, ... }, dependents = { ... } }.
local function CollectPrereqs(...)
    local list = {}
    -- The client returns tier, column, isLearnable, isPreviewLearnable for each prerequisite.
    for i = 1, select("#", ...), 4 do
        local tier, column = select(i, ...)
        if tier and column then
            list[#list + 1] = { tier = tier, column = column }
        end
    end
    return list
end

-- The shown character's trees. An altbot's come from the server (TREE messages), unless it's your class. Until they
-- are in this is an empty list.
function TM:LoadTrees()
    if self.trees then
        return self.trees
    end
    if self.char then
        self.trees = self.classTrees[self.char.class]
            or (self.char.class == PlayerClassId() and self:ClientTrees()) or nil
        return self.trees or {}
    end
    self.trees = self:ClientTrees()
    return self.trees
end

-- Your class's trees from the client's own data.
function TM:ClientTrees()
    if self.clientTrees then
        return self.clientTrees
    end

    local trees = {}
    for t = 1, GetNumTalentTabs(false, false) do
        local name, icon, _, background = GetTalentTabInfo(t, false, false)
        local tree = { index = t, name = name, icon = icon, background = background, talents = {}, order = {},
            maxTier = 0 }
        local at = {}
        for i = 1, GetNumTalents(t, false, false) do
            local talentName, talentIcon, tier, column, _, maxRank = GetTalentInfo(t, i, false, false)
            if talentName then
                local link = GetTalentLink(t, i, false, false)
                local talent = {
                    tree = t, index = i, name = talentName, icon = talentIcon, tier = tier, column = column,
                    maxRank = maxRank, id = link and tonumber(link:match("talent:(%d+)")),
                    prereqAt = CollectPrereqs(GetTalentPrereqs(t, i, false, false)),
                    prereqs = {}, dependents = {},
                }
                tree.talents[i] = talent
                tree.order[#tree.order + 1] = talent
                at[tier] = at[tier] or {}
                at[tier][column] = talent
                if tier > tree.maxTier then
                    tree.maxTier = tier
                end
            end
        end

        for _, talent in ipairs(tree.order) do
            for _, pos in ipairs(talent.prereqAt) do
                local prereq = at[pos.tier] and at[pos.tier][pos.column]
                if prereq then
                    talent.prereqs[#talent.prereqs + 1] = prereq
                    prereq.dependents[#prereq.dependents + 1] = talent
                end
            end
        end

        table.sort(tree.order, function(a, b)
            if a.tier ~= b.tier then
                return a.tier < b.tier
            end
            return a.column < b.column
        end)
        trees[t] = tree
    end

    self.clientTrees = trees
    return trees
end

-- Trees from the server's TREE entries (in link order). Names and pictures come from TREE_INFO, talent names and
-- icons from the talents' first rank spells.
local function ServerTrees(classId, entries)
    local trees, byId = {}, {}
    local info = TREE_INFO[classId] or {}
    for t = 1, 3 do
        local i = info[t] or {}
        trees[t] = { index = t, name = i[1] or ("Tree " .. t), background = i[2],
            icon = i[3] and ("Interface\\Icons\\" .. i[3]) or "Interface\\Icons\\INV_Misc_QuestionMark",
            talents = {}, order = {}, maxTier = 0 }
    end
    for _, e in ipairs(entries) do
        local tree = trees[e.tree]
        if tree then
            local index = #tree.order + 1
            local name, _, icon = GetSpellInfo(e.spell)
            local talent = {
                tree = e.tree, index = index, id = e.id, name = name or ("Talent " .. e.id),
                icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark", tier = e.row + 1, column = e.column + 1,
                maxRank = e.maxRank, prereqs = {}, dependents = {}, dependsOn = e.dependsOn,
                dependsOnRank = e.dependsOnRank,
            }
            tree.talents[index] = talent
            tree.order[index] = talent
            byId[e.id] = talent
            if talent.tier > tree.maxTier then
                tree.maxTier = talent.tier
            end
        end
    end
    for _, tree in ipairs(trees) do
        for _, talent in ipairs(tree.order) do
            local prereq = talent.dependsOn ~= 0 and byId[talent.dependsOn]
            if prereq then
                talent.prereqs[1] = prereq
                talent.prereqRanks = { talent.dependsOnRank + 1 }
                prereq.dependents[#prereq.dependents + 1] = talent
            end
        end
    end
    return trees
end

-- Points a talent needs in its k-th prerequisite: the server's rule (DependsOnRank + 1) when known, else the
-- prerequisite's top rank, as the stock talent frame shows it.
function TM:PrereqNeed(talent, k)
    return talent.prereqRanks and talent.prereqRanks[k] or talent.prereqs[k].maxRank
end

-- ---------------------------------------------------------------------------------------------------------------
-- Drafts and the game's talent rules

function TM:NewDraft()
    local draft = { ranks = {}, glyphs = {}, source = "new", dirty = false }
    for t in ipairs(self:LoadTrees()) do
        draft.ranks[t] = {}
    end
    for socket = 1, self.GLYPH_SLOTS do
        draft.glyphs[socket] = 0
    end
    return draft
end

-- The live talents in the active talent group: yours from the client, an altbot's from the server.
function TM:LiveDraft()
    if self.char then
        local draft = (self.live and self:DecodeDraft(self.live.talents)) or self:NewDraft()
        draft.source = "live"
        draft.dirty = false
        draft.glyphs = self:LiveGlyphs()
        return draft
    end
    local draft = self:NewDraft()
    draft.source = "live"
    local group = GetActiveTalentGroup(false, false)
    for t, tree in ipairs(self.trees) do
        for i in pairs(tree.talents) do
            local rank = select(5, GetTalentInfo(t, i, false, false, group))
            draft.ranks[t][i] = rank or 0
        end
    end
    draft.glyphs = self:LiveGlyphs()
    return draft
end

function TM:Rank(draft, talent)
    return draft.ranks[talent.tree][talent.index] or 0
end

function TM:TreePoints(draft, t)
    local total = 0
    for _, rank in pairs(draft.ranks[t]) do
        total = total + rank
    end
    return total
end

-- Points in rows above `tier` (rows are numbered from the top, 1 first).
function TM:PointsAbove(draft, t, tier)
    local total = 0
    for i, rank in pairs(draft.ranks[t]) do
        local talent = self.trees[t].talents[i]
        if talent and talent.tier < tier then
            total = total + rank
        end
    end
    return total
end

function TM:TotalPoints(draft)
    local total = 0
    for t in ipairs(self.trees) do
        total = total + self:TreePoints(draft, t)
    end
    return total
end

-- Talent points the character has in all: unspent plus spent in the active talent group.
function TM:AvailablePoints()
    if self.char then
        return self.info and self.info.points or 0
    end
    local group = GetActiveTalentGroup(false, false)
    local total = GetUnspentTalentPoints(false, false, group) or 0
    for t = 1, GetNumTalentTabs(false, false) do
        total = total + (select(3, GetTalentTabInfo(t, false, false, group)) or 0)
    end
    return total
end

function TM:PrereqsMet(draft, talent)
    for k, prereq in ipairs(talent.prereqs) do
        if self:Rank(draft, prereq) < self:PrereqNeed(talent, k) then
            return false
        end
    end
    return true
end

function TM:TierUnlocked(draft, talent)
    return self:TreePoints(draft, talent.tree) >= (talent.tier - 1) * self.TIER_POINTS
end

-- Why a point can't be added: nil when it can, else "max", "points", "tier" or "prereq".
function TM:AddBlocker(draft, talent, available)
    if self:Rank(draft, talent) >= talent.maxRank then
        return "max"
    end
    if self:TotalPoints(draft) >= (available or self:AvailablePoints()) then
        return "points"
    end
    if not self:TierUnlocked(draft, talent) then
        return "tier"
    end
    if not self:PrereqsMet(draft, talent) then
        return "prereq"
    end
    return nil
end

-- Every talent with points has enough points in the rows above it.
function TM:TreeValid(draft, t)
    for _, talent in ipairs(self.trees[t].order) do
        if self:Rank(draft, talent) > 0 then
            if self:PointsAbove(draft, t, talent.tier) < (talent.tier - 1) * self.TIER_POINTS then
                return false
            end
            if not self:PrereqsMet(draft, talent) then
                return false
            end
        end
    end
    return true
end

-- A point can be taken out if no talent below still needs it.
function TM:CanRemove(draft, talent)
    local rank = self:Rank(draft, talent)
    if rank <= 0 then
        return false
    end

    local ranks = draft.ranks[talent.tree]
    ranks[talent.index] = rank - 1
    local valid = self:TreeValid(draft, talent.tree)
    ranks[talent.index] = rank
    return valid
end

function TM:AddPoint(talent)
    local draft = self.draft
    if draft and not self:AddBlocker(draft, talent) then
        draft.ranks[talent.tree][talent.index] = self:Rank(draft, talent) + 1
        draft.dirty = true
        self:Fire("DRAFT")
    end
end

function TM:RemovePoint(talent)
    local draft = self.draft
    if draft and self:CanRemove(draft, talent) then
        draft.ranks[talent.tree][talent.index] = self:Rank(draft, talent) - 1
        draft.dirty = true
        self:Fire("DRAFT")
    end
end

-- A saved spec as a draft (not changed). A spec the rules no longer allow shows empty.
function TM:SpecDraft(spec)
    local draft = self:DecodeDraft(spec.talents) or self:NewDraft()
    draft.source = "spec"
    draft.specId = spec.id
    for socket = 1, self.GLYPH_SLOTS do
        draft.glyphs[socket] = spec.glyphs[socket] or 0
    end
    return draft
end

-- What the window shows: your live talents, a saved spec (by id) or a new empty build.
function TM:Select(what)
    if what == "live" then
        self.draft = self:LiveDraft()
    elseif what == "new" then
        self.draft = self:NewDraft()
    else
        local spec = self.specById[what]
        if not spec then
            return
        end
        self.draft = self:SpecDraft(spec)
    end
    self:Fire("DRAFT")
end

-- The draft's name for the window and popups.
function TM:DraftName(draft)
    draft = draft or self.draft
    if not draft then
        return ""
    end
    if draft.source == "spec" then
        local spec = self.specById[draft.specId]
        return spec and spec.name or "?"
    elseif draft.source == "live" then
        return "Live talents"
    end
    return "New spec"
end

-- Back to what was there before the changes: the saved spec, your live talents, or an empty new build.
function TM:RevertDraft()
    local draft = self.draft
    if draft and draft.source == "spec" then
        self:Select(draft.specId)
    else
        self:Select(draft and draft.source or "live")
    end
end

function TM:ClearDraft()
    local draft = self.draft
    if not draft then
        return
    end
    for t in ipairs(self.trees) do
        draft.ranks[t] = {}
    end
    draft.dirty = true
    self:Fire("DRAFT")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Glyphs. Sockets are numbered 1-6 as the client's GetGlyphSocketInfo counts them (server slot + 1).

-- Glyph art for a GlyphProperties icon id (SpellIcon.dbc), as the stock glyph frame draws a socketed glyph.
local GLYPH_ICONS = {
    [2681] = "Interface\\Icons\\Creature_SporeMushroom",
    [3098] = "Interface\\Spellbook\\UI-Glyph-Rune-11",
    [3110] = "Interface\\Spellbook\\UI-Glyph-Rune-1",
    [3112] = "Interface\\Spellbook\\UI-Glyph-Rune-10",
    [3113] = "Interface\\Spellbook\\UI-Glyph-Rune-12",
    [3114] = "Interface\\Spellbook\\UI-Glyph-Rune-13",
    [3115] = "Interface\\Spellbook\\UI-Glyph-Rune-14",
    [3116] = "Interface\\Spellbook\\UI-Glyph-Rune-15",
    [3117] = "Interface\\Spellbook\\UI-Glyph-Rune-16",
    [3118] = "Interface\\Spellbook\\UI-Glyph-Rune-17",
    [3119] = "Interface\\Spellbook\\UI-Glyph-Rune-18",
    [3120] = "Interface\\Spellbook\\UI-Glyph-Rune-19",
    [3121] = "Interface\\Spellbook\\UI-Glyph-Rune-20",
    [3122] = "Interface\\Spellbook\\UI-Glyph-Rune-2",
    [3123] = "Interface\\Spellbook\\UI-Glyph-Rune-3",
    [3124] = "Interface\\Spellbook\\UI-Glyph-Rune-4",
    [3125] = "Interface\\Spellbook\\UI-Glyph-Rune-5",
    [3126] = "Interface\\Spellbook\\UI-Glyph-Rune-6",
    [3127] = "Interface\\Spellbook\\UI-Glyph-Rune-7",
    [3128] = "Interface\\Spellbook\\UI-Glyph-Rune-8",
    [3129] = "Interface\\Spellbook\\UI-Glyph-Rune1",
    [3312] = "Interface\\Spellbook\\UI-Glyph-Rune-9",
}
TM.GLYPH_RUNE = "Interface\\Spellbook\\UI-Glyph-Rune1"

-- The level each socket opens at (Spell::EffectApplyGlyph, Player::InitGlyphsForLevel), and its type (GlyphSlot.dbc:
-- 1 major, 2 minor).
TM.SOCKET_LEVELS = { 15, 15, 50, 30, 70, 80 }
TM.SOCKET_TYPES = { 1, 2, 2, 1, 2, 1 }

-- enabled, type (1 major, 2 minor) of a socket for the shown character.
function TM:SocketInfo(socket)
    if self.char then
        local level = self.info and self.info.level or self.char.level or 0
        return level >= self.SOCKET_LEVELS[socket], self.SOCKET_TYPES[socket]
    end
    local enabled, glyphType = GetGlyphSocketInfo(socket)
    return enabled and true or false, glyphType
end

-- The glyph ids in the sockets now (active talent group), 0 for empty or unknown to the list.
function TM:LiveGlyphs()
    local glyphs = {}
    if self.char then
        for socket = 1, self.GLYPH_SLOTS do
            local id = self.live and self.live.glyphs[socket] or 0
            glyphs[socket] = self.glyphById[id] and id or 0
        end
        return glyphs
    end
    for socket = 1, self.GLYPH_SLOTS do
        local spell = select(3, GetGlyphSocketInfo(socket))
        local glyph = spell and self.glyphBySpell[spell]
        glyphs[socket] = glyph and glyph.id or 0
    end
    return glyphs
end

-- How many of the glyph's item the shown character carries: your bags as they are now, an altbot's as the server
-- last counted them.
function TM:GlyphBagCount(glyph)
    if self.char then
        return glyph.bags or 0
    end
    return GetItemCount(glyph.itemId)
end

-- "known": free to put in. "bags": a load uses up one of the glyph items in the bags. "none": neither.
function TM:GlyphState(glyph)
    if glyph.known then
        return "known"
    elseif self:GlyphBagCount(glyph) > 0 then
        return "bags"
    end
    return "none"
end

-- True when a load would put the glyph in that socket.
function TM:GlyphLoadable(glyph, socket)
    local enabled, glyphType = self:SocketInfo(socket)
    return enabled and glyphType == glyph.type and self:GlyphState(glyph) ~= "none"
end

-- Puts a glyph (id, 0 to empty) in a socket of the draft; a glyph goes in one socket only.
function TM:SetGlyph(socket, id)
    local draft = self.draft
    if not draft or (draft.glyphs[socket] or 0) == id then
        return
    end
    if id ~= 0 then
        for other = 1, self.GLYPH_SLOTS do
            if draft.glyphs[other] == id then
                draft.glyphs[other] = 0
            end
        end
    end
    draft.glyphs[socket] = id
    draft.dirty = true
    self:Fire("DRAFT")
end

function TM:ClearGlyphs()
    local draft = self.draft
    if not draft then
        return
    end
    for socket = 1, self.GLYPH_SLOTS do
        draft.glyphs[socket] = 0
    end
    draft.dirty = true
    self:Fire("DRAFT")
end

function TM:GlyphCount(draft)
    local count = 0
    for socket = 1, self.GLYPH_SLOTS do
        if (draft.glyphs[socket] or 0) ~= 0 then
            count = count + 1
        end
    end
    return count
end

function TM:GlyphName(id)
    local glyph = self.glyphById[id]
    return glyph and glyph.name or ("glyph " .. id)
end

-- "0/53/18"
function TM:Split(draft)
    local parts = {}
    for t in ipairs(self.trees) do
        parts[t] = self:TreePoints(draft, t)
    end
    return table.concat(parts, "/")
end

-- The tree with the most points, or nil for none.
function TM:MainTree(draft)
    local best, bestPoints = nil, 0
    for t in ipairs(self.trees) do
        local points = self:TreePoints(draft, t)
        if points > bestPoints then
            best, bestPoints = t, points
        end
    end
    return best
end

-- ---------------------------------------------------------------------------------------------------------------
-- Link format: one digit per talent (its rank) in row, then column order; trees joined by '-'; trailing zeros and
-- empty trailing trees left out. The same format as Wowhead's talent calculator and playerbots' PremadeSpecLink.

function TM:EncodeDraft(draft)
    local parts = {}
    for t, tree in ipairs(self.trees) do
        local digits = {}
        for k, talent in ipairs(tree.order) do
            digits[k] = tostring(self:Rank(draft, talent))
        end
        parts[t] = (table.concat(digits):gsub("0+$", ""))
    end
    while #parts > 0 and parts[#parts] == "" do
        parts[#parts] = nil
    end
    return table.concat(parts, "-")
end

-- Returns a draft, or nil and a reason.
function TM:DecodeDraft(text)
    text = (text or ""):gsub("%s", "")
    -- Accept a whole talent calculator URL too: keep what follows the last '/'.
    text = text:match("([%d%-]*)$") or ""
    if text == "" then
        return nil, "no talent link"
    end

    local draft = self:NewDraft()
    local t = 1
    for part in (text .. "-"):gmatch("([^%-]*)%-") do
        local tree = self.trees[t]
        if not tree then
            return nil, "too many trees"
        end
        if #part > #tree.order then
            return nil, ("too many talents for %s"):format(tree.name)
        end
        for k = 1, #part do
            local talent = tree.order[k]
            local rank = tonumber(part:sub(k, k))
            if rank > talent.maxRank then
                return nil, ("%s has only %d ranks"):format(talent.name, talent.maxRank)
            end
            draft.ranks[t][talent.index] = rank
        end
        t = t + 1
    end

    for tt in ipairs(self.trees) do
        if not self:TreeValid(draft, tt) then
            return nil, ("the %s tree breaks the talent rules"):format(self.trees[tt].name)
        end
    end
    return draft
end

-- ---------------------------------------------------------------------------------------------------------------
-- Server messages

-- A request about the shown character (the state in place): an altbot's carry its guid.
function TM:Send(command, payload)
    local tag = self.char and ("@" .. self.char.guid .. "|") or ""
    SendAddonMessage(self.PREFIX, tag .. command .. ":" .. (payload or ""), "WHISPER", UnitName("player"))
end

local function Split(text, sep)
    local list = {}
    for field in ((text or "") .. sep):gmatch("(.-)" .. sep) do
        list[#list + 1] = field
    end
    return list
end

local handlers = {}

-- INFO:version,maxSpecs,talentPoints,activeGroup,groupCount,level,class
function handlers.INFO(payload)
    local f = Split(payload, ",")
    TM.info = {
        version = tonumber(f[1]) or 0,
        maxSpecs = tonumber(f[2]) or 0,
        points = tonumber(f[3]) or 0,
        activeGroup = tonumber(f[4]) or 1,
        groups = tonumber(f[5]) or 1,
        level = tonumber(f[6]),
        class = tonumber(f[7]),
    }
    TM.serverSeen = true
    if TM.char and TM.info.level then
        TM.char.level = TM.info.level
    end
    if TM.info.version ~= TM.PROTOCOL and not TM.warnedVersion then
        TM.warnedVersion = true
        TM:Print(("The server's mod-talent-manager speaks version %d, this addon %d. Update the one that's older.")
            :format(TM.info.version, TM.PROTOCOL))
    end
    if not TM.listed then
        TM.listed = true
        TM:Send("LIST")
        TM:Send("GLYPHS")
    end
    if not TM.char then
        TM:Send("CHARS")
    end
    TM:Fire("INFO")
end

function handlers.ERR(payload)
    TM:Say("|cffff4040" .. payload .. "|r")
end

function handlers.MSG(payload)
    TM:Say(payload)
end

-- Your characters for the picker: CHARBEGIN:, CHAR: entries "guid,name,class,level" (you first), CHAREND:. Never
-- tagged: it's about you.
local incomingChars

function handlers.CHARBEGIN()
    incomingChars = {}
end

function handlers.CHAR(payload)
    if not incomingChars then
        return
    end
    for _, entry in ipairs(Split(payload, ";")) do
        local f = Split(entry, ",")
        local guid = tonumber(f[1])
        if guid then
            incomingChars[#incomingChars + 1] = { guid = guid, name = f[2] or "?", class = tonumber(f[3]) or 0,
                level = tonumber(f[4]) or 0 }
        end
    end
end

function handlers.CHAREND()
    if not incomingChars then
        return
    end
    TM.characters, incomingChars = incomingChars, nil
    TM.selfGuid = TM.characters[1] and TM.characters[1].guid
    -- States keep the same tables, so levels and names stay current there too.
    for _, character in ipairs(TM.characters) do
        local state = TM.states[character.guid]
        if state and state.char then
            state.char.level, state.char.name = character.level, character.name
        end
    end
    -- The altbot shown logged out or got another master: back to you.
    if TM.char and not TM:CharacterByGuid(TM.char.guid) then
        TM:Print(("%s isn't one of your online altbots any more."):format(TM.char.name))
        TM:ShowCharacter(nil)
    end
    if TM.pending and not TM:CharacterByGuid(TM.pending) then
        TM.pending = nil
    end
    TM:Fire("CHARACTERS")
end

-- An altbot's talent trees: TREEBEGIN:class, TREE: entries "tree,talentId,row,column,maxRank,spell,dependsOn,
-- dependsOnRank", TREEEND:class.
local incomingTrees

function handlers.TREEBEGIN()
    incomingTrees = {}
end

function handlers.TREE(payload)
    if not incomingTrees then
        return
    end
    for _, entry in ipairs(Split(payload, ";")) do
        local f = Split(entry, ",")
        local id = tonumber(f[2])
        if id then
            incomingTrees[#incomingTrees + 1] = { tree = tonumber(f[1]) or 0, id = id, row = tonumber(f[3]) or 0,
                column = tonumber(f[4]) or 0, maxRank = tonumber(f[5]) or 1, spell = tonumber(f[6]) or 0,
                dependsOn = tonumber(f[7]) or 0, dependsOnRank = tonumber(f[8]) or 0 }
        end
    end
end

function handlers.TREEEND(payload)
    if not incomingTrees then
        return
    end
    local classId = tonumber(payload) or 0
    TM.classTrees[classId] = ServerTrees(classId, incomingTrees)
    incomingTrees = nil
    if TM.char and TM.char.class == classId then
        TM.trees = TM.classTrees[classId]
    end
end

-- An altbot's live build: LIVE:talents,glyph1..glyph6.
function handlers.LIVE(payload)
    local f = Split(payload, ",")
    local live = { talents = f[1] or "", glyphs = {} }
    for socket = 1, TM.GLYPH_SLOTS do
        live.glyphs[socket] = tonumber(f[1 + socket]) or 0
    end
    TM.live = live
    local draft = TM.draft
    if draft and draft.source == "live" and not draft.dirty and TM.trees then
        TM.draft = TM:LiveDraft()
    end
    TM:Fire("DRAFT")
end

-- The spec list: SPECBEGIN:count,max,loaded1,loaded2, SPEC: entries "id,sort,name,talents,glyph1..glyph6,bars"
-- (';' separated; bars 1 when the spec has action bars saved), SPECEND:.
local incoming

function handlers.SPECBEGIN(payload)
    local f = Split(payload, ",")
    TM.maxSpecs = tonumber(f[2]) or TM.maxSpecs
    for group = 1, 2 do
        local id = tonumber(f[2 + group])
        TM.loaded[group] = (id and id > 0) and id or nil
    end
    incoming = {}
end

function handlers.SPEC(payload)
    if not incoming then
        return
    end
    for _, entry in ipairs(Split(payload, ";")) do
        local f = Split(entry, ",")
        local id = tonumber(f[1])
        if id then
            local spec = { id = id, sort = tonumber(f[2]) or 0, name = f[3] or "?", talents = f[4] or "", glyphs = {} }
            for socket = 1, TM.GLYPH_SLOTS do
                spec.glyphs[socket] = tonumber(f[4 + socket]) or 0
            end
            spec.hasBars = f[5 + TM.GLYPH_SLOTS] == "1"
            incoming[#incoming + 1] = spec
        end
    end
end

function handlers.SPECEND()
    if not incoming then
        return
    end
    TM:LoadTrees()
    table.sort(incoming, function(a, b)
        if a.sort ~= b.sort then
            return a.sort < b.sort
        end
        return a.id < b.id
    end)
    TM.specs, TM.specById = incoming, {}
    for _, spec in ipairs(incoming) do
        spec.draft = TM:DecodeDraft(spec.talents) or TM:NewDraft()
        TM.specById[spec.id] = spec
    end
    incoming = nil

    local draft = TM.draft
    if TM.pendingSelect and TM.specById[TM.pendingSelect] then
        -- Just saved: show the saved spec, unchanged.
        TM:Select(TM.pendingSelect)
    elseif draft and draft.source == "spec" and not TM.specById[draft.specId] then
        -- The shown spec was deleted.
        TM:Select("live")
    end
    TM.pendingSelect = nil
    if not TM.draft and next(TM:LoadTrees()) then
        TM.draft = TM:LiveDraft()
    end
    TM.ready = true
    TM:Fire("SPECS")
end

-- The class's glyphs: GLYPHBEGIN:count, GLYPH: entries "id,spellId,type,itemId,iconId,known,bags" (';' separated;
-- type 0 major, 1 minor; bags: how many of its item the character carries), GLYPHEND:.
local incomingGlyphs

function handlers.GLYPHBEGIN()
    incomingGlyphs = {}
end

function handlers.GLYPH(payload)
    if not incomingGlyphs then
        return
    end
    for _, entry in ipairs(Split(payload, ";")) do
        local f = Split(entry, ",")
        local id, spellId = tonumber(f[1]), tonumber(f[2])
        if id and spellId then
            incomingGlyphs[#incomingGlyphs + 1] = {
                id = id, spellId = spellId, type = (tonumber(f[3]) or 0) + 1, itemId = tonumber(f[4]) or 0,
                icon = GLYPH_ICONS[tonumber(f[5]) or 0] or TM.GLYPH_RUNE, known = f[6] == "1",
                bags = tonumber(f[7]) or 0, name = GetSpellInfo(spellId) or ("Glyph " .. id),
            }
        end
    end
end

function handlers.GLYPHEND()
    if not incomingGlyphs then
        return
    end
    table.sort(incomingGlyphs, function(a, b) return a.name < b.name end)
    TM.glyphs, TM.glyphById, TM.glyphBySpell = incomingGlyphs, {}, {}
    for _, glyph in ipairs(incomingGlyphs) do
        TM.glyphById[glyph.id] = glyph
        TM.glyphBySpell[glyph.spellId] = glyph
    end
    incomingGlyphs = nil

    -- Live glyphs can be read now.
    local draft = TM.draft
    if draft and draft.source == "live" and not draft.dirty and TM.trees then
        TM.draft = TM:LiveDraft()
    end
    TM:Fire("GLYPHS")
    TM:Fire("DRAFT")
end

function handlers.SAVED(payload)
    TM.pendingSelect = tonumber(payload)
end

local function GlyphNames(list)
    local names = {}
    for _, id in ipairs(Split(list, "/")) do
        if tonumber(id) then
            names[#names + 1] = TM:GlyphName(tonumber(id))
        end
    end
    return names
end

-- LOADED:id,missing,skipped,used,bars: the spec is on the character now. skipped and used are glyph ids joined by
-- '/': glyphs that couldn't go in, and glyphs inscribed from an item in the bags. bars is 1 when the spec's action
-- bars were put on. The list follows.
function handlers.LOADED(payload)
    local f = Split(payload, ",")
    local id, missing = tonumber(f[1]), tonumber(f[2]) or 0
    local skipped, used = GlyphNames(f[3]), GlyphNames(f[4])
    local bars = f[5] == "1"
    TM:Fire("SPECLOADED", id)
    local spec = id and TM.specById[id]
    local name = (spec and spec.name or "the spec") .. (bars and " with its action bars" or "")
    if missing > 0 then
        TM:Say(("Loaded %s, but %d talents didn't take. The server log has details."):format(name, missing))
    else
        TM:Say(("Loaded %s."):format(name))
    end
    if #used > 0 then
        TM:Say(("Used from %s, known from now on: %s."):format(TM:Bags(), table.concat(used, ", ")))
    end
    if #skipped > 0 then
        TM:Say(("Left out: %s. Not known and none in %s, or the socket isn't open yet.")
            :format(table.concat(skipped, ", "), TM:Bags()))
    end
    -- Show it, unchanged, once the list arrives.
    TM.pendingSelect = id
end

-- ---------------------------------------------------------------------------------------------------------------
-- Spec actions (the server answers with the new list)

-- Removes the protocol's separators from a name the player typed.
function TM:CleanName(name)
    name = (name or ""):gsub("[,;:|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function SpecPayload(id, name, draft)
    local fields = { id, name, TM:EncodeDraft(draft) }
    for socket = 1, TM.GLYPH_SLOTS do
        fields[#fields + 1] = draft.glyphs[socket] or 0
    end
    return table.concat(fields, ",")
end

function TM:CanAddSpec()
    return not self.maxSpecs or #self.specs < self.maxSpecs
end

-- Saves the shown build over its saved spec, or as a new spec called `name`.
function TM:SaveDraft(name)
    local draft = self.draft
    if not draft then
        return
    end
    if draft.source == "spec" and not name then
        local spec = self.specById[draft.specId]
        if spec then
            self:Send("SAVE", SpecPayload(spec.id, spec.name, draft))
        end
    else
        self:Send("SAVE", SpecPayload(0, self:CleanName(name), draft))
    end
end

-- The spec last loaded into the active talent group, if it still exists.
function TM:LoadedSpec()
    local id = self.loaded[self:ActiveGroup()]
    return id and self.specById[id] or nil
end

-- True when your live talents or glyphs are no longer the loaded spec's. An empty socket in the spec, or a glyph a
-- load couldn't put in, doesn't count.
function TM:LiveDiffers(spec)
    self:LoadTrees()
    local live = self:LiveDraft()
    if self:EncodeDraft(live) ~= spec.talents then
        return true
    end
    for socket = 1, self.GLYPH_SLOTS do
        local id = spec.glyphs[socket] or 0
        local glyph = self.glyphById[id]
        if glyph and live.glyphs[socket] ~= id and self:GlyphLoadable(glyph, socket) then
            return true
        end
    end
    return false
end

function TM:LoadSpec(id)
    if not self.char and InCombatLockdown() then
        self:Print("You can't change talents in combat.")
        return
    end
    self:Send("LOAD", tostring(id))
end

-- Puts your live talents into the shown saved spec, as unsaved changes (Save keeps them).
function TM:UseLive()
    local draft = self.draft
    if not draft or draft.source ~= "spec" then
        return
    end
    local live = self:LiveDraft()
    draft.ranks = live.ranks
    draft.glyphs = live.glyphs
    draft.dirty = true
    self:Fire("DRAFT")
end

-- A saved spec by name, ignoring case.
function TM:FindSpec(name)
    name = (name or ""):lower()
    for _, spec in ipairs(self.specs) do
        if spec.name:lower() == name then
            return spec
        end
    end
end

function TM:RenameSpec(id, name)
    self:Send("RENAME", id .. "," .. self:CleanName(name))
end

function TM:DeleteSpec(id)
    self:Send("DELETE", tostring(id))
end

-- Shows a talent calculator link as a new, unsaved build. Returns false and a reason when it can't.
function TM:Import(link)
    self:LoadTrees()
    local draft, reason = self:DecodeDraft(link)
    if not draft then
        return false, reason
    end
    local points, available = self:TotalPoints(draft), self:AvailablePoints()
    if points > available then
        return false, ("that build needs %d talent points and you have %d"):format(points, available)
    end
    draft.dirty = true
    self.draft = draft
    self:Fire("SHOW")
    self:Fire("DRAFT")
    return true
end

-- Messages about you, whoever the window shows.
local ABOUT_YOU = { CHARBEGIN = true, CHAR = true, CHAREND = true }

local function OnAddonMessage(prefix, message, _, sender)
    if prefix ~= TM.PREFIX or sender ~= UnitName("player") then
        return
    end
    local guid, rest = message:match("^@(%d+)|(.*)$")
    if guid then
        guid, message = tonumber(guid), rest
    end
    local command, payload = message:match("^(%u+):(.*)$")
    local handler = command and handlers[command]
    if not handler then
        return
    end
    if ABOUT_YOU[command] then
        handler(payload)
        return
    end
    local key = guid or "self"
    TM:WithState(key, handler, payload)
    if TM.pending and TM.pending == key and TM.states[key] and TM.states[key].ready then
        SwitchTo(key)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Game events

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("GLYPH_ADDED")
events:RegisterEvent("GLYPH_UPDATED")
events:RegisterEvent("GLYPH_REMOVED")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")

-- Warn once if the server never answers HELLO. Bag changes are passed on at most twice a second. An altbot asked for
-- that never answers is given up on.
local helloSentAt, bagsChangedAt, partyChangedAt
events:SetScript("OnUpdate", function()
    if bagsChangedAt and GetTime() - bagsChangedAt > 0.5 then
        bagsChangedAt = nil
        TM:Fire("BAGS")
    end
    if partyChangedAt and GetTime() - partyChangedAt > 1 then
        partyChangedAt = nil
        if TM.serverSeen then
            TM:WithState("self", function() TM:Send("CHARS") end)
        end
    end
    if TM.pending and GetTime() - (TM.pendingSince or 0) > 8 then
        TM.pending = nil
        TM:Fire("CHARACTER")
    end
    if helloSentAt and GetTime() - helloSentAt > 10 then
        helloSentAt = nil
        if not TM.serverSeen then
            TM:Print("The server doesn't answer: mod-talent-manager isn't installed or is disabled. "
                .. "You can still plan talents, but saving and loading specs won't work.")
        end
    end
end)

-- Your talents or point total changed. Unchanged live talents in the window follow them. Runs with your state in
-- place.
local function OnLiveChanged()
    if not TM.trees then
        return
    end
    if TM.draft and TM.draft.source == "live" and not TM.draft.dirty then
        TM.draft = TM:LiveDraft()
    end
    TM:Fire("DRAFT")
end

local OnEvent

events:SetScript("OnEvent", function(_, event, ...)
    -- Server messages say whom they are about. Game events are about you, whoever the window shows.
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    else
        TM:WithState("self", OnEvent, event, ...)
    end
end)

OnEvent = function(event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == "TalentManager" then
        TalentManagerDB = TalentManagerDB or {}
        for key, value in pairs(DEFAULTS) do
            if TalentManagerDB[key] == nil then
                TalentManagerDB[key] = value
            end
        end
        TM:Fire("ADDON")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not TM.info then
            TM:Send("HELLO")
            helloSentAt = helloSentAt or GetTime()
        end
    elseif event == "BAG_UPDATE" then
        bagsChangedAt = bagsChangedAt or GetTime()
    elseif event == "PARTY_MEMBERS_CHANGED" then
        partyChangedAt = partyChangedAt or GetTime()
    elseif event == "GLYPH_ADDED" or event == "GLYPH_UPDATED" or event == "GLYPH_REMOVED" then
        -- A glyph inscribed by hand becomes known.
        if TM.info and event ~= "GLYPH_REMOVED" then
            TM:Send("GSYNC")
        end
        OnLiveChanged()
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_LEVEL_UP" then
        if TM.info then
            TM:Send("HELLO")
        end
        OnLiveChanged()
    else
        OnLiveChanged()
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Slash commands

SLASH_TALENTMANAGER1 = "/tm"
SLASH_TALENTMANAGER2 = "/talentmanager"
SlashCmdList.TALENTMANAGER = function(text)
    local command, rest = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        TM:Fire("TOGGLE")
    elseif command == "link" then
        TM:LoadTrees()
        TM:Print("Talent link: " .. TM:EncodeDraft(TM.draft or TM:LiveDraft()))
    elseif command == "load" then
        TM:WithState("self", function()
            local spec = TM:FindSpec(rest)
            if spec then
                TM:LoadSpec(spec.id)
            else
                TM:Print(("You have no spec called %s."):format(rest))
            end
        end)
    elseif command == "debug" then
        local ui = TM.UI and TM.UI.frame
        local pane = _G["TalentManagerGlyphPane"]
        TM:Print(("protocol %d, server %s, glyph file %s, glyphs %s, tab %s, glyph pane %s, shown %s, %d characters")
            :format(TM.PROTOCOL, TM.info and tostring(TM.info.version) or "none",
            TM.GlyphPane and "loaded" or "NOT loaded", TM.glyphs and tostring(#TM.glyphs) or "none",
            ui and tostring(PanelTemplates_GetSelectedTab(ui)) or "-",
            pane and (pane:IsVisible() and "shown" or "hidden") or "none", TM.char and TM.char.name or "you",
            #TM.characters))
    elseif command == "import" then
        local ok, reason = TM:Import(rest)
        if not ok then
            TM:Print("Can't import that: " .. reason .. ".")
        end
    else
        TM:Print("/tm - open the talent window")
        TM:Print("/tm link - print the shown build as a talent calculator link")
        TM:Print("/tm import <link> - show a talent calculator link in the window")
        TM:Print("/tm load <name> - load a saved spec onto your character (works in macros)")
    end
end
