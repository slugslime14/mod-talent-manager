-- TalentManager window: a talent tree that looks like the game's talent frame, drawing a draft instead of your live
-- talents. The size, layout numbers and textures are the 3.3.5 PlayerTalentFrame's, scrolling tree included.
-- Branches and arrows are placed with the stock helpers in FrameXML's TalentFrameBase.lua (TalentFrame_SetPrereqs,
-- TalentFrame_SetBranchTexture, ...), which find their textures by name, so the child frames below use the names
-- those helpers expect ("<frame>ScrollFrame", "<frame>ScrollChildFrame", ...).

local TM = TalentManager
local UI = {}
TM.UI = UI

local NAME = "TalentManagerFrame"
local MAX_TALENTS = MAX_NUM_TALENTS or 40
local MAX_BRANCHES = MAX_NUM_BRANCH_TEXTURES or 30
local MAX_ARROWS = MAX_NUM_ARROW_TEXTURES or 30
local MAX_TIERS = MAX_NUM_TALENT_TIERS or 15
local COLUMNS = NUM_TALENT_COLUMNS or 4
local BUTTON_SIZE = TALENT_BUTTON_SIZE or 32
local OFFSET_X = INITIAL_TALENT_OFFSET_X or 35
local OFFSET_Y = INITIAL_TALENT_OFFSET_Y or 20
local SPACING = 63
local TALENT_BUTTON_HEIGHT = 37     -- ItemButtonTemplate

-- The stock frame: 384 x 512; the tree's scroll frame is 296 wide, 65 in from the right and 77 below the top, and
-- ends at the points bar (the points and button bars take the bottom 129).
local WIDTH, HEIGHT = 384, 512
local TREE_RIGHT, TREE_TOP, TREE_WIDTH = 65, 77, 296
local BOTTOM_BARS = 129
local CANVAS_WIDTH = 320            -- PlayerTalentFrameScrollChildFrame

local frame

-- The tab after the three trees shows the glyph sockets (TalentManagerGlyphs.lua).
UI.GLYPH_TAB = 4

-- ---------------------------------------------------------------------------------------------------------------
-- Building the window

local function Texture(parent, name, layer, file, width, height)
    local texture = parent:CreateTexture(name, layer)
    if file then
        texture:SetTexture(file)
    end
    if width then
        texture:SetWidth(width)
        texture:SetHeight(height)
    end
    return texture
end

-- Height of a tree's canvas: every row, plus a margin under the last row.
local function TreeHeight(tree)
    return OFFSET_Y + ((tree.maxTier or 1) - 1) * SPACING + TALENT_BUTTON_HEIGHT + 14
end

-- The frame art, portrait, title and close button, as PlayerTalentFrame has them.
local function BuildShell(f)
    f:SetWidth(WIDTH)
    f:SetHeight(HEIGHT)
    f:SetHitRectInsets(0, 30, 0, 45)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        TalentManagerDB.point = { point, x, y }
    end)
    f:Hide()
    tinsert(UISpecialFrames, NAME)

    f.portrait = Texture(f, NAME .. "Portrait", "BACKGROUND", nil, 60, 60)
    f.portrait:SetPoint("TOPLEFT", 7, -6)

    local art = "Interface\\PaperDollInfoFrame\\UI-Character-General-"
    local topLeft = Texture(f, nil, "BORDER", art .. "TopLeft", 256, 256)
    topLeft:SetPoint("TOPLEFT", 2, -1)
    local topRight = Texture(f, nil, "BORDER", art .. "TopRight", 128, 256)
    topRight:SetPoint("TOPRIGHT", 2, -1)
    local bottomLeft = Texture(f, nil, "BORDER", art .. "BottomLeft", 256, 256)
    bottomLeft:SetPoint("BOTTOMLEFT", 2, -1)
    local bottomRight = Texture(f, nil, "BORDER", art .. "BottomRight", 128, 256)
    bottomRight:SetPoint("BOTTOMRIGHT", 2, -1)

    f.title = f:CreateFontString(NAME .. "TitleText", "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -18)
    f.title:SetText(TALENTS)

    local close = CreateFrame("Button", NAME .. "CloseButton", f, "UIPanelCloseButton")
    close:SetPoint("CENTER", f, "TOPRIGHT", -44, -25)
end

-- The boxed line under the title (the stock frame's dual-spec status line): what the window shows.
local function BuildStatus(f)
    local status = CreateFrame("Frame", NAME .. "StatusFrame", f)
    status:SetWidth(264)
    status:SetHeight(20)
    status:SetPoint("TOPLEFT", f, "TOPLEFT", 75, -46)

    local border = "Interface\\Common\\Common-Input-Border"
    local left = Texture(status, nil, "OVERLAY", border, 8, 20)
    left:SetPoint("LEFT")
    left:SetTexCoord(0, 0.0625, 0, 0.625)
    local middle = Texture(status, nil, "OVERLAY", border, 248, 20)
    middle:SetPoint("LEFT", left, "RIGHT")
    middle:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    local right = Texture(status, nil, "OVERLAY", border, 8, 20)
    right:SetPoint("LEFT", middle, "RIGHT")
    right:SetTexCoord(0.9375, 1, 0, 0.625)

    f.statusText = status:CreateFontString(NAME .. "StatusText", "OVERLAY", "GameFontNormal")
    f.statusText:SetPoint("LEFT", 10, 0)
    f.statusText:SetPoint("RIGHT", -10, 0)
end

local function BorderPiece(parent, layer, width, height, l, r, t, b)
    local texture = Texture(parent, nil, layer, "Interface\\Buttons\\UI-Button-Borders2", width, height)
    texture:SetTexCoord(l, r, t, b)
    return texture
end

local function TooltipButton(parent, name, width, text, tooltip)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(22)
    button:SetText(text)
    button:SetScript("OnEnter", function(self)
        local tip = type(tooltip) == "function" and tooltip(self) or tooltip
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip, nil, nil, nil, nil, true)
        end
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end
UI.TooltipButton = TooltipButton

-- Save with no name asks for one: the shown build is your live talents or a new build.
local function SaveClicked()
    local draft = TM.draft
    if draft.source == "spec" then
        TM:SaveDraft()
    else
        UI:AskName("Name the new spec:", "", function(name) TM:SaveDraft(name) end)
    end
end

-- The bottom bars, laid out as the stock frame in talent preview mode: buttons at the bottom, the points line just
-- above them.
local function BuildBars(f)
    local bar = CreateFrame("Frame", NAME .. "PreviewBar", f)
    bar:SetHeight(26)
    bar:SetPoint("LEFT", f, "LEFT", 20, 0)
    bar:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    bar:SetPoint("BOTTOM", f, "BOTTOM", 0, 81)

    local buttonBorder = BorderPiece(bar, "BORDER", 164, 26, 0.16015625, 0.470703125, 0, 0.203125)
    buttonBorder:SetPoint("RIGHT")

    local filler = CreateFrame("Frame", nil, bar)
    filler:SetHeight(26)
    filler:SetPoint("LEFT")
    filler:SetPoint("RIGHT", buttonBorder, "LEFT")
    local fl = BorderPiece(filler, "BACKGROUND", 8, 26, 0.470703125, 0.484375, 0, 0.203125)
    fl:SetPoint("LEFT")
    fl:SetPoint("TOP")
    fl:SetPoint("BOTTOM")
    local fr = BorderPiece(filler, "BACKGROUND", 8, 26, 0.78515625, 0.80078125, 0, 0.203125)
    fr:SetPoint("RIGHT")
    fr:SetPoint("TOP")
    fr:SetPoint("BOTTOM")
    local fm = BorderPiece(filler, "BACKGROUND", nil, nil, 0.484375, 0.78515625, 0, 0.203125)
    fm:SetPoint("TOPLEFT", fl, "TOPRIGHT")
    fm:SetPoint("BOTTOMRIGHT", fr, "BOTTOMLEFT")

    f.clearButton = TooltipButton(filler, NAME .. "ClearButton", 60, "Clear", function()
        if UI:OnGlyphTab() then
            return "Take every glyph out of this build."
        end
        return "Take every point out, to plan from scratch."
    end)
    f.clearButton:SetPoint("LEFT", 4, 0)
    f.clearButton:SetScript("OnClick", function()
        if UI:OnGlyphTab() then
            TM:ClearGlyphs()
        else
            TM:ClearDraft()
        end
    end)

    f.noteText = filler:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.noteText:SetPoint("LEFT", f.clearButton, "RIGHT", 6, 1)
    f.noteText:SetPoint("RIGHT", -8, 1)
    f.noteText:SetJustifyH("LEFT")

    f.resetButton = TooltipButton(bar, NAME .. "ResetButton", 80, RESET, function()
        local source = TM.draft and TM.draft.source
        if source == "spec" then
            return "Drop the changes and show the saved spec again."
        elseif source == "live" then
            return "Drop the changes and show your live talents again."
        end
        return "Drop the changes and start the new spec over."
    end)
    f.resetButton:SetPoint("RIGHT", -4, 0)
    f.resetButton:SetScript("OnClick", function() TM:RevertDraft() end)

    f.saveButton = TooltipButton(bar, NAME .. "SaveButton", 80, SAVE or "Save", function()
        local draft = TM.draft
        if draft and draft.source == "spec" then
            return "Save the changes to " .. TM:DraftName(draft) .. "."
        elseif not TM:CanAddSpec() then
            return ("You have %d specs, the most the server allows. Delete one to save this."):format(#TM.specs)
        end
        return "Save this build as a new spec."
    end)
    f.saveButton:SetPoint("RIGHT", f.resetButton, "LEFT")
    f.saveButton:SetScript("OnClick", SaveClicked)

    local points = CreateFrame("Frame", NAME .. "PointsBar", f)
    points:SetHeight(26)
    points:SetPoint("LEFT", f, "LEFT", 16, 0)
    points:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    points:SetPoint("BOTTOM", bar, "TOP", 0, -4)
    local background = BorderPiece(points, "BACKGROUND", nil, nil, 0, 0.646484375, 0.2109375, 0.4140625)
    background:SetAllPoints()
    local bl = BorderPiece(points, "BORDER", 6, 18, 0, 0.01171875, 0.421875, 0.5625)
    bl:SetPoint("LEFT", 4, 0)
    bl:SetPoint("TOP", 0, -5)
    bl:SetPoint("BOTTOM", 0, 5)
    local br = BorderPiece(points, "BORDER", 6, 18, 0.3046875, 0.31640625, 0.421875, 0.5625)
    br:SetPoint("RIGHT", -4, 0)
    br:SetPoint("TOP", 0, -5)
    br:SetPoint("BOTTOM", 0, 5)
    local bm = BorderPiece(points, "BORDER", nil, nil, 0.01171875, 0.3046875, 0.421875, 0.5625)
    bm:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bm:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")

    f.spentText = points:CreateFontString(NAME .. "SpentPointsText", "ARTWORK", "GameFontNormalSmall")
    f.spentText:SetPoint("LEFT", 12, 1)
    f.pointsText = points:CreateFontString(NAME .. "TalentPointsText", "ARTWORK", "GameFontNormalSmall")
    f.pointsText:SetPoint("RIGHT", -12, 1)
end

local function OnTalentEnter(button)
    UI:ShowTalentTooltip(button)
end

local function OnTalentClick(button, mouseButton)
    local talent = button.talent
    if not talent then
        return
    end
    if IsModifiedClick("CHATLINK") then
        if talent.id then
            local rank = TM:Rank(TM.draft, talent)
            ChatEdit_InsertLink(("|cff4e96f7|Htalent:%d:%d|h[%s]|h|r"):format(talent.id, rank - 1, talent.name))
        end
    elseif mouseButton == "LeftButton" then
        TM:AddPoint(talent)
    elseif mouseButton == "RightButton" then
        TM:RemovePoint(talent)
    end
end

-- The tree: a scroll frame with the talent background and the scroll bar art, as the stock frame has them, and a
-- canvas that scrolls with the talent buttons, branch and arrow textures.
local function BuildTree(f)
    local area = CreateFrame("ScrollFrame", NAME .. "ScrollFrame", f, "UIPanelScrollFrameTemplate")
    area:SetWidth(TREE_WIDTH)
    area:SetHeight(HEIGHT - TREE_TOP - BOTTOM_BARS)
    area:SetPoint("TOPRIGHT", f, "TOPRIGHT", -TREE_RIGHT, -TREE_TOP)
    f.treeArea = area

    -- The four background pieces, anchored as PlayerTalentFrameBackground*.
    local b = {}
    b.TopLeft = Texture(area, NAME .. "BackgroundTopLeft", "BORDER", nil, 256, 256)
    b.TopLeft:SetPoint("TOPLEFT")
    b.TopLeft:SetPoint("RIGHT", -40, 0)
    b.TopLeft:SetPoint("BOTTOM", 0, 76)
    b.TopRight = Texture(area, NAME .. "BackgroundTopRight", "BORDER", nil, 44, 256)
    b.TopRight:SetPoint("TOPRIGHT")
    b.TopRight:SetPoint("BOTTOMLEFT", b.TopLeft, "BOTTOMRIGHT")
    b.TopRight:SetTexCoord(0, 0.6875, 0, 1)
    b.BottomLeft = Texture(area, NAME .. "BackgroundBottomLeft", "BORDER", nil, 256, 75)
    b.BottomLeft:SetPoint("BOTTOMLEFT")
    b.BottomLeft:SetPoint("TOPRIGHT", b.TopLeft, "BOTTOMRIGHT")
    b.BottomLeft:SetTexCoord(0, 1, 0, 0.5859375)
    b.BottomRight = Texture(area, NAME .. "BackgroundBottomRight", "BORDER", nil, 44, 75)
    b.BottomRight:SetPoint("BOTTOMRIGHT")
    b.BottomRight:SetPoint("TOPLEFT", b.TopLeft, "BOTTOMRIGHT")
    b.BottomRight:SetTexCoord(0, 0.6875, 0, 0.5859375)
    f.backgrounds = b

    -- The scroll bar's trough, as PlayerTalentFrameScrollFrameBackgroundTop / Bottom.
    local trough = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar"
    local troughTop = Texture(area, nil, "ARTWORK", trough, 31, 256)
    troughTop:SetPoint("TOPLEFT", area, "TOPRIGHT", -2, 5)
    troughTop:SetTexCoord(0, 0.484375, 0, 1)
    local troughBottom = Texture(area, nil, "ARTWORK", trough, 31, 106)
    troughBottom:SetPoint("BOTTOMLEFT", area, "BOTTOMRIGHT", -2, -2)
    troughBottom:SetTexCoord(0.515625, 1, 0, 0.4140625)

    -- Shown on the Glyphs tab when TalentManagerGlyphs.lua didn't load (a new file needs a client restart).
    f.glyphMissing = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.glyphMissing:SetPoint("TOPLEFT", area, "TOPLEFT", 20, -40)
    f.glyphMissing:SetPoint("RIGHT", area, "RIGHT", -20, 0)
    f.glyphMissing:SetText("The glyph part of TalentManager didn't load. Quit the game and start it again "
        .. "(a /reload doesn't pick up new addon files).")
    f.glyphMissing:Hide()

    local canvas = CreateFrame("Frame", NAME .. "ScrollChildFrame", area)
    canvas:SetWidth(CANVAS_WIDTH)
    canvas:SetHeight(50)
    canvas:SetPoint("TOPLEFT")
    area:SetScrollChild(canvas)
    f.canvas = canvas

    for i = 1, MAX_BRANCHES do
        local branch = Texture(canvas, NAME .. "Branch" .. i, "BACKGROUND", "Interface\\TalentFrame\\UI-TalentBranches",
            32, 32)
        branch:SetPoint("TOPLEFT")
        branch:Hide()
    end

    f.buttons = {}
    for i = 1, MAX_TALENTS do
        local button = CreateFrame("Button", NAME .. "Talent" .. i, canvas, "TalentButtonTemplate")
        button:SetID(i)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", OnTalentClick)
        button:SetScript("OnEnter", OnTalentEnter)
        button:Hide()
        f.buttons[i] = button
    end

    local arrows = CreateFrame("Frame", NAME .. "ArrowFrame", canvas)
    arrows:SetAllPoints(canvas)
    arrows:SetFrameLevel(canvas:GetFrameLevel() + 5)
    for i = 1, MAX_ARROWS do
        local arrow = Texture(arrows, NAME .. "Arrow" .. i, "OVERLAY", "Interface\\TalentFrame\\UI-TalentArrows",
            32, 32)
        arrow:SetPoint("TOPLEFT")
        arrow:Hide()
    end
end

-- The tree tabs along the bottom edge, then the Glyphs tab.
local function BuildTabs(f)
    f.tabs = {}
    for i = 1, UI.GLYPH_TAB do
        local tab = CreateFrame("Button", NAME .. "Tab" .. i, f, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 15, 46)
        else
            tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", -15, 0)
        end
        tab:SetScript("OnClick", function(self)
            PanelTemplates_SetTab(f, self:GetID())
            PlaySound("igCharacterInfoTab")
            UI:ScrollToTop()
            UI:Update()
        end)
        tab:SetScript("OnEnter", function(self)
            local tree = TM.trees and TM.trees[self:GetID()]
            if self:GetID() == UI.GLYPH_TAB and TM.draft then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(GLYPHS or "Glyphs")
                GameTooltip:AddLine(("%d of %d sockets filled"):format(TM:GlyphCount(TM.draft), TM.GLYPH_SLOTS),
                    1, 1, 1)
                GameTooltip:Show()
            elseif tree and TM.draft then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tree.name)
                GameTooltip:AddLine(("%d points"):format(TM:TreePoints(TM.draft, tree.index)), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        tab:SetScript("OnLeave", GameTooltip_Hide)
        f.tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(f, UI.GLYPH_TAB)
    PanelTemplates_SetTab(f, 1)
end

local function Build()
    frame = CreateFrame("Frame", NAME, UIParent)
    local f = frame
    UI.frame = f
    TalentFrame_Load(f)

    BuildShell(f)
    BuildStatus(f)
    BuildBars(f)
    BuildTree(f)
    BuildTabs(f)
    if TM.Specs then
        TM.Specs:Build(f)
    end
    if TM.GlyphPane then
        TM.GlyphPane:Build(f)
    end

    local saved = TalentManagerDB and TalentManagerDB.point
    if saved then
        f:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -12)
    end

    f:SetScript("OnShow", function()
        PlaySound("TalentScreenOpen")
        -- Altbots come and go: ask for the picker's list again.
        if TM.serverSeen then
            TM:WithState("self", function() TM:Send("CHARS") end)
        end
        UI:Update()
    end)
    f:SetScript("OnHide", function()
        PlaySound("TalentScreenClose")
        StaticPopup_Hide("TALENTMANAGER_NAME")
        StaticPopup_Hide("TALENTMANAGER_CONFIRM")
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Drawing a tree. The same steps as the stock TalentFrame_Update, with ranks from the draft.

-- The stock prerequisite helper takes (tier, column, isLearnable, isPreviewLearnable) per prerequisite.
local function PrereqArgs(talent)
    local args, n = {}, 0
    for k, prereq in ipairs(talent.prereqs) do
        local met = TM:Rank(TM.draft, prereq) >= TM:PrereqNeed(talent, k)
        args[n + 1], args[n + 2], args[n + 3], args[n + 4] = prereq.tier, prereq.column, met, met
        n = n + 4
    end
    return unpack(args, 1, n)
end

local function SetButtonLook(button, talent, rank, lit)
    local name = button:GetName()
    local slot, rankText, rankBorder = _G[name .. "Slot"], _G[name .. "Rank"], _G[name .. "RankBorder"]
    rankText:SetText(rank)
    if lit then
        SetItemButtonDesaturated(button, nil)
        if rank < talent.maxRank then
            slot:SetVertexColor(0.1, 1.0, 0.1)
            rankText:SetTextColor(GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        else
            slot:SetVertexColor(1.0, 0.82, 0)
            rankText:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        end
        rankBorder:SetVertexColor(1, 1, 1)
        rankBorder:Show()
        rankText:Show()
    else
        SetItemButtonDesaturated(button, 1, 0.65, 0.65, 0.65)
        slot:SetVertexColor(0.5, 0.5, 0.5)
        if rank == 0 then
            rankBorder:Hide()
            rankText:Hide()
        else
            rankBorder:SetVertexColor(0.5, 0.5, 0.5)
            rankBorder:Show()
            rankText:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
            rankText:Show()
        end
    end
end

-- Places the branch and arrow pieces the prerequisite pass recorded in TALENT_BRANCH_ARRAY.
local function DrawBranches(f)
    local coords, arrowCoords = TALENT_BRANCH_TEXTURECOORDS, TALENT_ARROW_TEXTURECOORDS
    local function Branch(tier, column, kind, value, x, y)
        TalentFrame_SetBranchTexture(tier, column, coords[kind][value], x, y, f)
    end
    local function Arrow(tier, column, kind, value, x, y)
        TalentFrame_SetArrowTexture(tier, column, arrowCoords[kind][value], x, y, f)
    end

    TalentFrame_ResetBranchTextureCount(f)
    TalentFrame_ResetArrowTextureCount(f)
    local ignoreUp
    for i = 1, MAX_TIERS do
        for j = 1, COLUMNS do
            local node = f.TALENT_BRANCH_ARRAY[i][j]
            local x = ((j - 1) * SPACING) + OFFSET_X + 2
            local y = -((i - 1) * SPACING) - OFFSET_Y - 2

            if node.id then
                if node.up ~= 0 then
                    if not ignoreUp then
                        Branch(i, j, "up", node.up, x, y + BUTTON_SIZE)
                    else
                        ignoreUp = nil
                    end
                end
                if node.down ~= 0 then
                    Branch(i, j, "down", node.down, x, y - BUTTON_SIZE + 1)
                end
                if node.left ~= 0 then
                    Branch(i, j, "left", node.left, x - BUTTON_SIZE, y)
                end
                if node.right ~= 0 then
                    -- A greyed branch coming down from the right is drawn grey here too.
                    local nextNode = f.TALENT_BRANCH_ARRAY[i][j + 1]
                    if nextNode.left ~= 0 and nextNode.down < 0 then
                        Branch(i, j - 1, "right", nextNode.down, x + BUTTON_SIZE, y)
                    else
                        Branch(i, j, "right", node.right, x + BUTTON_SIZE + 1, y)
                    end
                end
                if node.rightArrow ~= 0 then
                    Arrow(i, j, "right", node.rightArrow, x + BUTTON_SIZE / 2 + 5, y)
                end
                if node.leftArrow ~= 0 then
                    Arrow(i, j, "left", node.leftArrow, x - BUTTON_SIZE / 2 - 5, y)
                end
                if node.topArrow ~= 0 then
                    Arrow(i, j, "top", node.topArrow, x, y + BUTTON_SIZE / 2 + 5)
                end
            else
                -- An empty cell a branch passes through: pick the joint piece.
                if node.up ~= 0 and node.left ~= 0 and node.right ~= 0 then
                    Branch(i, j, "tup", node.up, x, y)
                elseif node.down ~= 0 and node.left ~= 0 and node.right ~= 0 then
                    Branch(i, j, "tdown", node.down, x, y)
                elseif node.left ~= 0 and node.down ~= 0 then
                    Branch(i, j, "topright", node.left, x, y)
                    Branch(i, j, "down", node.down, x, y - 32)
                elseif node.left ~= 0 and node.up ~= 0 then
                    Branch(i, j, "bottomright", node.left, x, y)
                elseif node.left ~= 0 and node.right ~= 0 then
                    Branch(i, j, "right", node.right, x + BUTTON_SIZE, y)
                    Branch(i, j, "left", node.left, x + 1, y)
                elseif node.right ~= 0 and node.down ~= 0 then
                    Branch(i, j, "topleft", node.right, x, y)
                    Branch(i, j, "down", node.down, x, y - 32)
                elseif node.right ~= 0 and node.up ~= 0 then
                    Branch(i, j, "bottomleft", node.right, x, y)
                elseif node.up ~= 0 and node.down ~= 0 then
                    Branch(i, j, "up", node.up, x, y)
                    Branch(i, j, "down", node.down, x, y - 32)
                    ignoreUp = 1
                end
            end
        end
    end

    for i = TalentFrame_GetBranchTextureCount(f), MAX_BRANCHES do
        _G[NAME .. "Branch" .. i]:Hide()
    end
    for i = TalentFrame_GetArrowTextureCount(f), MAX_ARROWS do
        _G[NAME .. "Arrow" .. i]:Hide()
    end
end

local function UpdateTree(f, tree, draft, pointsLeft)
    local base = "Interface\\TalentFrame\\" .. (tree.background or "MageFire") .. "-"
    for piece, texture in pairs(f.backgrounds) do
        texture:SetTexture(base .. piece)
    end

    f.canvas:SetHeight(TreeHeight(tree))
    f.treeArea:UpdateScrollChildRect()

    TalentFrame_ResetBranches(f)
    for i = 1, MAX_TALENTS do
        local button = f.buttons[i]
        local talent = tree.talents[i]
        button.talent = talent
        if talent then
            local rank = TM:Rank(draft, talent)
            SetTalentButtonLocation(button, talent.tier, talent.column)
            f.TALENT_BRANCH_ARRAY[talent.tier][talent.column].id = button:GetID()

            -- With no points left, only talents that have points are lit.
            local forceDesaturated = (pointsLeft <= 0 and rank == 0) and 1 or nil
            local tierUnlocked = TM:TierUnlocked(draft, talent) and 1 or nil
            SetItemButtonTexture(button, talent.icon)
            local lit = TalentFrame_SetPrereqs(f, talent.tier, talent.column, forceDesaturated, tierUnlocked, false,
                PrereqArgs(talent))
            SetButtonLook(button, talent, rank, lit and true or false)
            button:Show()
            if GameTooltip:IsOwned(button) then
                UI:ShowTalentTooltip(button)
            end
        else
            button:Hide()
        end
    end

    DrawBranches(f)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Tooltips

local REQUIRES_TIER = TOOLTIP_TALENT_TIER_POINTS or "Requires %d points in %s Talents"
local REQUIRES_PREREQ = TOOLTIP_TALENT_PREREQ or "Requires %d points in %s"

-- The talent at the draft's rank. A talent link carries the rank (0-based, -1 for none), so the client's tooltip
-- shows that rank's text and the next one.
function UI:ShowTalentTooltip(button)
    local talent = button.talent
    if not talent then
        return
    end
    local draft = TM.draft
    local rank = TM:Rank(draft, talent)

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if talent.id then
        GameTooltip:SetHyperlink(("talent:%d:%d"):format(talent.id, rank - 1))
    else
        GameTooltip:SetTalent(talent.tree, talent.index)
    end

    local blocker = TM:AddBlocker(draft, talent)
    if blocker == "tier" then
        GameTooltip:AddLine(REQUIRES_TIER:format((talent.tier - 1) * TM.TIER_POINTS, TM.trees[talent.tree].name),
            RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
    elseif blocker == "prereq" then
        for k, prereq in ipairs(talent.prereqs) do
            local need = TM:PrereqNeed(talent, k)
            if TM:Rank(draft, prereq) < need then
                GameTooltip:AddLine(REQUIRES_PREREQ:format(need, prereq.name),
                    RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
            end
        end
    end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Popups

local function PopupBox(dialog)
    if dialog.wideEditBox and dialog.wideEditBox:IsShown() then
        return dialog.wideEditBox
    end
    return dialog.editBox
end

-- A text prompt. data = { default, fn(text), select }.
StaticPopupDialogs["TALENTMANAGER_NAME"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self, data)
        local box = PopupBox(self)
        box:SetText(data and data.default or "")
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = function(self, data)
        data.fn(PopupBox(self):GetText())
    end,
    EditBoxOnEnterPressed = function(self, data)
        data.fn(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    OnHide = function(self)
        PopupBox(self):SetText("")
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

-- A long text field: import (fn set) or export (text only, to copy).
StaticPopupDialogs["TALENTMANAGER_LINK"] = {
    text = "%s",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = 1,
    hasWideEditBox = 1,
    maxLetters = 255,
    OnShow = function(self, data)
        local box = PopupBox(self)
        box:SetText(data and data.default or "")
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = function(self, data)
        if data and data.fn then
            data.fn(PopupBox(self):GetText())
        end
    end,
    EditBoxOnEnterPressed = function(self, data)
        if data and data.fn then
            data.fn(self:GetText())
        end
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    OnHide = function(self)
        PopupBox(self):SetText("")
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

-- A yes / no question. data = { fn }.
StaticPopupDialogs["TALENTMANAGER_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        data.fn()
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

function UI:AskName(prompt, default, fn)
    StaticPopup_Show("TALENTMANAGER_NAME", prompt, nil, { default = default, fn = fn })
end

function UI:AskLink(prompt, default, fn)
    StaticPopup_Show("TALENTMANAGER_LINK", prompt, nil, { default = default, fn = fn })
end

function UI:Confirm(question, fn)
    StaticPopup_Show("TALENTMANAGER_CONFIRM", question, nil, { fn = fn })
end

-- Runs `fn` now, or after asking when the shown build has changes that would be lost.
function UI:ConfirmDiscard(fn)
    local draft = TM.draft
    if draft and draft.dirty then
        UI:Confirm(("Drop your changes to %s?"):format(TM:DraftName(draft)), fn)
    else
        fn()
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Whole-window update

-- Your portrait, or the altbot's when it's in your party, else its class icon.
local function UpdatePortrait(f)
    local char = TM.char
    if not char then
        SetPortraitTexture(f.portrait, "player")
        f.portrait:SetTexCoord(0, 1, 0, 1)
        return
    end
    local count, prefix = GetNumRaidMembers(), "raid"
    if count == 0 then
        count, prefix = GetNumPartyMembers(), "party"
    end
    for i = 1, count do
        local unit = prefix .. i
        if UnitName(unit) == char.name then
            SetPortraitTexture(f.portrait, unit)
            f.portrait:SetTexCoord(0, 1, 0, 1)
            return
        end
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[TM.CLASS_TOKENS[char.class] or ""]
    if coords then
        f.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        f.portrait:SetTexCoord(unpack(coords))
    else
        f.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        f.portrait:SetTexCoord(0, 1, 0, 1)
    end
end

function UI:Update()
    local f = frame
    if not f or not f:IsShown() then
        return
    end
    UpdatePortrait(f)
    f.title:SetText(TM.char and ((TALENTS or "Talents") .. ": " .. TM.char.name) or TALENTS)
    local trees = TM:LoadTrees()
    if not trees[1] then
        -- Can't happen for a character that is shown (the switch waits for its trees); stay safe anyway.
        f.treeArea:Hide()
        f.statusText:SetText("Waiting for the server...")
        TM:Fire("WINDOW")
        return
    end
    if not TM.draft then
        TM.draft = TM:LiveDraft()
    end
    local draft = TM.draft

    local selected = PanelTemplates_GetSelectedTab(f) or 1
    if not trees[selected] and selected ~= UI.GLYPH_TAB then
        selected = 1
        PanelTemplates_SetTab(f, 1)
    end
    local onGlyphs = selected == UI.GLYPH_TAB

    for i, tab in ipairs(f.tabs) do
        local tree = trees[i]
        if i == UI.GLYPH_TAB then
            tab:SetText(GLYPHS or "Glyphs")
            PanelTemplates_TabResize(tab, 0)
            tab:Show()
        elseif tree then
            tab:SetText(tree.name)
            PanelTemplates_TabResize(tab, 0)
            tab:Show()
        else
            tab:Hide()
        end
    end
    PanelTemplates_UpdateTabs(f)

    local available = TM:AvailablePoints()
    local spent = TM:TotalPoints(draft)
    local left = available - spent
    local tree = trees[selected]

    if onGlyphs then
        f.spentText:SetFormattedText("%s: %s", GLYPHS or "Glyphs", HIGHLIGHT_FONT_COLOR_CODE
            .. TM:GlyphCount(draft) .. " / " .. TM.GLYPH_SLOTS .. FONT_COLOR_CODE_CLOSE)
    else
        f.spentText:SetFormattedText(MASTERY_POINTS_SPENT or "%s Talents: %s", tree.name,
            HIGHLIGHT_FONT_COLOR_CODE .. TM:TreePoints(draft, selected) .. FONT_COLOR_CODE_CLOSE)
    end
    local leftColor = left < 0 and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
    f.pointsText:SetFormattedText(UNSPENT_TALENT_POINTS or "Unspent Talent Points: %s",
        leftColor .. left .. FONT_COLOR_CODE_CLOSE)

    local name = TM:DraftName(draft)
    if draft.source == "live" and TM:NumGroups() > 1 then
        local group = TM:ActiveGroup()
        name = name .. " (" .. (group == 2 and (TALENT_SPEC_SECONDARY or "Secondary")
            or (TALENT_SPEC_PRIMARY or "Primary")) .. ")"
    end
    if draft.dirty then
        name = name .. "*"
    end
    f.statusText:SetText(name .. "  " .. HIGHLIGHT_FONT_COLOR_CODE .. TM:Split(draft) .. FONT_COLOR_CODE_CLOSE)

    if draft.dirty or draft.source == "new" then
        f.noteText:SetText(GREEN_FONT_COLOR_CODE .. "Not saved" .. FONT_COLOR_CODE_CLOSE)
    else
        f.noteText:SetText("")
    end

    if draft.dirty then
        f.resetButton:Enable()
    else
        f.resetButton:Disable()
    end
    local canSave
    if draft.source == "spec" then
        canSave = draft.dirty
    else
        canSave = TM.info ~= nil and TM:CanAddSpec()
    end
    if canSave then
        f.saveButton:Enable()
    else
        f.saveButton:Disable()
    end
    if (onGlyphs and TM:GlyphCount(draft) > 0) or (not onGlyphs and spent > 0) then
        f.clearButton:Enable()
    else
        f.clearButton:Disable()
    end

    if onGlyphs then
        f.treeArea:Hide()
        if TM.GlyphPane then
            f.glyphMissing:Hide()
        else
            f.glyphMissing:Show()
        end
    else
        f.glyphMissing:Hide()
        f.treeArea:Show()
        UpdateTree(f, tree, draft, left)
    end
    TM:Fire("WINDOW")
end

function UI:ScrollToTop()
    local bar = frame and _G[NAME .. "ScrollFrameScrollBar"]
    if bar then
        bar:SetValue(0)
    end
end

function UI:OnGlyphTab()
    return frame ~= nil and PanelTemplates_GetSelectedTab(frame) == UI.GLYPH_TAB
end

function UI:Toggle()
    if not frame then
        Build()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function UI:Show()
    if not frame then
        Build()
    end
    if frame:IsShown() then
        UI:Update()
    else
        frame:Show()
    end
end

TM:On("TOGGLE", function() UI:Toggle() end)
TM:On("SHOW", function() UI:Show() end)
TM:On("DRAFT", function() UI:Update() end)
TM:On("INFO", function() UI:Update() end)
TM:On("SPECS", function() UI:Update() end)
TM:On("CHARACTER", function() UI:Update() end)
TM:On("CHARACTERS", function() UI:Update() end)
