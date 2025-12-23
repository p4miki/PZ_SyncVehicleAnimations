local SYNC_MODULE = 'SyncVehicleAnim'
local SYNC_COMMAND = 'setDoorAnim'

local function getLocalUsername()
    local player = getSpecificPlayer(0)
    return player and player:getUsername() or nil
end

local function tryPlayDoorAnim(vehicle, part, isOpen)
    if not vehicle or not part then
        return
    end
    -- Build 42 uses "Open"/"Close" (see ISOpenVehicleDoor/ISCloseVehicleDoor).
    vehicle:playPartAnim(part, isOpen and 'Open' or 'Close')
end

local function onServerCommand(module, command, args)
    if module ~= SYNC_MODULE or command ~= SYNC_COMMAND then
        return
    end
    if type(args) ~= 'table' or args.vehicle == nil or args.part == nil or args.open == nil then
        return
    end

    local vehicle = getVehicleById(args.vehicle)
    if not vehicle then
        return
    end

    local part = vehicle:getPartById(args.part)
    if not part then
        return
    end

    local localUsername = getLocalUsername()
    if localUsername ~= nil and args.username ~= nil and localUsername == args.username then
        return
    end

    local open = args.open == true or args.open == 1 or args.open == 'true'
    tryPlayDoorAnim(vehicle, part, open)
end

Events.OnServerCommand.Add(onServerCommand)

local function sendDoorAnim(vehicle, part, open)
    if not isClient() then
        return
    end
    -- Avoid errors in SP / non-network contexts.
    if type(sendClientCommand) ~= 'function' then
        return
    end
    if not vehicle or not part then
        return
    end

    sendClientCommand(SYNC_MODULE, SYNC_COMMAND, {
        vehicle = vehicle:getId(),
        part = part:getId(),
        open = open == true,
    })
end

require 'Vehicles/TimedActions/ISOpenVehicleDoor'
require 'Vehicles/TimedActions/ISCloseVehicleDoor'

if ISOpenVehicleDoor and ISOpenVehicleDoor.start then
    local originalStart = ISOpenVehicleDoor.start
    function ISOpenVehicleDoor:start()
        sendDoorAnim(self.vehicle, self.part, true)
        return originalStart(self)
    end
end

if ISCloseVehicleDoor and ISCloseVehicleDoor.start then
    local originalStart = ISCloseVehicleDoor.start
    function ISCloseVehicleDoor:start()
        sendDoorAnim(self.vehicle, self.part, false)
        return originalStart(self)
    end
end
