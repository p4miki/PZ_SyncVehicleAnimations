local SYNC_MODULE = 'SyncVehicleAnim'
local SYNC_COMMAND_DOOR = 'setDoorAnim'
local SYNC_COMMAND_WINDOW_ANIM = 'setWindowAnim'

local function getSenderId(player)
    if player and player.getOnlineID then
        return tonumber(player:getOnlineID())
    end
    return nil
end

local function normalizeVehicleId(vehicle)
    if vehicle == nil then
        return nil
    end
    if type(vehicle) == 'number' then
        return vehicle
    end
    local asNumber = tonumber(vehicle)
    if asNumber ~= nil then
        return asNumber
    end
    if type(vehicle) == 'userdata' or type(vehicle) == 'table' then
        if vehicle.getId then
            return tonumber(vehicle:getId())
        end
    end
    return nil
end

local function normalizePartId(part)
    if part == nil then
        return nil
    end
    if type(part) == 'string' then
        return part
    end
    if type(part) == 'userdata' or type(part) == 'table' then
        if part.getId then
            return tostring(part:getId())
        end
    end
    return tostring(part)
end

local function OnClientCommand(module, command, player, args)
    if module ~= SYNC_MODULE then
        return
    end

    if command ~= SYNC_COMMAND_DOOR and command ~= SYNC_COMMAND_WINDOW_ANIM then
        return
    end

    if type(args) ~= 'table' or args.vehicle == nil or args.part == nil then
        return
    end

    local vehicleId = normalizeVehicleId(args.vehicle)
    local partId = normalizePartId(args.part)
    if vehicleId == nil or partId == nil then
        return
    end

    local payload = {
        vehicle = vehicleId,
        part = partId,
        username = player and player:getUsername() or nil,
        senderId = getSenderId(player),
    }

    if command == SYNC_COMMAND_DOOR then
        if args.open == nil then
            return
        end
        payload.open = args.open == true or args.open == 1 or args.open == 'true'
    elseif command == SYNC_COMMAND_WINDOW_ANIM then
        if args.open == nil then
            return
        end
        payload.open = args.open == true or args.open == 1 or args.open == 'true'
        payload.durationMs = tonumber(args.durationMs) or nil
    end

    -- Broadcast to all clients (sender included; client filters by senderId/username).
    sendServerCommand(SYNC_MODULE, command, payload)
end

Events.OnClientCommand.Add(OnClientCommand)
