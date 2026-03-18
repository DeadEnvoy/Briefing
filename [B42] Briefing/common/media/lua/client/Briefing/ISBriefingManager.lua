if isServer() then return; end

require "Scenarios/API";
require "Briefing/ISBriefingAPI";

ISBriefingManager = {};

function ISBriefingManager:getLocationName(x, y)
    local gameMode = SAPI and SAPI.Scenarios:getCurrent() or "Zomboid";
    local locations = require("Briefing/ISBriefingLocations");
    for i = #locations, 1, -1 do
        local location = locations[i]
        if (location.mode == gameMode) and (x >= location.startX and x <= location.endX) and (y >= location.startY and y <= location.endY) then
            return getText("UI_Briefing_Location_" .. location.id) .. ", " .. getText("UI_Briefing_KnoxCountry");
        end
    end
    if SAPI and SAPI.Scenarios:getCurrent() ~= "Zomboid" then
        for i = #locations, 1, -1 do
            local location = locations[i]
            if (location.mode == "Zomboid") and (x >= location.startX and x <= location.endX) and (y >= location.startY and y <= location.endY) then
                return getText("UI_Briefing_Location_" .. location.id) .. ", " .. getText("UI_Briefing_KnoxCountry");
            end
        end
    end
    return getText("UI_Briefing_KnoxCountry") .. ", " .. getText("UI_Briefing_Kentucky");
end

function ISBriefingManager:formatTime(time)
    local h = math.floor(time);
    local m = math.floor((time - h) * 60);
    if getCore():getOptionClock24Hour() then
        return string.format("%02d:%02d", h, m);
    else
        local ampm = getText("UI_Time_AM");
        if h >= 12 then
            ampm = getText("UI_Time_PM");
            if h > 12 then
                h = h - 12;
            end
        end
        if h == 0 then
            h = 12;
        end
        return string.format("%02d:%02d %s", h, m, ampm);
    end
end

function ISBriefingManager:getDaysSinceOutbreak()
    local gt = getGameTime()

    local currentTimestamp = os.time{
        year = gt:getYear(),
        month = gt:getMonth() + 1,
        day = gt:getDay() + 1,
        hour = gt:getHour(),
        min = gt:getMinutes(),
        sec = 0
    }

    return math.floor(os.difftime(currentTimestamp, os.time{year=1993, month=7, day=4, hour=9, min=0, sec=0}) / 86400)
end

function ISBriefingManager:show()
    if not getPlayer() or not getPlayer():isAlive() or getPlayer():isAsleep() then
        return;
    end

    local playerObj = getPlayer();
    if not playerObj then return end

    local noPause = false;
    if SAPI and SAPI.Scenarios:getCurrent() ~= "Zomboid" then
        if (SAPI.isNewGame() and (SAPI.Scenarios:getOptionValue("Climate.SnowAtStart") or not SAPI.Scenarios:getOptionValue("Briefing.Pause"))) then
            noPause = true;
        end
    end

    if not isClient() then
        if getGameSpeed() ~= 1 then setGameSpeed(1); end
    end

    local data = { name = nil, date = nil, location = nil, days = nil };
    local startDay = getSandboxOptions():getOptionByName("StartDay"):getValue();
    local startMonth = getSandboxOptions():getOptionByName("StartMonth"):getValue();
    local startYear = getSandboxOptions():getOptionByName("StartYear"):getValue();
    local timeSince = getSandboxOptions():getOptionByName("TimeSinceApo"):getValue() - 1;

    local day = getGameTime():getDay() + 1;
    local month = getGameTime():getMonth() + 1;
    local year = getGameTime():getYear();

    local consistent = ((timeSince == 0) and (startDay == 9 and startMonth == 7 and startYear == 1)) or ((timeSince > 0) and ((year - 1993) * 12 + (month - 7) >= timeSince));

    data.name = playerObj:getFullName();
    
    local strTime = self:formatTime(getGameTime():getTimeOfDay());
    local strMonth = getText("Sandbox_StartMonth_option" .. month);
    local strDate = strMonth .. " " .. day .. ", " .. year;

    local showDays = BriefingSettings and BriefingSettings.options:getOption("enableDaysSurvived"):getValue() or false;
    local dateFormat = BriefingSettings and BriefingSettings.options:getOption("dateTimeFormat"):getValue() or 1;

    if SAPI and SAPI.Scenarios:getCurrent() ~= "Zomboid" then
        ---@diagnostic disable-next-line: cast-local-type
        showDays = SAPI.Scenarios:getOptionValue("Briefing.Days");
    end

    data.date = (dateFormat == 1) and strTime .. " - " .. strDate or year .. ", " .. strMonth .. " " .. day .. " - " .. strTime;

    data.location = self:getLocationName(playerObj:getX(), playerObj:getY());

    if not showDays and consistent then
        data.days = string.format(getText("UI_Briefing_DaysAfterOutbreak"), self:getDaysSinceOutbreak());
    else
        data.days = string.format(getText((getGameTime():getDaysSurvived() + 1) == 1 and "UI_Briefing_Day" or "UI_Briefing_Days"), getGameTime():getDaysSurvived() + 1);
    end

    local lines = { data.name, data.date, data.location, data.days };

    ISBriefingManager.ui = ISBriefingUI:new(lines, noPause); ISBriefingManager.ui:addToUIManager();

    triggerEvent("OnBriefingStart");
end

function ISBriefingManager.onGameStart()
    if getCore():getGameMode() == "Tutorial" or getCore():isChallenge() then return end
    
    if not getActivatedMods():contains("Briefing") and (SAPI and SAPI.Scenarios:getCurrent() == "Zomboid") then return end

    if SAPI and SAPI.Scenarios:getCurrent() ~= "Zomboid" then
        if not SAPI.Scenarios:getOptionValue("Briefing.Show") and not (SAPI.isNewGame() and SAPI.Scenarios:getOptionValue("Climate.SnowAtStart")) then
            return;
        end
    end

    ISBriefingManager:show();
end

Events.OnGameStart.Add(ISBriefingManager.onGameStart);