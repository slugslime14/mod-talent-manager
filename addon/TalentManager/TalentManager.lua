-- TalentManager: saved talent specs for the mod-talent-manager server module.
-- Server <-> client messages are addon whispers to yourself, "CMD:payload", prefix TMGR.
-- The talent trees are read from the client's own data (GetTalentInfo and friends). A spec being edited is a
-- "draft": ranks per (tree, talent index). It can be written as the Wowhead / playerbots link format.
-- Saved specs live on the server, per character; the addon keeps the last list it was sent (TM.specs).

TalentManager = {
    PREFIX = "TMGR",
    PROTOCOL = 4,
    TIER_POINTS = 5,        -- points needed in a tree per row (PLAYER_TALENTS_PER_TIER)
    GLYPH_SLOTS = 6,
    info = nil,             -- the server's INFO: { version, maxSpecs, castMs, points, activeGroup, groups }
    trees = nil,            -- the class's talent trees, see LoadTrees
    -- The build shown in the window: { ranks = { [tree] = { [index] = rank } }, glyphs = { [socket] = id },
    -- source = "live" | "new" | "spec", specId, dirty }. "new" is a build not saved yet (New, Import).
    draft = nil,
    specs = {},             -- saved specs by list order: { id, sort, name, talents (link), glyphs, draft }
    specById = {},
    loaded = {},            -- [talent group] = id of the spec last loaded into it
    casting = nil,          -- a swap cast in progress: { specId, started, duration }
    -- The class's glyphs from the server: { id, spellId, type (1 major, 2 minor, as GetGlyphSocketInfo), itemId,
    -- icon, known, name }, sorted by name.
    glyphs = nil,
    glyphById = {},
    glyphBySpell = {},
    listeners = {},
}

local TM = TalentManager

local DEFAULTS = {
    point = nil,            -- the window's position: { point, x, y }
}

-- ---------------------------------------------------------------------------------------------------------------
-- Events between the files

function TM:On(event, callback)
    self.listeners[event] = self.listeners[event] or {}
    table.insert(self.listeners[event], callback)
end

-- A listener that fails is reported (the game's error handler) and the others still run.
function TM:Fire(event, ...)
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

function TM:LoadTrees()
    if self.trees then
        return self.trees
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

    self.trees = trees
    return trees
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

-- Your live talents in the active talent group.
function TM:LiveDraft()
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
    local group = GetActiveTalentGroup(false, false)
    local total = GetUnspentTalentPoints(false, false, group) or 0
    for t = 1, GetNumTalentTabs(false, false) do
        total = total + (select(3, GetTalentTabInfo(t, false, false, group)) or 0)
    end
    return total
end

function TM:PrereqsMet(draft, talent)
    for _, prereq in ipairs(talent.prereqs) do
        if self:Rank(draft, prereq) < prereq.maxRank then
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

-- The level each socket opens at (Spell::EffectApplyGlyph, Player::InitGlyphsForLevel).
TM.SOCKET_LEVELS = { 15, 15, 50, 30, 70, 80 }

-- enabled, type (1 major, 2 minor) of a socket for your character.
function TM:SocketInfo(socket)
    local enabled, glyphType = GetGlyphSocketInfo(socket)
    return enabled and true or false, glyphType
end

-- The glyph ids in your sockets now (active talent group), 0 for empty or unknown to the list.
function TM:LiveGlyphs()
    local glyphs = {}
    for socket = 1, self.GLYPH_SLOTS do
        local spell = select(3, GetGlyphSocketInfo(socket))
        local glyph = spell and self.glyphBySpell[spell]
        glyphs[socket] = glyph and glyph.id or 0
    end
    return glyphs
end

-- "known": free to put in. "bags": a load uses up one of the glyph items in your bags. "none": neither.
function TM:GlyphState(glyph)
    if glyph.known then
        return "known"
    elseif GetItemCount(glyph.itemId) > 0 then
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

function TM:Send(command, payload)
    SendAddonMessage(self.PREFIX, command .. ":" .. (payload or ""), "WHISPER", UnitName("player"))
end

local function Split(text, sep)
    local list = {}
    for field in ((text or "") .. sep):gmatch("(.-)" .. sep) do
        list[#list + 1] = field
    end
    return list
end

local handlers = {}

-- INFO:version,maxSpecs,swapCastMs,talentPoints,activeGroup,groupCount
function handlers.INFO(payload)
    local f = Split(payload, ",")
    TM.info = {
        version = tonumber(f[1]) or 0,
        maxSpecs = tonumber(f[2]) or 0,
        castMs = tonumber(f[3]) or 0,
        points = tonumber(f[4]) or 0,
        activeGroup = tonumber(f[5]) or 1,
        groups = tonumber(f[6]) or 1,
    }
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
    TM:Fire("INFO")
end

function handlers.ERR(payload)
    TM:Print("|cffff4040" .. payload .. "|r")
end

function handlers.MSG(payload)
    TM:Print(payload)
end

-- The spec list: SPECBEGIN:count,max,loaded1,loaded2, SPEC: entries "id,sort,name,talents,glyph1..glyph6" (';'
-- separated), SPECEND:.
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
    TM:Fire("SPECS")
end

-- The class's glyphs: GLYPHBEGIN:count, GLYPH: entries "id,spellId,type,itemId,iconId,known" (';' separated; type
-- 0 major, 1 minor), GLYPHEND:.
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
                name = GetSpellInfo(spellId) or ("Glyph " .. id),
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

-- CAST:ms,id: the swap cast for spec id started.
function handlers.CAST(payload)
    local f = Split(payload, ",")
    TM.casting = { specId = tonumber(f[2]), started = GetTime(), duration = (tonumber(f[1]) or 0) / 1000 }
    TM:Fire("CAST")
end

local STOP_REASONS = {
    moved = "You moved.",
    combat = "You entered combat.",
    dead = "You died.",
    cast = "You started casting.",
    stopped = "Stopped.",
    deleted = "The spec was deleted.",
}

-- CASTSTOP:reason: the swap cast ended without loading.
function handlers.CASTSTOP(payload)
    local casting = TM.casting
    TM.casting = nil
    TM:Fire("CASTSTOP", payload)
    if payload ~= "failed" then
        local spec = casting and TM.specById[casting.specId]
        TM:Print(("Loading %s stopped: %s"):format(spec and spec.name or "the spec",
            STOP_REASONS[payload] or payload))
    end
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

-- LOADED:id,missing,skipped,used: the spec is on the character now. skipped and used are glyph ids joined by '/':
-- glyphs that couldn't go in, and glyphs inscribed from an item in the bags. The list follows.
function handlers.LOADED(payload)
    local f = Split(payload, ",")
    local id, missing = tonumber(f[1]), tonumber(f[2]) or 0
    local skipped, used = GlyphNames(f[3]), GlyphNames(f[4])
    TM.casting = nil
    TM:Fire("LOADED", id)
    local spec = id and TM.specById[id]
    local name = spec and spec.name or "the spec"
    if missing > 0 then
        TM:Print(("Loaded %s, but %d talents didn't take. The server log has details."):format(name, missing))
    else
        TM:Print(("Loaded %s."):format(name))
    end
    if #used > 0 then
        TM:Print(("Used from your bags, known from now on: %s."):format(table.concat(used, ", ")))
    end
    if #skipped > 0 then
        TM:Print(("Left out: %s. Not known and none in your bags, or the socket isn't open yet.")
            :format(table.concat(skipped, ", ")))
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
    local id = self.loaded[GetActiveTalentGroup(false, false)]
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
    if InCombatLockdown() then
        self:Print("You can't change talents in combat.")
        return
    end
    self:Send("LOAD", tostring(id))
end

function TM:StopLoad()
    self:Send("STOP")
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

local function OnAddonMessage(prefix, message, _, sender)
    if prefix ~= TM.PREFIX or sender ~= UnitName("player") then
        return
    end
    local command, payload = message:match("^(%u+):(.*)$")
    local handler = command and handlers[command]
    if handler then
        handler(payload)
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

-- Warn once if the server never answers HELLO. Bag changes are passed on at most twice a second.
local helloSentAt, bagsChangedAt
events:SetScript("OnUpdate", function()
    if bagsChangedAt and GetTime() - bagsChangedAt > 0.5 then
        bagsChangedAt = nil
        TM:Fire("BAGS")
    end
    if helloSentAt and GetTime() - helloSentAt > 10 then
        helloSentAt = nil
        if not TM.info then
            TM:Print("The server doesn't answer: mod-talent-manager isn't installed or is disabled. "
                .. "You can still plan talents, but saving and loading specs won't work.")
        end
    end
end)

-- Your talents or point total changed. Unchanged live talents in the window follow them.
local function OnLiveChanged()
    if not TM.trees then
        return
    end
    if TM.draft and TM.draft.source == "live" and not TM.draft.dirty then
        TM.draft = TM:LiveDraft()
    end
    TM:Fire("DRAFT")
end

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == "TalentManager" then
        TalentManagerDB = TalentManagerDB or {}
        for key, value in pairs(DEFAULTS) do
            if TalentManagerDB[key] == nil then
                TalentManagerDB[key] = value
            end
        end
        TM:Fire("LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not TM.info then
            TM:Send("HELLO")
            helloSentAt = helloSentAt or GetTime()
        end
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(arg1, arg2, arg3, arg4)
    elseif event == "BAG_UPDATE" then
        bagsChangedAt = bagsChangedAt or GetTime()
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
end)

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
        local spec = TM:FindSpec(rest)
        if spec then
            TM:LoadSpec(spec.id)
        else
            TM:Print(("You have no spec called %s."):format(rest))
        end
    elseif command == "debug" then
        local ui = TM.UI and TM.UI.frame
        local pane = _G["TalentManagerGlyphPane"]
        TM:Print(("protocol %d, server %s, glyph file %s, glyphs %s, tab %s, glyph pane %s"):format(TM.PROTOCOL,
            TM.info and tostring(TM.info.version) or "none", TM.GlyphPane and "loaded" or "NOT loaded",
            TM.glyphs and tostring(#TM.glyphs) or "none", ui and tostring(PanelTemplates_GetSelectedTab(ui)) or "-",
            pane and (pane:IsVisible() and "shown" or "hidden") or "none"))
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
