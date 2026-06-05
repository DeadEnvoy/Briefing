require "Briefing/ISBriefingLocations";

BriefingAPI = {};

function BriefingAPI.isActive()
    return ISBriefingUI and ISBriefingUI.instance ~= nil and not ISBriefingUI.instance.isFinished;
end

BriefingAPI.Locations = {};

function BriefingAPI.Locations:add(gameMode, id, startX, endX, startY, endY)
    for i, v in ipairs(BriefingLocations) do
        if (v.mode == gameMode) and (v.id == id) then
            return;
        end
    end

    local location = {};
    location.mode = gameMode;
    location.id = id;
    location.startX = startX;
    location.endX = endX;
    location.startY = startY;
    location.endY = endY;

    table.insert(BriefingLocations, location);
end

LuaEventManager.AddEvent("OnBriefingStart");
LuaEventManager.AddEvent("OnBriefingEnd");