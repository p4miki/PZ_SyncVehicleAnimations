local SYNC_MODULE = 'SyncVehicleAnim'
local SYNC_COMMAND_DOOR = 'setDoorAnim'
local SYNC_COMMAND_WINDOW_ANIM = 'setWindowAnim'

-- Predict-only window sync: send only open/close start + duration,
-- each client interpolates window openDelta locally.
local WINDOW_ANIM_MS_PER_TIME_UNIT = 20
local WINDOW_ANIM_MIN_MS = 300
local WINDOW_ANIM_MAX_MS = 2500
local WINDOW_WAIT_FOR_VEHICLE_MS = 60000

local __SVA_STATE_KEY = '__SyncVehicleAnim_State'
local __svaState = rawget(_G, __SVA_STATE_KEY)
if not __svaState then
    __svaState = {}
    rawset(_G, __SVA_STATE_KEY, __svaState)
end

local function nowMs()
    if type(getTimestampMs) == 'function' then
        return getTimestampMs()
    end
    if type(getTimestamp) == 'function' then
        return math.floor(getTimestamp() * 1000)
    end
    if UIManager and UIManager.getMillisSinceLastRender then
        __svaState.__fallbackMs = (__svaState.__fallbackMs or 0) + UIManager.getMillisSinceLastRender()
        return __svaState.__fallbackMs
    end
    __svaState.__fallbackMs = (__svaState.__fallbackMs or 0) + 16
    return __svaState.__fallbackMs
end

local function clampNumber(x, minValue, maxValue)
    x = tonumber(x)
    if not x then
        return nil
    end
    if x < minValue then
        return minValue
    end
    if x > maxValue then
        return maxValue
    end
    return x
end

local function getLocalPlayerInfo()
    local player = getSpecificPlayer(0)
    if not player then
        return nil, nil
    end
    local username = player.getUsername and player:getUsername() or nil
    local onlineId = player.getOnlineID and tonumber(player:getOnlineID()) or nil
    return username, onlineId
end

local function tryPlayDoorAnim(vehicle, part, isOpen)
    if not vehicle or not part then
        return
    end
    -- Build 42 uses "Open"/"Close" (see ISOpenVehicleDoor/ISCloseVehicleDoor).
    vehicle:playPartAnim(part, isOpen and 'Open' or 'Close')
end

local activeWindowAnims = __svaState.activeWindowAnims or {}
__svaState.activeWindowAnims = activeWindowAnims

local function safeSetWindowDelta(window, delta)
    if not window or not window.setOpenDelta then
        return
    end
    window:setOpenDelta(delta)
end

local function safeIsWindowDestroyed(window)
    if not window then
        return true
    end
    if window.isDestroyed then
        return window:isDestroyed()
    end
    return false
end

local function windowAnimKey(vehicleId, partId)
    return tostring(vehicleId) .. ':' .. tostring(partId)
end

local function startPredictedWindowAnim(vehicleId, partId, open, durationMs)
    vehicleId = tonumber(vehicleId)
    if vehicleId == nil or partId == nil then
        return
    end
    partId = tostring(partId)
    local now = nowMs()
    local key = windowAnimKey(vehicleId, partId)
    activeWindowAnims[key] = {
        vehicleId = vehicleId,
        partId = partId,
        open = open == true,
        createdMs = now,
        startMs = nil,
        durationMs = clampNumber(durationMs, WINDOW_ANIM_MIN_MS, WINDOW_ANIM_MAX_MS) or 1000,
        fromDelta = nil,
        toDelta = (open == true) and 1.0 or 0.0,
    }
end

local function tickPredictedWindowAnims()
    if type(activeWindowAnims) ~= 'table' then
        return
    end

    local hasAny = false
    for _ in pairs(activeWindowAnims) do
        hasAny = true
        break
    end
    if not hasAny then
        return
    end

    local now = nowMs()
    for key, anim in pairs(activeWindowAnims) do
        local vehicle = anim and getVehicleById and getVehicleById(anim.vehicleId) or nil
        local part = vehicle and vehicle:getPartById(anim.partId) or nil
        local window = part and part:getWindow() or nil

        -- If the vehicle isn't streamed yet, keep the request around for a bit.
        if not vehicle or not part or not window then
            local createdMs = anim and anim.createdMs or now
            if (now - createdMs) > WINDOW_WAIT_FOR_VEHICLE_MS then
                activeWindowAnims[key] = nil
            end
        elseif safeIsWindowDestroyed(window) then
            activeWindowAnims[key] = nil
        else
            if anim.startMs == nil then
                anim.startMs = now
                -- Prefer a deterministic animation even if vanilla state replication already snapped open/closed.
                anim.fromDelta = anim.open and 0.0 or 1.0
                anim.toDelta = anim.open and 1.0 or 0.0
            end

            local elapsed = now - (anim.startMs or now)
            local duration = anim.durationMs or 1000
            local t = duration > 0 and (elapsed / duration) or 1
            if t < 0 then
                t = 0
            elseif t > 1 then
                t = 1
            end

            local fromDelta = anim.fromDelta or (anim.open and 0.0 or 1.0)
            local toDelta = anim.toDelta or (anim.open and 1.0 or 0.0)
            local delta = fromDelta + (toDelta - fromDelta) * t
            safeSetWindowDelta(window, delta)

            if t >= 1 then
                -- Finalize logical state.
                window:setOpen(anim.open)
                activeWindowAnims[key] = nil
            end
        end
    end
end

local function onServerCommand(module, command, args)
    if module ~= SYNC_MODULE then
        return
    end

    if command ~= SYNC_COMMAND_DOOR and command ~= SYNC_COMMAND_WINDOW_ANIM then
        return
    end

    if type(args) ~= 'table' or args.vehicle == nil or args.part == nil then
        return
    end

    local localUsername, localOnlineId = getLocalPlayerInfo()
    if localOnlineId ~= nil and args.senderId ~= nil and tonumber(args.senderId) == localOnlineId then
        return
    end
    if localUsername ~= nil and args.username ~= nil and localUsername == args.username then
        return
    end

    local vehicleId = tonumber(args.vehicle)
    if vehicleId == nil then
        return
    end
    local partId = tostring(args.part)

    -- Window prediction can be queued by ids even if the vehicle isn't streamed yet.
    if command == SYNC_COMMAND_WINDOW_ANIM then
        if args.open == nil then
            return
        end
        local open = args.open == true or args.open == 1 or args.open == 'true'
        startPredictedWindowAnim(vehicleId, partId, open, args.durationMs)
        return
    end

    if type(getVehicleById) ~= 'function' then
        return
    end

    local vehicle = getVehicleById(vehicleId)
    if not vehicle then
        return
    end

    local part = vehicle:getPartById(partId)
    if not part then
        return
    end

    if command == SYNC_COMMAND_DOOR then
        if args.open == nil then
            return
        end
        local open = args.open == true or args.open == 1 or args.open == 'true'
        tryPlayDoorAnim(vehicle, part, open)
        return
    end
end

local function ensureEventHooks()
    if not Events then
        return
    end

    if Events.OnServerCommand then
        if __svaState.onServerCommandFn then
            Events.OnServerCommand.Remove(__svaState.onServerCommandFn)
        end
        __svaState.onServerCommandFn = onServerCommand
        Events.OnServerCommand.Add(onServerCommand)
    end

    if Events.OnTick then
        if __svaState.onTickFn then
            Events.OnTick.Remove(__svaState.onTickFn)
        end
        __svaState.onTickFn = tickPredictedWindowAnims
        Events.OnTick.Add(tickPredictedWindowAnims)
    end
end

ensureEventHooks()

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

    sendClientCommand(SYNC_MODULE, SYNC_COMMAND_DOOR, {
        vehicle = vehicle:getId(),
        part = part:getId(),
        open = open == true,
    })
end

local function sendWindowAnimStart(vehicle, part, open, durationMs)
    if not isClient() then
        return
    end
    if type(sendClientCommand) ~= 'function' then
        return
    end
    if not vehicle or not part then
        return
    end

    sendClientCommand(SYNC_MODULE, SYNC_COMMAND_WINDOW_ANIM, {
        vehicle = vehicle:getId(),
        part = part:getId(),
        open = open == true,
        durationMs = tonumber(durationMs) or nil,
    })
end

require 'Vehicles/TimedActions/ISOpenVehicleDoor'
require 'Vehicles/TimedActions/ISCloseVehicleDoor'
require 'Vehicles/TimedActions/ISOpenCloseVehicleWindow'

-- Some load orders can run this file before Events is fully ready.
-- Try again on game start.
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(ensureEventHooks)
end

if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(ensureEventHooks)
end

if ISOpenVehicleDoor and ISOpenVehicleDoor.start then
    local originalStart = ISOpenVehicleDoor.start
    ---@diagnostic disable-next-line: duplicate-set-field
    ISOpenVehicleDoor.start = function(self)
        sendDoorAnim(self.vehicle, self.part, true)
        return originalStart(self)
    end
end

if ISCloseVehicleDoor and ISCloseVehicleDoor.start then
    local originalStart = ISCloseVehicleDoor.start
    ---@diagnostic disable-next-line: duplicate-set-field
    ISCloseVehicleDoor.start = function(self)
        sendDoorAnim(self.vehicle, self.part, false)
        return originalStart(self)
    end
end

-- Windows don't play a part animation in vanilla; they smoothly move using window:setOpenDelta()
-- during the timed action, and only the final open/closed state is transmitted.
-- We can either stream openDelta ('delta') or send start+duration and predict ('predict').
if ISOpenCloseVehicleWindow and ISOpenCloseVehicleWindow.start then
    local originalStart = ISOpenCloseVehicleWindow.start
    ---@diagnostic disable-next-line: duplicate-set-field
    ISOpenCloseVehicleWindow.start = function(self)
        local ok = originalStart(self)
        if self.vehicle and self.part and self.window then
            local maxTime = tonumber(self.maxTime) or 50
            local durationMs = clampNumber(maxTime * WINDOW_ANIM_MS_PER_TIME_UNIT, WINDOW_ANIM_MIN_MS, WINDOW_ANIM_MAX_MS)
            sendWindowAnimStart(self.vehicle, self.part, self.open, durationMs)
        end
        return ok
    end
end
