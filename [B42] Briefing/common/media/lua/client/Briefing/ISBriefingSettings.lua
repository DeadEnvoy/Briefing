if isServer() then return; end

require "PZAPI/ModOptions";
require "ModManager/ModOptions/ModOptionsScreen";

BriefingSettings = {};
BriefingSettings.options = PZAPI.ModOptions:create("Briefing", "Briefing");

if BriefingSettings.options.addImage then
    BriefingSettings.options:addImage("media/ui/ModManager/briefing_preview.png", true);
end

local dateFormat = BriefingSettings.options:addComboBox("dateTimeFormat", "Date & Time Format", "Choose the display format for date and time information.");
dateFormat:addItem("HH:mm - MM DD, YYYY", true);
dateFormat:addItem("YYYY, MM DD - HH:mm", false);

BriefingSettings.options:addTickBox("enableDaysSurvived", "Always display days survived", false, "Show days survived rather than days since the outbreak began.");

if isClient() then return; end

BriefingSettings.options:addTickBox("pauseOnEnd", "Pause game after briefing", false, "Automatically pause the game once the text has finished typing.");