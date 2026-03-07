if not isServer() then return; end

ISBriefingServer = {};

local snapshots = {};
local activePlayers = {};

function ISBriefingServer.applySnapshot(player, args)
    if not args or not args.parts or type(args.parts) ~= "table" then return; end
    local snapshot = { parts = {} };

    for i, partData in ipairs(args.parts) do
        snapshot.parts[i - 1] = partData;
    end

    snapshot.infectionTime = args.infectionTime;
    snapshot.infectionMortalityDuration = args.infectionMortalityDuration;

    snapshots[player:getOnlineID()] = snapshot;
end;

function ISBriefingServer.restoreTimersFromSnapshot(player)
    local snapshot = snapshots[player:getOnlineID()];
    if not snapshot then return; end

    local bodyDamage = player:getBodyDamage();
    local bodyParts = bodyDamage:getBodyParts();
    local count = bodyParts:size();

    for i = 0, count - 1 do
        local bodyPart = bodyDamage:getBodyPart(BodyPartType.FromIndex(i));
        local partData = snapshot.parts[i];
        if partData then
            bodyPart:setBleedingTime(partData.bleedingTime);
            bodyPart:setCutTime(partData.cutTime);
            bodyPart:setBiteTime(partData.biteTime);
            bodyPart:setScratchTime(partData.scratchTime);
            bodyPart:setDeepWoundTime(partData.deepWoundTime);
            bodyPart:setBurnTime(partData.burnTime);
            bodyPart:setStitchTime(partData.stitchTime);
            bodyPart:setFractureTime(partData.fractureTime);
            if bodyPart:isInfectedWound() then
                bodyPart:setWoundInfectionLevel(partData.woundInfectionLevel);
            end
            bodyPart:SetHealth(partData.health);
        end
    end

    bodyDamage:setInfectionTime(snapshot.infectionTime);
    bodyDamage:setInfectionMortalityDuration(snapshot.infectionMortalityDuration);

    bodyDamage:calculateOverallHealth();
end;

function ISBriefingServer.clearSnapshot(player)
    local onlineID = player:getOnlineID();
    snapshots[onlineID] = nil;
    activePlayers[onlineID] = nil;
end;

function ISBriefingServer.onTick()
    for onlineID, player in pairs(activePlayers) do
        local ok, err = pcall(function()
            if player:isDead() then
                player:setInvisible(false);
                player:setGhostMode(false, true);
                player:setNoClip(false, true);
                player:setBlockMovement(false);
                player:setIgnoreMovement(false);
                player:setZombiesDontAttack(false);
                player:setShootable(true);

                player:getBodyDamage():setHealthReductionFromSevereBadMoodles(0.0165);
                player:getBodyDamage():setStandardHealthAddition(0.002);

                sendPlayerExtraInfo(player);

                snapshots[onlineID] = nil;
                activePlayers[onlineID] = nil;
                
                player:getModData().isBriefingActive = nil;
                player:transmitModData();
            else
                local snapshot = snapshots[onlineID];
                if snapshot then
                    local bodyDamage = player:getBodyDamage();
                    local count = bodyDamage:getBodyParts():size();
                    local dirty = false;

                    for i = 0, count - 1 do
                        local bodyPart = bodyDamage:getBodyPart(BodyPartType.FromIndex(i));
                        local partData = snapshot.parts[i];
                        if partData and bodyPart:getHealth() < partData.health then
                            bodyPart:SetHealth(partData.health);
                            dirty = true;
                        end
                    end

                    if dirty then
                        bodyDamage:calculateOverallHealth();
                    end
                end

                if player:isOnFire() then
                    player:StopBurning(); player:sendObjectChange(IsoObjectChange.STOP_BURNING);
                end
            end
        end); if not ok then
            snapshots[onlineID] = nil;
            activePlayers[onlineID] = nil;
        end
    end
end;

Events.OnTick.Add(ISBriefingServer.onTick);

Events.EveryOneMinute.Add(function()
    local online, players = {}, getOnlinePlayers();
    for i = 0, players:size() - 1 do
        online[players:get(i):getOnlineID()] = true;
    end

    for onlineID, _ in pairs(activePlayers) do
        if not online[onlineID] then
            snapshots[onlineID] = nil;
            activePlayers[onlineID] = nil;
        end
    end
end);

function ISBriefingServer.restoreFlags(player, modData)
    player:setInvisible(false);
    player:setGhostMode(false, true);
    player:setNoClip(false, true);
    player:setBlockMovement(false);
    player:setIgnoreMovement(false);
    player:setZombiesDontAttack(false);
    player:setShootable(true);

    local bodyDamage = player:getBodyDamage();
    bodyDamage:setHealthReductionFromSevereBadMoodles(0.0165);
    bodyDamage:setStandardHealthAddition(0.002);

    ISBriefingServer.restoreTimersFromSnapshot(player);
    ISBriefingServer.clearSnapshot(player);

    sendPlayerExtraInfo(player);
    
    modData.isBriefingActive = nil;
end;

function ISBriefingServer.onClientCommand(module, command, player, args)
    if module ~= "Briefing" then return; end
    if command == "setBriefingActive" then
        local enabled = type(args.active) == "boolean" and args.active or false;
        local modData = player:getModData();

        if enabled then
            modData.isBriefingActive = true;

            player:setInvisible(true);
            player:setGhostMode(true, true);
            player:setNoClip(true, true);
            player:setBlockMovement(true);
            player:setIgnoreMovement(true);
            player:setZombiesDontAttack(true);
            player:setShootable(false);

            local bodyDamage = player:getBodyDamage();
            bodyDamage:setHealthReductionFromSevereBadMoodles(0);
            bodyDamage:setStandardHealthAddition(0);

            if player:isOnFire() then
                player:StopBurning(); player:sendObjectChange(IsoObjectChange.STOP_BURNING);
            end

            ISBriefingServer.applySnapshot(player, args);
            activePlayers[player:getOnlineID()] = player;

            sendPlayerExtraInfo(player);
        else
            ISBriefingServer.restoreFlags(player, modData);
        end
        player:transmitModData();
    end
end;

Events.OnClientCommand.Add(ISBriefingServer.onClientCommand);