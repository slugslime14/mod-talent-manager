-- TalentManager Glyphs tab: the build's six glyph sockets drawn like the stock 3.3.5 glyph frame (Blizzard_GlyphUI's
-- art, socket positions and textures). Clicking a socket opens a list of the class's glyphs for it beside the socket.
-- Sockets are numbered as GetGlyphSocketInfo counts them: 1, 4 and 6 major, 2, 3 and 5 minor.

local TM = TalentManager
local UI = TM.UI
local Pane = {}
TM.GlyphPane = Pane

local NAME = "TalentManagerGlyphPane"
local ART = "Interface\\Spellbook\\UI-GlyphFrame"
local MAJOR, MINOR = 1, 2
local GLYPH_COLORS = {
    [MAJOR] = { r = 1, g = 0.25, b = 0 },
    [MINOR] = { r = 0, g = 0.25, b = 1 },
}

-- Rune art behind a socketed glyph, per socket (GLYPH_SLOTS in Blizzard_GlyphUI.lua); [0] is an empty socket.
local SOCKET_BACKGROUNDS = {
    [0] = { 0.78125, 0.91015625, 0.69921875, 0.828125 },
    [1] = { 0, 0.12890625, 0.87109375, 1 },
    [2] = { 0.130859375, 0.259765625, 0.87109375, 1 },
    [3] = { 0.392578125, 0.521484375, 0.87109375, 1 },
    [4] = { 0.5234375, 0.65234375, 0.87109375, 1 },
    [5] = { 0.26171875, 0.390625, 0.87109375, 1 },
    [6] = { 0.654296875, 0.783203125, 0.87109375, 1 },
}

-- Where the stock frame puts each socket on its 384 x 512 frame.
local SOCKET_POINTS = {
    [1] = { "CENTER", -15, 140 },
    [2] = { "CENTER", -14, -103 },
    [3] = { "TOPLEFT", 28, -133 },
    [4] = { "BOTTOMRIGHT", -56, 168 },
    [5] = { "TOPRIGHT", -56, -133 },
    [6] = { "BOTTOMLEFT", 26, 168 },
}

-- The glyph list popup: where it opens beside each socket (point on the list, point on the socket, x, y).
local LIST_POINTS = {
    [1] = { "TOP", "BOTTOM", 0, 6 },
    [2] = { "BOTTOM", "TOP", 0, -6 },
    [3] = { "LEFT", "RIGHT", -6, 0 },
    [6] = { "LEFT", "RIGHT", -6, 0 },
    [4] = { "RIGHT", "LEFT", 6, 0 },
    [5] = { "RIGHT", "LEFT", 6, 0 },
}
local LIST_WIDTH = 250
local LIST_ROWS = 12
local LIST_INSET = 8
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 22

local pane, list
local selectedSocket        -- the socket the list is open for, or nil when it is closed
local listOffset = 0

local function Texture(parent, layer, file, width, height)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(file)
    texture:SetWidth(width)
    texture:SetHeight(height)
    texture:SetPoint("CENTER")
    return texture
end

-- ---------------------------------------------------------------------------------------------------------------
-- Sockets

-- Sizes and art for a major or minor socket (GlyphFrameGlyph_SetGlyphType).
local function SetSocketType(socket, glyphType)
    socket.glyphType = glyphType
    socket.setting:SetTexture(ART)
    local color = GLYPH_COLORS[glyphType]
    socket.glyph:SetVertexColor(color.r, color.g, color.b)
    if glyphType == MAJOR then
        socket.setting:SetWidth(108)
        socket.setting:SetHeight(108)
        socket.setting:SetTexCoord(0.740234375, 0.953125, 0.484375, 0.697265625)
        socket.highlight:SetWidth(108)
        socket.highlight:SetHeight(108)
        socket.highlight:SetTexCoord(0.740234375, 0.953125, 0.484375, 0.697265625)
        socket.ring:SetWidth(82)
        socket.ring:SetHeight(82)
        socket.ring:SetPoint("CENTER", socket, "CENTER", 0, -1)
        socket.ring:SetTexCoord(0.767578125, 0.92578125, 0.32421875, 0.482421875)
        socket.shine:SetTexCoord(0.9609375, 1, 0.9609375, 1)
        socket.background:SetWidth(70)
        socket.background:SetHeight(70)
    else
        socket.setting:SetWidth(86)
        socket.setting:SetHeight(86)
        socket.setting:SetTexCoord(0.765625, 0.927734375, 0.15625, 0.31640625)
        socket.highlight:SetWidth(86)
        socket.highlight:SetHeight(86)
        socket.highlight:SetTexCoord(0.765625, 0.927734375, 0.15625, 0.31640625)
        socket.ring:SetWidth(62)
        socket.ring:SetHeight(62)
        socket.ring:SetPoint("CENTER", socket, "CENTER", 0, 1)
        socket.ring:SetTexCoord(0.787109375, 0.908203125, 0.033203125, 0.154296875)
        socket.shine:SetTexCoord(0.9609375, 1, 0.921875, 0.9609375)
        socket.background:SetWidth(64)
        socket.background:SetHeight(64)
    end
end

local function SocketGlyph(id)
    local draft = TM.draft
    return draft and TM.glyphById[draft.glyphs[id] or 0]
end

-- %s is "your bags" or "<altbot>'s bags".
local STATE_LINES = {
    known = { "Known: a load puts it in for free.", 0.1, 1, 0.1 },
    bags = { "Not known yet: a load uses one from %s, then it's known.", 1, 0.82, 0 },
    none = { "Not known and none in %s: a load leaves it out. Inscribe it once by hand, or have one in the bags.",
        1, 0.25, 0.25 },
}

local function AddStateLine(glyph)
    local line = STATE_LINES[TM:GlyphState(glyph)]
    GameTooltip:AddLine(line[1]:format(TM:Bags()), line[2], line[3], line[4], true)
end

local function SocketTooltip(socket)
    local id = socket:GetID()
    local enabled, glyphType = TM:SocketInfo(id)
    local typeName = glyphType == MINOR and (MINOR_GLYPH or "Minor Glyph") or (MAJOR_GLYPH or "Major Glyph")
    GameTooltip:SetOwner(socket, "ANCHOR_RIGHT")
    local glyph = SocketGlyph(id)
    if not enabled then
        GameTooltip:SetText(typeName)
        GameTooltip:AddLine(("Opens at level %d."):format(TM.SOCKET_LEVELS[id]), 1, 0.25, 0.25)
    elseif glyph then
        GameTooltip:SetHyperlink("spell:" .. glyph.spellId)
        AddStateLine(glyph)
        GameTooltip:AddLine("Click to pick another, right-click to take it out.", 0.5, 0.5, 0.5, true)
    else
        GameTooltip:SetText(typeName)
        GameTooltip:AddLine("Empty. Click to pick a glyph.", 1, 1, 1, true)
        GameTooltip:AddLine("Loading a spec with an empty socket leaves the glyph you have there.", 0.5, 0.5, 0.5,
            true)
    end
    GameTooltip:Show()
end

local function UpdateSocket(socket)
    local id = socket:GetID()
    local enabled, glyphType = TM:SocketInfo(id)
    SetSocketType(socket, glyphType == MINOR and MINOR or MAJOR)
    local glyph = SocketGlyph(id)

    socket.glyph:SetDesaturated(false)
    socket.glyph:SetAlpha(1)
    if not enabled then
        socket.shine:Hide()
        socket.background:Hide()
        socket.glyph:Hide()
        socket.ring:Hide()
        socket.setting:SetTexture("Interface\\Spellbook\\UI-GlyphFrame-Locked")
        socket.setting:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        socket.setting:SetAlpha(0.6)
    elseif not glyph then
        socket.shine:Show()
        socket.background:Show()
        socket.background:SetTexCoord(unpack(SOCKET_BACKGROUNDS[0]))
        socket.glyph:Hide()
        socket.ring:Show()
        socket.setting:SetAlpha(0.6)
    else
        socket.shine:Show()
        socket.background:Show()
        socket.background:SetTexCoord(unpack(SOCKET_BACKGROUNDS[id]))
        socket.glyph:SetTexture(glyph.icon)
        socket.glyph:Show()
        socket.ring:Show()
        socket.setting:SetAlpha(1)
        -- A glyph a load would leave out is drawn faded.
        if TM:GlyphState(glyph) == "none" then
            socket.glyph:SetDesaturated(true)
            socket.glyph:SetAlpha(0.5)
        end
    end

    if enabled and id == selectedSocket and list:IsShown() then
        socket.highlight:SetAlpha(0.6)
        socket.highlight:Show()
    elseif socket:IsMouseOver() and enabled then
        socket.highlight:SetAlpha(0.4)
        socket.highlight:Show()
    else
        socket.highlight:Hide()
    end

    if GameTooltip:IsOwned(socket) then
        SocketTooltip(socket)
    end
end

local function OpenList(id)
    selectedSocket = id
    listOffset = 0
    local point = LIST_POINTS[id]
    list:ClearAllPoints()
    list:SetPoint(point[1], pane.sockets[id], point[2], point[3], point[4])
end

local function CloseList()
    selectedSocket = nil
end

-- Click opens the list for the socket (or closes it when it is open for that socket); right-click empties it.
local function SocketClicked(socket, button)
    local id = socket:GetID()
    if not TM:SocketInfo(id) then
        return
    end
    if button == "RightButton" then
        TM:SetGlyph(id, 0)
        CloseList()
    elseif selectedSocket == id then
        CloseList()
    else
        OpenList(id)
    end
    Pane:Update()
end

-- One socket, built like GlyphTemplate.
local function BuildSocket(parent, id)
    local socket = CreateFrame("Button", NAME .. "Glyph" .. id, parent)
    socket:SetID(id)
    socket:SetWidth(90)
    socket:SetHeight(90)
    local point = SOCKET_POINTS[id]
    socket:SetPoint(point[1], parent, point[1], point[2], point[3])
    socket:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    socket.setting = Texture(socket, "BACKGROUND", ART, 86, 86)
    socket.highlight = Texture(socket, "BORDER", ART, 86, 86)
    socket.highlight:SetBlendMode("ADD")
    socket.highlight:SetVertexColor(1, 1, 1, 0.25)
    socket.highlight:Hide()
    socket.background = Texture(socket, "BORDER", ART, 64, 64)
    socket.glyph = Texture(socket, "ARTWORK", TM.GLYPH_RUNE, 53, 53)
    socket.ring = Texture(socket, "OVERLAY", ART, 62, 62)
    socket.shine = Texture(socket, "OVERLAY", ART, 16, 16)
    socket.shine:ClearAllPoints()
    socket.shine:SetPoint("CENTER", -9, 12)

    socket:SetScript("OnClick", SocketClicked)
    socket:SetScript("OnEnter", function(self)
        SocketTooltip(self)
        UpdateSocket(self)
    end)
    socket:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        UpdateSocket(self)
    end)
    return socket
end

-- ---------------------------------------------------------------------------------------------------------------
-- The glyph list

local STATE_ORDER = { known = 1, bags = 2, none = 3 }

-- The class's glyphs for the selected socket's type: known first, then in the bags, then the rest.
local function ListedGlyphs()
    local glyphs = {}
    local _, glyphType = TM:SocketInfo(selectedSocket)
    for _, glyph in ipairs(TM.glyphs or {}) do
        if glyph.type == glyphType then
            glyphs[#glyphs + 1] = glyph
        end
    end
    table.sort(glyphs, function(a, b)
        local sa, sb = STATE_ORDER[TM:GlyphState(a)], STATE_ORDER[TM:GlyphState(b)]
        if sa ~= sb then
            return sa < sb
        end
        return a.name < b.name
    end)
    return glyphs
end

-- The socket of the draft a glyph is in, or nil.
local function SocketOf(glyph)
    local draft = TM.draft
    for socket = 1, TM.GLYPH_SLOTS do
        if draft and draft.glyphs[socket] == glyph.id then
            return socket
        end
    end
end

local function RowTooltip(row)
    local glyph = row.glyph
    if not glyph then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("spell:" .. glyph.spellId)
    AddStateLine(glyph)
    GameTooltip:Show()
end

local function RowClicked(row)
    if row.glyph and selectedSocket and TM:SocketInfo(selectedSocket) then
        local socket = selectedSocket
        CloseList()
        TM:SetGlyph(socket, row.glyph.id)
        Pane:Update()
    end
end

local function BuildRow(index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_INSET, -LIST_INSET - HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT", -LIST_INSET, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(18)
    row.icon:SetHeight(18)
    row.icon:SetPoint("LEFT", 4, 0)

    row.state = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.state:SetPoint("RIGHT", -4, 0)
    row.state:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")

    row:SetScript("OnClick", RowClicked)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function UpdateRow(row, glyph)
    row.glyph = glyph
    if not glyph then
        row:Hide()
        return
    end
    row.icon:SetTexture(GetItemIcon(glyph.itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(glyph.name)

    local state = TM:GlyphState(glyph)
    local socket = SocketOf(glyph)
    local here = socket ~= nil and socket == selectedSocket
    row.icon:SetDesaturated(state == "none" and not here)
    if here then
        row.name:SetTextColor(1, 1, 1)
        row.state:SetText("In this socket")
        row.state:SetTextColor(1, 1, 1)
    else
        if state == "none" then
            row.name:SetTextColor(0.5, 0.5, 0.5)
        else
            row.name:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        end
        if socket then
            row.state:SetText("In another socket")
            row.state:SetTextColor(0.8, 0.8, 0.8)
        elseif state == "known" then
            row.state:SetText("Known")
            row.state:SetTextColor(0.1, 1, 0.1)
        elseif state == "bags" then
            row.state:SetText(("In bags (%d)"):format(TM:GlyphBagCount(glyph)))
            row.state:SetTextColor(1, 0.82, 0)
        else
            row.state:SetText("Not known")
            row.state:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    row:Show()
    if GameTooltip:IsOwned(row) then
        RowTooltip(row)
    end
end

local function VisibleRows()
    return #list.rows
end

local function UpdateList()
    local _, glyphType = TM:SocketInfo(selectedSocket)
    local glyphs = ListedGlyphs()
    local rows = VisibleRows()
    listOffset = math.max(0, math.min(listOffset, #glyphs - rows))

    if not TM.glyphs then
        list.header:SetText(TM.info and "Waiting for the glyph list..." or "The server didn't send a glyph list.")
    else
        local typeName = glyphType == MINOR and "Minor glyphs" or "Major glyphs"
        if #glyphs > rows then
            list.header:SetText(("%s %d-%d of %d (scroll)"):format(typeName, listOffset + 1,
                math.min(listOffset + rows, #glyphs), #glyphs))
        else
            list.header:SetText(typeName)
        end
    end

    for i, row in ipairs(list.rows) do
        UpdateRow(row, glyphs[listOffset + i])
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Building and updating

function Pane:Build(f)
    pane = CreateFrame("Frame", NAME, f)
    pane:SetWidth(384)
    pane:SetHeight(512)
    pane:SetPoint("TOPLEFT", f, "TOPLEFT")
    -- Above the status line and the tree, as the stock glyph frame sits over the talent frame. The close button
    -- stays on top.
    pane:SetFrameLevel(f:GetFrameLevel() + 10)
    local close = _G[f:GetName() .. "CloseButton"]
    if close then
        close:SetFrameLevel(pane:GetFrameLevel() + 2)
    end
    pane:Hide()

    local art = pane:CreateTexture(nil, "ARTWORK")
    art:SetTexture(ART)
    art:SetWidth(352)
    art:SetHeight(441)
    art:SetPoint("TOPLEFT")
    art:SetTexCoord(0, 0.6875, 0, 0.861328125)

    pane.title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pane.title:SetPoint("TOP", 0, -18)
    pane.title:SetWidth(240)

    pane.sockets = {}
    for id = 1, TM.GLYPH_SLOTS do
        pane.sockets[id] = BuildSocket(pane, id)
    end

    -- The window's bottom bars (Clear, Save, Reset and the points line) stay usable above the art.
    for _, bar in ipairs({ "PreviewBar", "PointsBar" }) do
        local frame = _G[f:GetName() .. bar]
        if frame then
            frame:SetFrameLevel(pane:GetFrameLevel() + 2)
        end
    end

    -- The glyph list: a popup beside the socket it is open for.
    list = CreateFrame("Frame", NAME .. "List", pane)
    list:SetWidth(LIST_WIDTH)
    list:SetHeight(2 * LIST_INSET + HEADER_HEIGHT + LIST_ROWS * ROW_HEIGHT)
    list:SetFrameLevel(pane:GetFrameLevel() + 6)
    list:SetClampedToScreen(true)
    list:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    list:SetBackdropColor(0, 0, 0, 0.95)
    list:SetBackdropBorderColor(1, 1, 1)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        listOffset = listOffset - delta * 3
        UpdateList()
    end)
    list:Hide()

    local close = CreateFrame("Button", nil, list, "UIPanelCloseButton")
    close:SetWidth(24)
    close:SetHeight(24)
    close:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        CloseList()
        Pane:Update()
    end)

    list.header = list:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    list.header:SetPoint("TOPLEFT", LIST_INSET + 4, -LIST_INSET - 5)
    list.header:SetPoint("RIGHT", close, "LEFT", -2, 0)
    list.header:SetJustifyH("LEFT")

    list.rows = {}
    for i = 1, LIST_ROWS do
        list.rows[i] = BuildRow(i)
    end
end

function Pane:Update()
    if not pane then
        return
    end
    if not UI:OnGlyphTab() or not UI.frame:IsShown() then
        CloseList()
        pane:Hide()
        return
    end
    pane:Show()

    -- A socket can close under the list: another character shown, or a lower level.
    if selectedSocket and not TM:SocketInfo(selectedSocket) then
        CloseList()
    end
    if selectedSocket then
        list:Show()
    else
        list:Hide()
    end

    local draft = TM.draft
    local name = TM:DraftName(draft)
    if draft and draft.dirty then
        name = name .. "*"
    end
    pane.title:SetText((GLYPHS or "Glyphs") .. ": " .. name)

    for _, socket in ipairs(pane.sockets) do
        UpdateSocket(socket)
    end
    if selectedSocket then
        UpdateList()
    end
end

TM:On("WINDOW", function() Pane:Update() end)
TM:On("GLYPHS", function() Pane:Update() end)
TM:On("BAGS", function()
    if TM.UI.frame and TM.UI.frame:IsShown() then
        TM.UI:Update()
    end
end)
