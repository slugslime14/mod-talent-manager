-- TalentManager spec list: a panel on the right of the talent window. The first row is your live talents, then your
-- saved specs. Clicking a row shows it in the tree; the buttons under the list make, copy, rename, delete, import
-- and export specs, and Load puts the shown spec on your character. Saving is the Save button under the tree.

local TM = TalentManager
local UI = TM.UI
local Specs = {}
TM.Specs = Specs

local NAME = "TalentManagerSpecs"
local ROW_HEIGHT = 34
local ROW_WIDTH = 186
local LIST_TOP = 40         -- below the panel's title
local BUTTONS_HEIGHT = 120  -- the three button rows and the note line at the bottom
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local panel
local rows = {}
local offset = 0            -- saved specs scrolled past (the mouse wheel; the live row always stays first)

-- The icon of the tree with the most points.
local function DraftIcon(draft)
    local main = TM:MainTree(draft)
    return main and TM.trees[main].icon or EMPTY_ICON
end

local function RowClicked(row)
    local what = row.what
    local draft = TM.draft
    if draft and ((what == "live" and draft.source == "live") or (what == draft.specId and draft.source == "spec")) then
        return
    end
    UI:ConfirmDiscard(function() TM:Select(what) end)
end

local function RowEnter(row)
    local what = row.what
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if what == "live" then
        GameTooltip:SetText("Live talents")
        GameTooltip:AddLine("The talents your character has now.", 1, 1, 1, true)
    else
        local spec = TM.specById[what]
        if not spec then
            return
        end
        GameTooltip:SetText(spec.name)
        GameTooltip:AddLine(TM:Split(spec.draft) .. "  (" .. TM:TotalPoints(spec.draft) .. " points)", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function MakeRow(index)
    local row = CreateFrame("Button", NAME .. "Row" .. index, panel)
    row:SetWidth(ROW_WIDTH)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -LIST_TOP - (index - 1) * ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(28)
    row.icon:SetHeight(28)
    row.icon:SetPoint("LEFT", 2, 0)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")

    row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.sub:SetPoint("RIGHT", -4, 0)
    row.sub:SetJustifyH("LEFT")

    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    row.selected:SetBlendMode("ADD")
    row.selected:SetVertexColor(0.2, 0.5, 1.0, 0.7)
    row.selected:SetAllPoints()
    row.selected:Hide()

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", RowClicked)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[index] = row
    return row
end

-- ---------------------------------------------------------------------------------------------------------------
-- Buttons

local function ShownSpec()
    local draft = TM.draft
    return draft and draft.source == "spec" and TM.specById[draft.specId] or nil
end

local function NewClicked()
    UI:ConfirmDiscard(function() TM:Select("new") end)
end

-- Saves the shown build, changes included, as a new spec.
local function CopyClicked()
    local default = TM:DraftName() .. " copy"
    UI:AskName("Name the copy:", default:sub(1, 32), function(name) TM:SaveDraft(name) end)
end

local function RenameClicked()
    local spec = ShownSpec()
    if spec then
        UI:AskName(("Rename %s to:"):format(spec.name), spec.name, function(name) TM:RenameSpec(spec.id, name) end)
    end
end

local function DeleteClicked()
    local spec = ShownSpec()
    if spec then
        UI:Confirm(("Delete the spec %s? This can't be undone."):format(spec.name),
            function() TM:DeleteSpec(spec.id) end)
    end
end

local function ImportClicked()
    UI:ConfirmDiscard(function()
        UI:AskLink("Paste a talent calculator link (Wowhead's, or one from Export or /tm link):", "", function(link)
            local ok, reason = TM:Import(link)
            if not ok then
                TM:Print("Can't import that: " .. reason .. ".")
            end
        end)
    end)
end

local function ExportClicked()
    UI:AskLink("Talent link for " .. TM:DraftName() .. ". Press Ctrl+C to copy it.", TM:EncodeDraft(TM.draft))
end

-- Load, or Stop while a load is casting.
local function LoadClicked()
    if TM.casting then
        TM:StopLoad()
        return
    end
    local spec = ShownSpec()
    if spec then
        TM:LoadSpec(spec.id)
    end
end

-- Why Load can't be used now, or nil.
local function LoadBlocker()
    local spec = ShownSpec()
    if not spec then
        return "Pick a saved spec in the list to load it."
    elseif TM.draft.dirty then
        return "Save the changes first."
    elseif TM:LoadedSpec() == spec and not TM:LiveDiffers(spec) then
        return "This spec is already on your character."
    end
end

local function LoadTooltip()
    if TM.casting then
        return "Stop loading the spec. Moving or combat stops it too."
    end
    local blocker = LoadBlocker()
    if blocker then
        return blocker
    end
    local spec = ShownSpec()
    if TM:LoadedSpec() == spec then
        return "Put your talents and glyphs back to " .. spec.name .. "."
    end
    return "Put " .. spec.name .. " on your character, out of combat. Talents that move or come out take a "
        .. "short cast; moving or combat stops it. Glyphs go in with it."
end

local BUTTONS = {
    { key = "new", text = "New", click = NewClicked, tip = "Start a new spec from an empty tree." },
    { key = "copy", text = "Copy", click = CopyClicked,
        tip = "Save the build shown, changes included, as a new spec." },
    { key = "rename", text = "Rename", click = RenameClicked, tip = "Rename the saved spec shown." },
    { key = "delete", text = DELETE or "Delete", click = DeleteClicked, tip = "Delete the saved spec shown." },
    { key = "import", text = "Import", click = ImportClicked,
        tip = "Show a talent calculator link in the tree, to save as a new spec." },
    { key = "export", text = "Export", click = ExportClicked,
        tip = "Show the build as a talent calculator link, to copy." },
}

-- ---------------------------------------------------------------------------------------------------------------
-- Building and updating

function Specs:Build(f)
    panel = CreateFrame("Frame", NAME, f)
    panel:SetWidth(ROW_WIDTH + 28)
    panel:SetPoint("TOPLEFT", f, "TOPRIGHT", -34, -12)
    panel:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -34, 78)
    -- Known now; GetHeight() of an anchored frame can read 0 before its first layout.
    panel.height = f:GetHeight() - 12 - 78
    -- Keep the panel on screen too when the window is dragged to the right edge.
    f:SetClampRectInsets(0, -(ROW_WIDTH + 28 - 34), 0, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        Specs:Update()
    end)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Talent Specs")

    panel.buttons = {}
    for i, def in ipairs(BUTTONS) do
        local button = UI.TooltipButton(panel, NAME .. "Button" .. def.key, 60, def.text, def.tip)
        local column = (i - 1) % 3
        local line = math.floor((i - 1) / 3)
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 15 + column * 62, 40 - line * 24)
        button:SetScript("OnClick", def.click)
        panel.buttons[def.key] = button
    end

    panel.load = UI.TooltipButton(panel, NAME .. "LoadButton", 120, "Load", LoadTooltip)
    panel.load:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 15, 64)
    panel.load:SetScript("OnClick", LoadClicked)

    panel.useLive = UI.TooltipButton(panel, NAME .. "UseLiveButton", 62, "Use live",
        "Copy your live talents and glyphs into this spec as changes; Save keeps them.")
    panel.useLive:SetPoint("LEFT", panel.load, "RIGHT", 2, 0)
    panel.useLive:SetScript("OnClick", function() TM:UseLive() end)

    panel.note = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    panel.note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 90)
    panel.note:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.note:SetHeight(26)
    panel.note:SetJustifyH("LEFT")
    panel.note:SetJustifyV("TOP")

    panel.count = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.count:SetPoint("BOTTOM", panel, "BOTTOM", 0, BUTTONS_HEIGHT + 2)

    panel.offline = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.offline:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -LIST_TOP - ROW_HEIGHT - 8)
    panel.offline:SetPoint("RIGHT", -18, 0)
    panel.offline:SetJustifyH("LEFT")
    panel.offline:SetText("The server doesn't have mod-talent-manager, so specs can't be saved.")
end

local function SetEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

local function FillRow(row, what, icon, name, sub, selected)
    row.what = what
    row.icon:SetTexture(icon)
    row.name:SetText(name)
    row.sub:SetText(sub)
    if selected then
        row.selected:Show()
    else
        row.selected:Hide()
    end
    row:Show()
end

function Specs:Update()
    if not panel then
        return
    end
    local draft = TM.draft
    local rowCount = math.max(2, math.floor((panel.height - LIST_TOP - BUTTONS_HEIGHT - 16) / ROW_HEIGHT))
    local specRows = rowCount - 1
    offset = math.max(0, math.min(offset, #TM.specs - specRows))

    -- The live row: shown live talents may have unsaved changes.
    local live = (draft and draft.source == "live") and draft or TM:LiveDraft()
    local liveName = "Live talents"
    if draft and draft.source == "live" and draft.dirty then
        liveName = liveName .. "*"
    end
    FillRow(rows[1] or MakeRow(1), "live", DraftIcon(live), liveName, TM:Split(live),
        draft and draft.source == "live")

    local group = GetActiveTalentGroup(false, false)
    local otherGroup = group == 1 and 2 or 1
    local loaded = TM:LoadedSpec()
    local liveDiffers = loaded and TM:LiveDiffers(loaded)
    for i = 1, specRows do
        local row = rows[i + 1] or MakeRow(i + 1)
        local spec = TM.specs[i + offset]
        if spec then
            local shown = draft and draft.source == "spec" and draft.specId == spec.id
            local specDraft = shown and draft or spec.draft
            local name = spec.name .. ((shown and draft.dirty) and "*" or "")
            local sub = TM:Split(specDraft)
            if spec == loaded then
                sub = sub .. (liveDiffers and "  |cffffa000Active, changed|r" or "  |cff40ff40Active|r")
            elseif GetNumTalentGroups(false, false) > 1 and TM.loaded[otherGroup] == spec.id then
                sub = sub .. "  |cff9d9d9d" .. (otherGroup == 2 and (TALENT_SPEC_SECONDARY or "Secondary")
                    or (TALENT_SPEC_PRIMARY or "Primary")) .. "|r"
            end
            FillRow(row, spec.id, DraftIcon(specDraft), name, sub, shown)
        else
            row:Hide()
        end
    end
    for i = rowCount + 1, #rows do
        rows[i]:Hide()
    end

    -- A new, unsaved build has no row; nothing is marked then.
    local online = TM.info ~= nil
    if online then
        panel.offline:Hide()
    else
        panel.offline:Show()
    end
    if TM.maxSpecs then
        panel.count:SetText(("%d of %d specs"):format(#TM.specs, TM.maxSpecs))
    else
        panel.count:SetText("")
    end

    local spec = ShownSpec()
    if TM.casting then
        panel.load:SetText(STOP or "Stop")
        SetEnabled(panel.load, true)
    else
        panel.load:SetText("Load")
        SetEnabled(panel.load, online and not LoadBlocker())
    end
    SetEnabled(panel.useLive, online and spec ~= nil and spec == loaded and liveDiffers and not draft.dirty)
    if spec and spec == loaded then
        panel.note:SetText(liveDiffers and "Your live talents or glyphs differ from this spec: Load puts them back, "
            .. "Use live copies them in." or "On your character now.")
    else
        panel.note:SetText("")
    end

    local b = panel.buttons
    SetEnabled(b.new, true)
    SetEnabled(b.copy, online and TM:CanAddSpec())
    SetEnabled(b.rename, online and spec ~= nil)
    SetEnabled(b.delete, online and spec ~= nil)
    SetEnabled(b.import, true)
    SetEnabled(b.export, true)
end

TM:On("WINDOW", function() Specs:Update() end)
TM:On("CAST", function() Specs:Update() end)
TM:On("CASTSTOP", function() Specs:Update() end)
