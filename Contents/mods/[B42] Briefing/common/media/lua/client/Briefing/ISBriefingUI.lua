require "ISUI/ISPanel";
require "JoyPad/JoyPadSetup";
require "ISUI/ISBackButtonWheel";
require "Briefing/ISBriefingAPI";

ISBriefingUI = ISPanel:derive("ISBriefingUI");

local function getLocationName(x, y)
    local locations = require("Briefing/ISBriefingLocations");
    if SAPI and SAPI.isScenario() then
        local gameMode = SAPI.Scenarios:getCurrent()
        for i = #locations, 1, -1 do
            local location = locations[i]
            if (location.mode == gameMode) and (x >= location.startX and x <= location.endX) and (y >= location.startY and y <= location.endY) then
                return getText("UI_Briefing_Location_" .. location.id) .. ", " .. getText("UI_Briefing_KnoxCountry");
            end
        end
    end
    for i = #locations, 1, -1 do
        local location = locations[i]
        if (location.mode == "Zomboid") and (x >= location.startX and x <= location.endX) and (y >= location.startY and y <= location.endY) then
            return getText("UI_Briefing_Location_" .. location.id) .. ", " .. getText("UI_Briefing_KnoxCountry");
        end
    end
    return getText("UI_Briefing_KnoxCountry") .. ", " .. getText("UI_Briefing_Kentucky");
end

local function formatTime(time)
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

local function getDaysSinceOutbreak()
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

local function getTimeAfterOutbreakText(days)
    if days < 365 then
        return getText("UI_Briefing_DaysAfterOutbreak", days);
    end

    local years = math.floor(days / 365);
    if getCore():getOptionLanguageName() == "RU" then
        local lastTwoDigits = years % 100;
        local lastDigit = years % 10;

        if lastTwoDigits >= 11 and lastTwoDigits <= 14 then
            return getText("UI_Briefing_Years_AfterOutbreak", years);
        elseif lastDigit == 1 then
            return getText("UI_Briefing_Year_1_AfterOutbreak", years);
        elseif lastDigit >= 2 and lastDigit <= 4 then
            return getText("UI_Briefing_Year_2_AfterOutbreak", years);
        end
    elseif years == 1 then
        return getText("UI_Briefing_Year_1_AfterOutbreak", years);
    end

    return getText("UI_Briefing_Years_AfterOutbreak", years);
end

local _originalJoypadDisconnectedUI_new = ISJoypadDisconnectedUI.new;
ISJoypadDisconnectedUI.new = function(self, playerNum)
    if BriefingAPI.isActive() then
        return {
            setAlwaysOnTop = function() end,
            addToUIManager = function() end,
            removeFromUIManager = function() end
        };
    end
    return _originalJoypadDisconnectedUI_new(self, playerNum);
end

local _originalOnPressButtonNoFocus = JoypadControllerData.onPressButtonNoFocus;
JoypadControllerData.onPressButtonNoFocus = function(self, button)
    if BriefingAPI.isActive() then
        return;
    end
    _originalOnPressButtonNoFocus(self, button);
end

local function utf8_len(s)
    local len = 0;
    local i = 1;
    while i <= #s do
        local byte = string.byte(s, i);
        local step = 1;
        if byte >= 192 and byte <= 223 then
            step = 2;
        elseif byte >= 224 and byte <= 239 then
            step = 3;
        elseif byte >= 240 and byte <= 247 then
            step = 4;
        end
        i = i + step;
        len = len + 1;
    end
    return len;
end

local function utf8_sub(s, start, num)
    if not s or num <= 0 then return ""; end
    local i = 1;
    local charIdx = 1;
    local startByte = nil;
    local endByte = 0;
    while i <= #s do
        if charIdx == start then startByte = i; end
        local byte = string.byte(s, i);
        local step = 1;
        if byte >= 192 and byte <= 223 then
            step = 2;
        elseif byte >= 224 and byte <= 239 then
            step = 3;
        elseif byte >= 240 and byte <= 247 then
            step = 4;
        end
        if charIdx == start + num - 1 then
            endByte = i + step - 1;
            break;
        end
        i = i + step;
        charIdx = charIdx + 1;
    end
    if not startByte then return ""; end
    if endByte == 0 then endByte = #s; end
    return string.sub(s, startByte, endByte);
end

local function setZombiesUseless(value)
    local zombieList = getCell():getZombieList();
    for i = 0, zombieList:size() - 1 do
        local zombie = zombieList:get(i);
        if zombie and zombie:isAlive() then
            if value then
                zombie:setTarget(nil);
            end
            zombie:setCanWalk(value);
            zombie:setUseless(value);
        end
    end
end

function ISBriefingUI:initialise()
    ISPanel.initialise(self);

    if ISMoodlesInLuaHandle then
        ISMoodlesInLuaHandle:setVisible(false);
    end

    if MF and MF.MoodlesStorage then
        for _, playerMoodles in pairs(MF.MoodlesStorage) do
            for _, moodle in pairs(playerMoodles) do
                if moodle.setVisible then
                    moodle:setVisible(false);
                end
            end
        end
    end

    self.isVolumeFadingOut = true;

    getCore():setOptionVehicleEngineVolume(0);

    local bodyDamage = self.player:getBodyDamage();
    local count = bodyDamage:getBodyParts():size();
    local snapshotParts = {};

    for i = 0, count - 1 do
        local bodyPart = bodyDamage:getBodyPart(BodyPartType.FromIndex(i));
        snapshotParts[i + 1] = {
            health = bodyPart:getHealth(),
            bleedingTime = bodyPart:getBleedingTime(),
            cutTime = bodyPart:getCutTime(),
            biteTime = bodyPart:getBiteTime(),
            scratchTime = bodyPart:getScratchTime(),
            deepWoundTime = bodyPart:getDeepWoundTime(),
            burnTime = bodyPart:getBurnTime(),
            stitchTime = bodyPart:getStitchTime(),
            fractureTime = bodyPart:getFractureTime(),
            woundInfectionLevel = bodyPart:isInfectedWound() and bodyPart:getWoundInfectionLevel() or 0,
        };
    end

    self.snapshotParts = snapshotParts;
    self.snapshotInfectionTime = bodyDamage:getInfectionTime();
    self.snapshotInfectionMortalityDuration = bodyDamage:getInfectionMortalityDuration();

    local stats = self.player:getStats();
    self.snapshotStats = {
        hunger = stats:get(CharacterStat.HUNGER),
        thirst = stats:get(CharacterStat.THIRST),
        fatigue = stats:get(CharacterStat.FATIGUE),
        endurance = stats:get(CharacterStat.ENDURANCE),
        boredom = stats:get(CharacterStat.BOREDOM),
        unhappiness = stats:get(CharacterStat.UNHAPPINESS),
        discomfort = stats:get(CharacterStat.DISCOMFORT),
        wetness = stats:get(CharacterStat.WETNESS),
        temperature = stats:get(CharacterStat.TEMPERATURE),
        sickness = stats:get(CharacterStat.SICKNESS),
        foodSickness = stats:get(CharacterStat.FOOD_SICKNESS),
        poison = stats:get(CharacterStat.POISON),
        nicotineWithdrawal = stats:get(CharacterStat.NICOTINE_WITHDRAWAL),
    };

    self.snapshotTimeSinceLastSmoke = self.player:getTimeSinceLastSmoke();
    self.snapshotCatchACold = bodyDamage:getCatchACold();
    self.snapshotColdStrength = bodyDamage:getColdStrength();
    self.snapshotColdDamageStage = bodyDamage:getColdDamageStage();

    local nutrition = self.player:getNutrition();
    self.snapshotNutrition = {
        carbohydrates = nutrition:getCarbohydrates(),
        lipids = nutrition:getLipids(),
        proteins = nutrition:getProteins(),
        calories = nutrition:getCalories(),
    };

    self.snapshotHealthFromFoodTimer = bodyDamage:getHealthFromFoodTimer();

    if isClient() then
        self.player:setInvisible(true);
        self.player:setGhostMode(true, true);
        self.player:setNoClip(true, true);
        self.player:setZombiesDontAttack(true);
        self.player:setShootable(false);

        self.oldVoiceMode = getCore():getOptionVoiceMode();
        self.oldVoiceVol = getCore():getOptionVoiceVolumePlayers();

        getCore():setOptionVoiceMode(3);
        getCore():setOptionVoiceVolumePlayers(0);

        if ISChat and ISChat.instance then
            self.wasChatVisible = ISChat.instance:isVisible();
            ISChat.instance:setVisible(false);
        end
    else
        setZombiesUseless(true);
    end

    if self.player.setBlockMovement then
        self.player:setBlockMovement(true);
    end
    if self.player.setIgnoreMovement then
        self.player:setIgnoreMovement(true);
    end

    if GameKeyboard.setDoLuaKeyPressed then
        GameKeyboard.setDoLuaKeyPressed(false);
    end
    if GameKeyboard.noEventsWhileLoading ~= nil then
        GameKeyboard.noEventsWhileLoading = true;
    end

    if JoypadState then
        if JoypadState.disableControllerPrompt ~= nil then
            JoypadState.disableControllerPrompt = true;
        end
        if JoypadState.disableMovement ~= nil then
            JoypadState.disableMovement = true;
        end
    end

    if ISBackButtonWheel then
        if ISBackButtonWheel.disablePlayerInfo ~= nil then
            ISBackButtonWheel.disablePlayerInfo = true;
        end
        if ISBackButtonWheel.disableCrafting ~= nil then
            ISBackButtonWheel.disableCrafting = true;
        end
        if ISBackButtonWheel.disableTime ~= nil then
            ISBackButtonWheel.disableTime = true;
        end
        if ISBackButtonWheel.disableMoveable ~= nil then
            ISBackButtonWheel.disableMoveable = true;
        end
    end

    local joypadData = JoypadState.players[self.player:getPlayerNum() + 1];
    if joypadData and joypadData.isActive then
        self.joypadData = joypadData;
        setJoypadFocus(self.player:getPlayerNum(), self);
    end

    Events.OnTickEvenPaused.Add(ISBriefingUI.onTick);
end

function ISBriefingUI.onTick()
    local self = ISBriefingUI.instance;

    self:updateVolumeFade();

    if self.isFinished then return; end

    if self.player:isOnFire() then
        self.player:StopBurning();
    end

    if not isClient() then
        local bodyDamage = self.player:getBodyDamage();
        bodyDamage:setHealthReductionFromSevereBadMoodles(0);
        bodyDamage:setStandardHealthAddition(0);

        local dirty = false;

        for i = 0, bodyDamage:getBodyParts():size() - 1 do
            local bodyPart = bodyDamage:getBodyPart(BodyPartType.FromIndex(i));
            local partData = self.snapshotParts[i + 1];
            if partData then
                if bodyPart:getHealth() ~= partData.health then
                    bodyPart:SetHealth(partData.health);
                    dirty = true;
                end
                if bodyPart:getBurnTime() ~= partData.burnTime then
                    bodyPart:setBurnTime(partData.burnTime);
                    dirty = true;
                end
                if bodyPart:getBleedingTime() ~= partData.bleedingTime then
                    bodyPart:setBleedingTime(partData.bleedingTime);
                    dirty = true;
                end
                if bodyPart:getDeepWoundTime() ~= partData.deepWoundTime then
                    bodyPart:setDeepWoundTime(partData.deepWoundTime);
                    dirty = true;
                end
                if bodyPart:getFractureTime() ~= partData.fractureTime then
                    bodyPart:setFractureTime(partData.fractureTime);
                    dirty = true;
                end
                if bodyPart:getWoundInfectionLevel() ~= partData.woundInfectionLevel then
                    bodyPart:setWoundInfectionLevel(partData.woundInfectionLevel);
                    dirty = true;
                end
            end
        end

        setZombiesUseless(true);

        if dirty then
            bodyDamage:calculateOverallHealth();
        end

        if self.snapshotStats then
            local stats = self.player:getStats();
            stats:set(CharacterStat.HUNGER, self.snapshotStats.hunger);
            stats:set(CharacterStat.THIRST, self.snapshotStats.thirst);
            stats:set(CharacterStat.FATIGUE, self.snapshotStats.fatigue);
            stats:set(CharacterStat.ENDURANCE, self.snapshotStats.endurance);
            stats:set(CharacterStat.BOREDOM, self.snapshotStats.boredom);
            stats:set(CharacterStat.UNHAPPINESS, self.snapshotStats.unhappiness);
            stats:set(CharacterStat.DISCOMFORT, self.snapshotStats.discomfort);
            stats:set(CharacterStat.WETNESS, self.snapshotStats.wetness);
            stats:set(CharacterStat.TEMPERATURE, self.snapshotStats.temperature);
            stats:set(CharacterStat.SICKNESS, self.snapshotStats.sickness);
            stats:set(CharacterStat.FOOD_SICKNESS, self.snapshotStats.foodSickness);
            stats:set(CharacterStat.POISON, self.snapshotStats.poison);
            stats:set(CharacterStat.NICOTINE_WITHDRAWAL, self.snapshotStats.nicotineWithdrawal);
        end

        if self.snapshotTimeSinceLastSmoke ~= nil then
            self.player:setTimeSinceLastSmoke(self.snapshotTimeSinceLastSmoke);
        end

        if self.snapshotNutrition then
            local nutrition = self.player:getNutrition();
            nutrition:setCarbohydrates(self.snapshotNutrition.carbohydrates);
            nutrition:setLipids(self.snapshotNutrition.lipids);
            nutrition:setProteins(self.snapshotNutrition.proteins);
            nutrition:setCalories(self.snapshotNutrition.calories);
        end

        if self.snapshotCatchACold ~= nil then
            bodyDamage:setCatchACold(self.snapshotCatchACold);
        end

        if self.snapshotColdStrength ~= nil then
            bodyDamage:setColdStrength(self.snapshotColdStrength);
        end

        if self.snapshotColdDamageStage ~= nil then
            bodyDamage:setColdDamageStage(self.snapshotColdDamageStage);
        end

        if self.snapshotHealthFromFoodTimer ~= nil then
            bodyDamage:setHealthFromFoodTimer(self.snapshotHealthFromFoodTimer);
        end
        
        if isGamePaused() then
            setGameSpeed(1);
        end

        if self.tickDelay > 5 and not self.noPause then
            GameTime.getInstance():setMultiplier(0.0);
        end
    end
end

function ISBriefingUI:update()
    ISPanel.update(self);
    self:updateCursor();

    if self.player:isDead() and not self.fadeStartTime then
        self:skipAnimation();
        return;
    end

    if not self.isFinished and self.tickDelay < 60 then
        self.tickDelay = self.tickDelay + 1;
    end

    if isClient() and (not self.fadeStartTime and not self.isFinished) and not self.sentStartCommand then
        if self.player:getSquare() and self.player:getOnlineID() ~= -1 and self.tickDelay > 5 then
            sendClientCommand(self.player, "Briefing", "setBriefingActive", {
                active = true,
                parts = self.snapshotParts,
                infectionTime = self.snapshotInfectionTime,
                infectionMortalityDuration = self.snapshotInfectionMortalityDuration,
                stats = self.snapshotStats,
                timeSinceLastSmoke = self.snapshotTimeSinceLastSmoke,
                catchACold = self.snapshotCatchACold,
                coldStrength = self.snapshotColdStrength,
                coldDamageStage = self.snapshotColdDamageStage,
                nutrition = self.snapshotNutrition,
                healthFromFoodTimer = self.snapshotHealthFromFoodTimer,
            });
            self.sentStartCommand = true;
        end
    end

    if not self.isTypingComplete and not self.skipRequested then
        self:updateTyping();
        return;
    end

    if self.holdStartTime and not self.fadeStartTime and not self.skipRequested then
        local timestamp = getTimestampMs();
        local elapsed = (timestamp - self.holdStartTime) / 1000.0;
        if elapsed >= self.holdDuration then
            self.fadeStartTime = timestamp;
        end
    end

    if self.fadeStartTime then
        if not self.isFinished then
            self:restoreGame();
        end
        self:updateFadeOut();
    end
end

function ISBriefingUI:updateVolumeFade()
    local sm = getSoundManager();
    local timestamp = getTimestampMs();

    if self.typingFadeStartTime and self.soundInstance then
        local elapsed = (timestamp - self.typingFadeStartTime) / 1000.0;
        local progress = math.min(1.0, elapsed / 0.250);
        local fade = 1.0 - progress; fade = fade * fade;

        local emitter = sm:getUIEmitter();
        emitter:setVolume(self.soundInstance, (self.oldSoundVol / 10) * fade);

        if progress >= 1.0 then
            emitter:stopSound(self.soundInstance);
            self.soundInstance = nil;
            self.typingFadeStartTime = nil;
        end
    end

    if self.isVolumeFadingOut then
         if not self.volumeFadeStartTime then
            self.volumeFadeStartTime = timestamp;
        end

        local elapsed = (timestamp - self.volumeFadeStartTime) / 1000.0;
        local progress = math.min(1.0, elapsed / 1.0);
        local fade = 1.0 - progress; fade = fade * fade;

        sm:setSoundVolume((self.oldSoundVol / 10) * fade);
        sm:setMusicVolume((self.oldMusicVol / 10) * fade);

        if progress >= 1.0 then
            getCore():setOptionSoundVolume(0);
            getCore():setOptionMusicVolume(0);
            
            self.isVolumeFadingOut = false;
        end
    elseif not self.isFinished then
        if sm:getSoundVolume() ~= 0 then
            sm:setSoundVolume(0);
        end
        if sm:getMusicVolume() ~= 0 then
            sm:setMusicVolume(0);
        end
        if sm:getVehicleEngineVolume() ~= 0 then
            sm:setVehicleEngineVolume(0);
        end

        if isClient() and getCore():getOptionVoiceMode() ~= 3 then
            getCore():setOptionVoiceMode(3);
        end
        if isClient() and getCore():getOptionVoiceVolumePlayers() ~= 0 then
            getCore():setOptionVoiceVolumePlayers(0);
        end
    end
end

local RadioWavs = require("RadioCom/RadioWavs");
if RadioWavs and RadioWavs.adjustSounds then
    Events.OnTick.Remove(RadioWavs.adjustSounds);
    local _originalRadioWavs_adjustSounds = RadioWavs.adjustSounds;
    function RadioWavs.adjustSounds()
        if BriefingAPI.isActive() then
            if RadioWavs.soundCache then
                for _, t in ipairs(RadioWavs.soundCache) do
                    if t.sound and t.sound.setVolume then
                        t.sound:setVolume(0);
                    end
                end
            end
            return;
        end
        _originalRadioWavs_adjustSounds();
    end
    Events.OnTick.Add(RadioWavs.adjustSounds);
end

require "MuffleSound";
if _G._Muffle_OnPlayerUpdate then
    Events.OnPlayerUpdate.Remove(_G._Muffle_OnPlayerUpdate);
    local _original_onPlayerUpdate = _G._Muffle_OnPlayerUpdate;
    function _G._Muffle_OnPlayerUpdate(player)
        if BriefingAPI.isActive() then
            return;
        end
        _original_onPlayerUpdate(player);
    end
    Events.OnPlayerUpdate.Add(_G._Muffle_OnPlayerUpdate);
end

function ISBriefingUI:prerender()
    ISPanel.prerender(self);
    local alpha = math.max(0.0, math.min(1.0, self.alpha));
    self:drawRect(0, 0, self.width, self.height, alpha, 0, 0, 0);

    local y = self.height / 2 - self.textBlockHeight / 2;
    for i,_ in ipairs(self.lines) do
        local display = self:getDisplayText(i);
        if #display > 0 then
            local x = self.width / 2;
            self:drawTextCentre(display, x + 2, y + 12, 0, 0, 0, alpha * 0.7, self.font);
            self:drawTextCentre(display, x, y + 10, 1, 1, 1, alpha, self.font);
        end
        y = y + self.fontHgt + 5;
    end
end

function ISBriefingUI:onMouseDown()
    if not self.isFinished then
        if (not self.joypadData and not self.noPause) and self.typingStarted then
            self:skipAnimation();
        end
        return true;
    end
    return false;
end

function ISBriefingUI:onMouseWheel()
    if not self.isFinished then
        return true;
    end
    return false;
end

function ISBriefingUI:onRightMouseDown()
    if not self.isFinished then
        if (not self.joypadData and not self.noPause) and self.typingStarted then
            self:skipAnimation();
        end
        return true;
    end
    return false;
end

function ISBriefingUI:onKeyPress(key)
    if not self.isFinished then
        GameKeyboard.eatKeyPress(key);
        if ((not self.joypadData and not self.noPause) and key == Keyboard.KEY_ESCAPE) and self.typingStarted then
            self:skipAnimation();
        end
        return true;
    end
    return false;
end

function ISBriefingUI:onJoypadDown(button, joypadData)
    local elapsed = (getTimestampMs() - self.startTime) / 1000.0;
    if elapsed < 1.75 then return true; end
    if not self.isFinished then
        if (not self.noPause and button == Joypad.AButton) and self.typingStarted then
            self:skipAnimation();
        end
        return true;
    end
    return false;
end

function ISBriefingUI:onJoypadDirUp() return true; end

function ISBriefingUI:onJoypadDirDown() return true; end

function ISBriefingUI:onJoypadDirLeft() return true; end

function ISBriefingUI:onJoypadDirRight() return true; end

function ISBriefingUI:skipAnimation()
    if self.fadeStartTime then
        return;
    end
    self.skipRequested = true;
    self.fadeStartTime = getTimestampMs();

    if not self.isTypingComplete then
        self.currentCharIndex = self.totalSymbols;
        self.isTypingComplete = true;
        self.holdStartTime = self.fadeStartTime;
        self.showCursor = false;
    end
end

function ISBriefingUI:restoreGame()
    if self.isFinished then return; end

    if ISMoodlesInLuaHandle then
        ISMoodlesInLuaHandle:setVisible(true);
    end

    if MF and MF.MoodlesStorage then
        for _, playerMoodles in pairs(MF.MoodlesStorage) do
            for _, moodle in pairs(playerMoodles) do
                if moodle.setVisible then
                    moodle:setVisible(true);
                end
            end
        end
    end

    local sm = getSoundManager();
    local emitter = sm:getUIEmitter();
    if self.soundInstance then
        emitter:stopSound(self.soundInstance);
        self.soundInstance = nil;
    end

    self.isVolumeFadingOut = false;

    getCore():setOptionSoundVolume(self.oldSoundVol);
    getCore():setOptionMusicVolume(self.oldMusicVol);
    getCore():setOptionVehicleEngineVolume(self.oldVehicleVol);

    sm:setSoundVolume(self.oldSoundVol / 10);
    sm:setMusicVolume(self.oldMusicVol / 10);
    sm:setVehicleEngineVolume(self.oldVehicleVol / 10);

    if self.player.setBlockMovement then
        self.player:setBlockMovement(false);
    end
    if self.player.setIgnoreMovement then
        self.player:setIgnoreMovement(false);
    end

    if GameKeyboard.setDoLuaKeyPressed then
        GameKeyboard.setDoLuaKeyPressed(true);
    end
    if GameKeyboard.noEventsWhileLoading ~= nil then
        GameKeyboard.noEventsWhileLoading = false;
    end

    if JoypadState then
        if JoypadState.disableControllerPrompt ~= nil then
            JoypadState.disableControllerPrompt = false;
        end
        if JoypadState.disableMovement ~= nil then
            JoypadState.disableMovement = false;
        end
    end

    if ISBackButtonWheel then
        if ISBackButtonWheel.disablePlayerInfo ~= nil then
            ISBackButtonWheel.disablePlayerInfo = false;
        end
        if ISBackButtonWheel.disableCrafting ~= nil then
            ISBackButtonWheel.disableCrafting = false;
        end
        if ISBackButtonWheel.disableTime ~= nil then
            ISBackButtonWheel.disableTime = false;
        end
        if ISBackButtonWheel.disableMoveable ~= nil then
            ISBackButtonWheel.disableMoveable = false;
        end
    end

    if self.joypadData then
        setJoypadFocus(self.player:getPlayerNum(), nil);
    end

    if isClient() then
        self.player:setInvisible(false);
        self.player:setGhostMode(false, true);
        self.player:setNoClip(false, true);
        self.player:setZombiesDontAttack(false);
        self.player:setShootable(true);

        if self.sentStartCommand then
            sendClientCommand(self.player, "Briefing", "setBriefingActive", { active = false });
        end

        getCore():setOptionVoiceMode(self.oldVoiceMode);
        getCore():setOptionVoiceVolumePlayers(self.oldVoiceVol);

        if (ISChat and ISChat.instance) and self.wasChatVisible then
            ISChat.instance:setVisible(true);
        end
    else
        if BriefingSettings and BriefingSettings.options:getOption("pauseOnEnd"):getValue() then
            setGameSpeed(0);
        else
            setGameSpeed(1);
        end

        local bodyDamage = self.player:getBodyDamage();
        bodyDamage:setHealthReductionFromSevereBadMoodles(0.0165);
        bodyDamage:setStandardHealthAddition(0.002);

        setZombiesUseless(false);
    end

    if self.joypadData and not self.joypadData.controller.connected then
        local ui = _originalJoypadDisconnectedUI(ISJoypadDisconnectedUI, self.player:getPlayerNum());
        ---@diagnostic disable-next-line: redundant-parameter
        ui:setAlwaysOnTop(true);
        ui:addToUIManager();
        self.joypadData.disconnectedUI = ui;
    end

    self.isFinished = true;

    triggerEvent("OnBriefingEnd");
end

function ISBriefingUI:updateCursor()
    if self.isTypingComplete then
        self.showCursor = false;
        return;
    end
    self.showCursor = true;
end

function ISBriefingUI:updateTyping()
    if self.isTypingComplete or self.skipRequested then return; end

    if not self.typingStarted then
        local timestamp = getTimestampMs();
        local elapsed = (timestamp - self.startTime) / 1000.0;
        if elapsed >= self.fadeInDuration then
            local data = { name = self.player:getFullName(), date = nil, location = nil, days = nil };

            local startDay = getSandboxOptions():getOptionByName("StartDay"):getValue();
            local startMonth = getSandboxOptions():getOptionByName("StartMonth"):getValue();
            local startYear = getSandboxOptions():getOptionByName("StartYear"):getValue() + 1992;
            local timeSince = getSandboxOptions():getOptionByName("TimeSinceApo"):getValue() - 1;

            local day = getGameTime():getDay() + 1;
            local month = getGameTime():getMonth() + 1;
            local year = getGameTime():getYear();

            local startMonthsSinceOutbreak = (startYear - 1993) * 12 + (startMonth - 7);
            local isAfterOutbreak = startYear > 1993 or (startYear == 1993 and (startMonth > 7 or (startMonth == 7 and startDay >= 4)));
            local matchesTimeSince = (timeSince == 12 and startMonthsSinceOutbreak >= timeSince) or (timeSince ~= 12 and startMonthsSinceOutbreak == timeSince);

            local strTime = formatTime(getGameTime():getTimeOfDay());
            local strMonth = getText("Sandbox_StartMonth_option" .. month);
            local strDate = strMonth .. " " .. day .. ", " .. year;

            local showDays = BriefingSettings and BriefingSettings.options:getOption("enableDaysSurvived"):getValue() or false;
            local dateFormat = BriefingSettings and BriefingSettings.options:getOption("dateTimeFormat"):getValue() or 1;

            if SAPI and SAPI.isScenario() then
                ---@diagnostic disable-next-line: cast-local-type
                showDays = SAPI.Scenarios:getOptionValue("Briefing.Days");
            end

            data.date = (dateFormat == 1) and (strTime .. " - " .. strDate) or (year .. ", " .. strMonth .. " " .. day .. " - " .. strTime);

            data.location = getLocationName(self.player:getX(), self.player:getY());

            if not showDays and (isAfterOutbreak and matchesTimeSince) then
                data.days = getTimeAfterOutbreakText(getDaysSinceOutbreak());
            else
                data.days = getText("UI_Briefing_Day", getGameTime():getDaysSurvived() + 1);
            end

            self.lines = { data.name, data.date, data.location, data.days };

            local total = 0;
            for _, line in ipairs(self.lines) do
                total = total + utf8_len(line);
            end
            self.totalSymbols = total;
            self.textBlockHeight = #self.lines * (self.fontHgt + 5) + 20;

            self.typingStarted = true;
        else
            return;
        end
    end

    if self.currentCharIndex < self.totalSymbols then
        self.currentCharIndex = self.currentCharIndex + 1;
        if self.currentCharIndex > 1 and not self.soundInstance then
            local emitter = getSoundManager():getUIEmitter();
            self.soundInstance = getSoundManager():playUISound("Typing_Sound");
            if self.soundInstance and self.soundInstance ~= 0 then
                emitter:setVolume(self.soundInstance, self.oldSoundVol / 10);
            end
        end
    else
        self.isTypingComplete = true;
        self.typingFadeStartTime = getTimestampMs();
        self.holdStartTime = getTimestampMs();
    end
end

function ISBriefingUI:removeFromUIManager()
    if not self.isFinished then
        self:restoreGame();
    end

    ISPanel.removeFromUIManager(self);
end

function ISBriefingUI:updateFadeOut()
    if not self.fadeStartTime then return; end

    local timestamp = getTimestampMs();
    local elapsed = (timestamp - self.fadeStartTime) / 1000.0;
    local progress = elapsed / self.fadeOutDuration;

    self.alpha = math.max(0.0, self.fadeOutDuration - progress);

    if elapsed >= self.fadeOutDuration then
        self:removeFromUIManager();
        return true;
    end
    return false;
end

function ISBriefingUI:getDisplayText(index)
    if not self.typingStarted and not self.skipRequested then return ""; end
    if self.isTypingComplete or self.skipRequested then return self.lines[index]; end

    local charsBefore = 0;
    for i = 1, index - 1 do
        charsBefore = charsBefore + utf8_len(self.lines[i]);
    end

    local charsInThisLine = self.currentCharIndex - charsBefore;
    local lineLength = utf8_len(self.lines[index]);

    if charsInThisLine <= 0 then return ""; end
    if charsInThisLine >= lineLength then return self.lines[index]; end

    local visibleText = utf8_sub(self.lines[index], 1, charsInThisLine);
    if self.showCursor then
        visibleText = visibleText .. "_";
    end
    return visibleText;
end

function ISBriefingUI:destroy()
    ISPanel.destroy(self);
end

function ISBriefingUI:show()
    if getCore():getGameMode() == "Tutorial" or getCore():isChallenge() then return; end

    if (SAPI and SAPI.isScenario()) and not SAPI.Scenarios:getOptionValue("Briefing.Show") then
        return;
    end

    if not getPlayer() or not getPlayer():isAlive() or getPlayer():isAsleep() then
        return;
    end

    if BriefingAPI.isActive() then
        return;
    end

    local ui = ISBriefingUI:new();
    ui:addToUIManager();

    triggerEvent("OnBriefingStart");
end

function ISBriefingUI:new()
    local o = ISPanel:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight());
    setmetatable(o, self);
    self.__index = self;
    o.lines = {};
    o:noBackground();
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 };

    o:setAlwaysOnTop(true);
    o:setWantKeyEvents(true);
    o:setJoypadFocused(true);
    o:setCapture(true);
    o:setVisible(true);

    o.noPause = false;
    if (SAPI and SAPI.Scenarios:getCurrent() ~= "Zomboid") and not SAPI.Scenarios:getOptionValue("Briefing.Pause") then
        o.noPause = true;
    end

    o.tickDelay = 0;
    o.holdDuration = 1.0;
    o.fadeOutDuration = 1.0;
    o.fadeInDuration = 1.0;

    o.typingStarted = false;
    o.currentCharIndex = 0;
    o.isTypingComplete = false;

    o.holdStartTime = nil;
    o.fadeStartTime = nil;

    o.isFinished = false;
    o.startTime = getTimestampMs();
    o.alpha = 1.0;
    o.showCursor = true;
    o.sentStartCommand = false;
    o.skipRequested = false;
    o.joypadData = nil;

    o.font = UIFont.Large;
    o.fontHgt = getTextManager():getFontHeight(o.font);
    o.totalSymbols = 0;
    o.textBlockHeight = 20;

    o.soundInstance = nil;
    o.isVolumeFadingOut = false;
    o.volumeFadeStartTime = nil;
    o.typingFadeStartTime = nil;

    o.oldSoundVol = getCore():getOptionSoundVolume();
    o.oldMusicVol = getCore():getOptionMusicVolume();
    o.oldVehicleVol = getCore():getOptionVehicleEngineVolume();

    o.player = getPlayer();

    ISBriefingUI.instance = o;

    o:initialise();
    return o;
end

Events.OnGameStart.Add(ISBriefingUI.show);