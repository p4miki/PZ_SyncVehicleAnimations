local SYNC_MODULE = 'SyncVehicleAnim'
local SYNC_COMMAND = 'setDoorAnim'

local function OnClientCommand(module, command, player, args)
    if module ~= SYNC_MODULE or command ~= SYNC_COMMAND then
        return
    end
    if type(args) ~= 'table' or args.vehicle == nil or args.part == nil or args.open == nil then
        return
    end

    local open = args.open == true or args.open == 1 or args.open == 'true'
    local payload = {
        vehicle = args.vehicle,
        part = args.part,
        open = open,
        username = player and player:getUsername() or nil,
    }

    -- Broadcast to all clients (sender included; client filters by username).
    sendServerCommand(SYNC_MODULE, SYNC_COMMAND, payload)
end

Events.OnClientCommand.Add(OnClientCommand)
