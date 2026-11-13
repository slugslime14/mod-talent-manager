-- TalentManager swap cast bar: shown while the server counts down a spec load, yours or an altbot's. It is built
-- like the stock casting bar (CastingBarFrameTemplate: border, spark and flash textures, the same colours) and sits
-- where that bar sits. Not the stock bar itself: that one is driven by real spell casts. The server decides when the
-- cast ends or stops; this bar only shows it.

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

-- The state key ("self" or an altbot's guid) whose load the bar shows; fading out once it ended.
local owner, fadeStart

-- Right-click the bar to stop the load.
bar:EnableMouse(true)
bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and owner and not fadeStart then
        TM:WithState(owner, function() TM:StopLoad() end)
    end
end)

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
    if not self.started then
        return
    end
    local progress = self.duration > 0 and math.min(1, (now - self.started) / self.duration) or 1
    self:SetValue(progress)
    spark:SetPoint("CENTER", self, "LEFT", progress * self:GetWidth(), 2)
end)

-- BAR events come for any character (yours or an altbot's): ("start", key, label, seconds), ("stop", key),
-- ("done", key). The bar shows the latest start; a stop or done for someone else's cast leaves it alone.
TM:On("BAR", function(what, key, label, duration)
    if what == "start" then
        owner = key
        bar.started, bar.duration = GetTime(), duration or 0
        fadeStart = nil
        bar:SetAlpha(1)
        bar:SetStatusBarColor(1.0, 0.7, 0.0)
        bar:SetValue(0)
        flash:Hide()
        spark:Show()
        text:SetText(label)
        bar:Show()
    elseif key == owner and bar:IsShown() and not fadeStart then
        owner = nil
        if what == "stop" then
            Finish(1.0, 0.0, 0.0, INTERRUPTED or "Interrupted")
        else
            Finish(0.0, 1.0, 0.0, text:GetText())
        end
    end
end)
