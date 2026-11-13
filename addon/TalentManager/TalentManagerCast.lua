-- TalentManager swap cast bar: shown while the server counts down a spec load. It is built like the stock casting
-- bar (CastingBarFrameTemplate: border, spark and flash textures, the same colours) and sits where that bar sits.
-- Not the stock bar itself: that one is driven by real spell casts. The server decides when the cast ends or stops;
-- this bar only shows it.

local TM = TalentManager

local bar = CreateFrame("StatusBar", "TalentManagerCastBar", UIParent)
bar:SetWidth(195)
bar:SetHeight(13)
bar:SetPoint("CENTER", CastingBarFrame or UIParent, "CENTER", 0, CastingBarFrame and 0 or -200)
bar:SetFrameStrata("HIGH")
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetMinMaxValues(0, 1)
bar:Hide()

local background = bar:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetTexture(0, 0, 0, 0.5)

local border = bar:CreateTexture(nil, "ARTWORK")
border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
border:SetWidth(256)
border:SetHeight(64)
border:SetPoint("TOP", 0, 28)

local text = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
text:SetWidth(185)
text:SetHeight(16)
text:SetPoint("TOP", 0, 5)

local spark = bar:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetWidth(32)
spark:SetHeight(32)

local flash = bar:CreateTexture(nil, "OVERLAY")
flash:SetTexture("Interface\\CastingBar\\UI-CastingBar-Flash")
flash:SetBlendMode("ADD")
flash:SetWidth(256)
flash:SetHeight(64)
flash:SetPoint("TOP", 0, 28)

-- Right-click the bar to stop the load.
bar:EnableMouse(true)
bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and TM.casting then
        TM:StopLoad()
    end
end)

local fadeStart
local FADE_TIME = 0.5

local function Finish(r, g, b, label)
    bar:SetStatusBarColor(r, g, b)
    bar:SetValue(1)
    spark:Hide()
    flash:SetAlpha(0)
    flash:Show()
    text:SetText(label)
    fadeStart = GetTime()
end

bar:SetScript("OnUpdate", function(self)
    local now = GetTime()
    local casting = TM.casting
    if fadeStart then
        local t = (now - fadeStart) / FADE_TIME
        if t >= 1 then
            fadeStart = nil
            self:Hide()
            return
        end
        flash:SetAlpha(math.min(1, t * 2))
        self:SetAlpha(1 - t)
        return
    end
    if not casting then
        return
    end
    local progress = casting.duration > 0 and math.min(1, (now - casting.started) / casting.duration) or 1
    self:SetValue(progress)
    spark:SetPoint("CENTER", self, "LEFT", progress * self:GetWidth(), 2)
end)

TM:On("CAST", function()
    local casting = TM.casting
    local spec = casting and TM.specById[casting.specId]
    fadeStart = nil
    bar:SetAlpha(1)
    bar:SetStatusBarColor(1.0, 0.7, 0.0)
    bar:SetValue(0)
    flash:Hide()
    spark:Show()
    text:SetText("Loading " .. (spec and spec.name or "spec"))
    bar:Show()
end)

TM:On("CASTSTOP", function()
    if bar:IsShown() then
        Finish(1.0, 0.0, 0.0, INTERRUPTED or "Interrupted")
    end
end)

TM:On("LOADED", function()
    if bar:IsShown() then
        Finish(0.0, 1.0, 0.0, text:GetText())
    end
end)
