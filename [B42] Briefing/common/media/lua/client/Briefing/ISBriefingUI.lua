if isServer() then return; end

require "ISUI/ISPanel";
require "JoyPad/JoyPadSetup";
require "ISUI/ISBackButtonWheel";
require "Briefing/ISBriefingAPI";

ISBriefingUI = ISPanel:derive("ISBriefingUI");

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
        if byte >= 192 and byte <= 223 then step = 2;
        elseif byte >= 224 and byte <= 239 then step = 3;
        elseif byte >= 240 and byte <= 247 then step = 4; end
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
        if byte >= 192 and byte <= 223 then step = 2;
        elseif byte >= 224 and byte <= 239 then step = 3;
        elseif byte >= 240 and byte <= 247 then step = 4; end
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

local function setVehicleStatic(value)
    local vehicle = getPlayer():getVehicle();
    if vehicle then
        vehicle:setPhysicsActive(not value);
    end
end

function ISBriefingUI:initialise()
    ISPanel.initialise(self);

    if ISMoodlesInLuaHandle then
        ISMoodlesInLuaHandle:setVisible(false);
    end

    self.isVolumeFadingOut = true;
    self.volumeFadeStartTime = getTimestampMs();

    self.player:setBlockMovement(true);
    self.player:setIgnoreMovement(true);

    GameKeyboard.setDoLuaKeyPressed(false);
    GameKeyboard.noEventsWhileLoading = true;

    JoypadState.disableControllerPrompt = true;
    JoypadState.disableMovement = true;

    ISBackButtonWheel.disablePlayerInfo = true;
    ISBackButtonWheel.disableCrafting = true;
    ISBackButtonWheel.disableTime = true;
    ISBackButtonWheel.disableMoveable = true;

    local joypadData = JoypadState.players[self.player:getPlayerNum() + 1];
    if joypadData and joypadData.isActive then
        self.joypadData = joypadData;
        setJoypadFocus(self.player:getPlayerNum(), self);
    end

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

    if isClient() then
        self.player:setInvisible(true);
        self.player:setGhostMode(true, true);
        self.player:setNoClip(true, true);
        self.player:setZombiesDontAttack(true);
        self.player:setShootable(false);

        self.oldVoiceMode = getCore():getOptionVoiceMode();
        getCore():setOptionVoiceMode(3);

        if ISChat and ISChat.instance then
            self.wasChatVisible = ISChat.instance:isVisible();
            ISChat.instance:setVisible(false);
        end
    else
        setZombiesUseless(true);
        setVehicleStatic(true);
    end
    
    Events.OnTick.Add(ISBriefingUI.onTick);
end

function ISBriefingUI.onTick()
    local self = ISBriefingUI.instance;
    if not self or self.isFinished then return; end
    
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
                if bodyPart:getHealth() < partData.health then
                    bodyPart:SetHealth(partData.health);
                    dirty = true;
                end
                if bodyPart:getBurnTime() > partData.burnTime then
                    bodyPart:setBurnTime(partData.burnTime);
                    dirty = true;
                end
                if bodyPart:getBleedingTime() > partData.bleedingTime then
                    bodyPart:setBleedingTime(partData.bleedingTime);
                    dirty = true;
                end
                if bodyPart:getDeepWoundTime() > partData.deepWoundTime then
                    bodyPart:setDeepWoundTime(partData.deepWoundTime);
                    dirty = true;
                end
                if bodyPart:getFractureTime() > partData.fractureTime then
                    bodyPart:setFractureTime(partData.fractureTime);
                    dirty = true;
                end
                if bodyPart:getWoundInfectionLevel() > partData.woundInfectionLevel then
                    bodyPart:setWoundInfectionLevel(partData.woundInfectionLevel);
                    dirty = true;
                end
            end
        end

        setZombiesUseless(true);

        if dirty then
            bodyDamage:calculateOverallHealth();
        end

        if self.tickDelay > 5 and not self.noPause then
            GameTime.getInstance():setMultiplier(0.0);
        elseif isGamePaused() and not self.noPause then
            GameTime.getInstance():setMultiplier(1.0);
        end
    end
end

function ISBriefingUI:update()
    ISPanel.update(self);

    self:updateCursor();
    self:updateVolumeFade();

    if self.player:isDead() and not self.fadeStartTime then
        self:skipAnimation();
        return;
    end

    if not self.isFinished then
        self.tickDelay = self.tickDelay + 1;
    end

    if isClient() and (not self.fadeStartTime and not self.isFinished) and not self.sentStartCommand then
        if self.player:getSquare() and self.player:getOnlineID() ~= -1 and self.tickDelay > 5 then
            sendClientCommand(self.player, "Briefing", "setBriefingActive", {
                active = true,
                parts = self.snapshotParts,
                infectionTime = self.snapshotInfectionTime,
                infectionMortalityDuration = self.snapshotInfectionMortalityDuration,
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
    if not self.oldAmbientVol then return; end
    local sm = getSoundManager();
    local timestamp = getTimestampMs();

    if self.isVolumeFadingOut then
        local elapsed = (timestamp - self.volumeFadeStartTime) / 1000.0;
        local progress = math.min(1.0, elapsed / 1.0);

        sm:setAmbientVolume(self.oldAmbientVol * (1.0 - progress));
        sm:setSoundVolume(self.oldSoundVol * (1.0 - progress));
        sm:setMusicVolume(self.oldMusicVol * (1.0 - progress));

        if progress >= 1.0 then
            self.isVolumeFadingOut = false;
        end
    elseif self.isVolumeFadingIn then
        local elapsed = (timestamp - self.volumeFadeInStartTime) / 1000.0;
        local progress = math.min(1.0, elapsed / 1.0);

        sm:setAmbientVolume(self.oldAmbientVol * progress);
        sm:setSoundVolume(self.oldSoundVol * progress);
        sm:setMusicVolume(self.oldMusicVol * progress);

        if progress >= 1.0 then
            self.isVolumeFadingIn = false;
        end
    end
end

function ISBriefingUI:prerender()
    ISPanel.prerender(self);
    local alpha = math.max(0.0, math.min(1.0, self.alpha));
    self:drawRect(0, 0, self.width, self.height, alpha, 0, 0, 0);

    local y = self.height / 2 - self.textBlockHeight / 2;
    for i, line in ipairs(self.lines) do
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
        if not self.joypadData and not self.noPause then
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
        if not self.joypadData and not self.noPause then
            self:skipAnimation();
        end
        return true;
    end
    return false;
end

function ISBriefingUI:onKeyPress(key)
    if not self.isFinished then
        GameKeyboard.eatKeyPress(key);
        if (not self.joypadData and not self.noPause) and key == Keyboard.KEY_ESCAPE then
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
        if not self.noPause and button == Joypad.AButton then
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
    self.isFinished = true;

    if ISMoodlesInLuaHandle then
        ISMoodlesInLuaHandle:setVisible(true);
    end

    local sm = getSoundManager();
    local emitter = getSoundManager():getUIEmitter();
    if self.soundInstance then
        emitter:stopSound(self.soundInstance);
        self.soundInstance = nil;
    end

    if self.oldAmbientVol then sm:setAmbientVolume(self.oldAmbientVol); end
    if self.oldSoundVol then sm:setSoundVolume(self.oldSoundVol); end
    if self.oldMusicVol then sm:setMusicVolume(self.oldMusicVol); end

    self.isVolumeFadingIn = true;
    self.volumeFadeInStartTime = getTimestampMs();
    self.isVolumeFadingOut = false;

    self.player:setBlockMovement(false);
    self.player:setIgnoreMovement(false);

    GameKeyboard.setDoLuaKeyPressed(true);
    GameKeyboard.noEventsWhileLoading = false;

    JoypadState.disableControllerPrompt = false;
    JoypadState.disableMovement = false;

    ISBackButtonWheel.disablePlayerInfo = false;
    ISBackButtonWheel.disableCrafting = false;
    ISBackButtonWheel.disableTime = false;
    ISBackButtonWheel.disableMoveable = false;

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

        if self.oldVoiceMode then
            getCore():setOptionVoiceMode(self.oldVoiceMode);
            self.oldVoiceMode = nil;
        end

        if (ISChat and ISChat.instance) and self.wasChatVisible then
            ISChat.instance:setVisible(true);
        end
    else
        GameTime.getInstance():setMultiplier(1.0);

        local bodyDamage = self.player:getBodyDamage();
        bodyDamage:setHealthReductionFromSevereBadMoodles(0.0165);
        bodyDamage:setStandardHealthAddition(0.002);

        if not self.noPause then
            setVehicleStatic(false);
        end

        setZombiesUseless(false);
    end

    Events.OnTick.Remove(ISBriefingUI.onTick);

    if self.joypadData and not self.joypadData.controller.connected then
        local ui = _originalJoypadDisconnectedUI(ISJoypadDisconnectedUI, self.player:getPlayerNum());
        ---@diagnostic disable-next-line: redundant-parameter
        ui:setAlwaysOnTop(true);
        ui:addToUIManager();
        self.joypadData.disconnectedUI = ui;
    end

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
        if elapsed >= self.typingDelay then
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
                emitter:setVolume(self.soundInstance, self.oldSoundVol);
            end
        end
    else
        self.isTypingComplete = true;
        local emitter = getSoundManager():getUIEmitter();
        if self.soundInstance then
            emitter:stopSound(self.soundInstance);
            self.soundInstance = nil;
        end
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

    self.alpha = math.max(0.0, 1.0 - progress);

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

function ISBriefingUI:new(lines, noPause)
    local o = ISPanel:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight());
    setmetatable(o, self);
    self.__index = self;
    o.lines = lines or {};
    o:noBackground();
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 };

    o:setAlwaysOnTop(true);
    o:setWantKeyEvents(true);
    o:setJoypadFocused(true);
    o:setCapture(true);
    o:setVisible(true);

    o.tickDelay = 0;
    o.noPause = noPause;
    o.holdDuration = 1.0;
    o.fadeOutDuration = 1.0;

    o.typingStarted = false;
    o.typingDelay = 1.0;
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

    local total = 0;
    for _, line in ipairs(o.lines) do
        total = total + utf8_len(line);
    end
    o.totalSymbols = total;
    o.textBlockHeight = #o.lines * (o.fontHgt + 5) + 20;
    o.soundInstance = nil;
    o.isVolumeFadingOut = false;
    o.isVolumeFadingIn = false;
    o.volumeFadeStartTime = 0;
    o.volumeFadeInStartTime = 0;

    local sm = getSoundManager();
    o.oldAmbientVol = sm:getAmbientVolume();
    o.oldSoundVol = sm:getSoundVolume();
    o.oldMusicVol = sm:getMusicVolume();

    o.player = getPlayer();

    ISBriefingUI.instance = o;

    o:initialise();
    return o;
end