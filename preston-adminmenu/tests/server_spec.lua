-- Runs the real server scripts against a small fake FiveM server, to check the menu's rules end to end:
-- permissions, immunity, bans (saved, matched when joining, unbanned), reports and tamper detection.
-- Run from the resource folder with any Lua 5.3+:  lua tests/server_spec.lua

local say = print
local consoleLines = {}
print = function(...) consoleLines[#consoleLines + 1] = table.concat({ ... }, ' ') end

-- ---------------------------------------------------------------- fake server

local players, entities, kvp, handlers, commands = {}, {}, {}, {}, {}
local bagHandlers, timeouts, toClients = {}, {}, {}
local clockMs, nextEntity = 0, 100

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

-- Stands in for FiveM's json library: stores a copy, so saved data can't be changed by accident.
json = {
    encode = function(value) return { saved = copy(value) } end,
    decode = function(value) return type(value) == 'table' and copy(value.saved) or nil end,
}

local Vector = {}
Vector.__index = Vector
Vector.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vector) end

local function newEntity(kind, coords)
    nextEntity = nextEntity + 1
    entities[nextEntity] = { type = kind, coords = coords }
    return nextEntity
end

local function fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end

local function runTimeouts()
    while #timeouts > 0 do table.remove(timeouts, 1)() end
end

function GetConvar(_, default) return default end
function GetCurrentResourceName() return 'preston-adminmenu' end
function GetResourceState() return 'missing' end
function GetGameTimer() return clockMs end
function CreateThread(fn) fn() end
function Wait() end
function SetTimeout(_, fn) timeouts[#timeouts + 1] = fn end
function PerformHttpRequest() end
function AddEventHandler(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerClientEvent(name, target, ...) toClients[#toClients + 1] = { name = name, target = target, args = { ... } } end
function RegisterCommand(name, fn) commands[name] = fn end

function GetPlayers()
    local out = {}
    for id in pairs(players) do out[#out + 1] = tostring(id) end
    table.sort(out)
    return out
end
local function playerOf(id) return players[tonumber(id)] end
function GetPlayerName(id) local p = playerOf(id) return p and p.name or nil end
function GetPlayerIdentifiers(id) local p = playerOf(id) return p and copy(p.ids) or {} end
function GetNumPlayerTokens(id) local p = playerOf(id) return p and #p.tokens or 0 end
function GetPlayerToken(id, index) return playerOf(id).tokens[index + 1] end
function GetPlayerPing() return 42 end
function GetPlayerPed(id) local p = playerOf(id) return p and p.ped or 0 end

-- Like the real server, ACEs are a tree: granting "adminmenu" also grants "adminmenu.kick".
function IsPlayerAceAllowed(id, ace)
    local p = playerOf(id)
    if not p then return false end
    for granted in pairs(p.aces) do
        if ace == granted or ace:sub(1, #granted + 1) == granted .. '.' then return true end
    end
    return false
end

local function leave(id, reason)
    if not players[id] then return end
    source = id
    fire('playerDropped', reason)
    players[id] = nil
end
local dropped = {}
function DropPlayer(id, reason)
    dropped[tonumber(id)] = reason
    leave(tonumber(id), reason)
end

function GetEntityCoords(entity) local e = entities[entity] return e and e.coords or vector3(0.0, 0.0, 0.0) end
function SetEntityCoords(entity, x, y, z) entities[entity].coords = vector3(x, y, z) end
function GetEntityHeading() return 90.0 end
function FreezeEntityPosition(entity, frozen) entities[entity].frozen = frozen end
local hashAlias = {} -- [name] = another name with the same hash, to test hash collisions
function GetHashKey(name) return hashAlias[name] or name end
function NetworkGetNetworkIdFromEntity(entity) return entity end
function GetVehiclePedIsIn(ped)
    local vehicle = entities[ped] and entities[ped].vehicle
    return (vehicle and entities[vehicle]) and vehicle or 0
end
function GetPlayerRoutingBucket(id) local p = players[tonumber(id)] return p and p.bucket or 0 end
function SetEntityRoutingBucket(entity, bucket) entities[entity].bucket = bucket end
function CreateVehicleServerSetter(model, kind, x, y, z)
    local id = newEntity(2, vector3(x, y, z))
    entities[id].model, entities[id].vehicleType = model, kind
    return id
end
function DoesEntityExist(entity) return entities[entity] ~= nil end
function DeleteEntity(entity) entities[entity] = nil end
function SetPedIntoVehicle(ped, vehicle) entities[ped].vehicle = vehicle end
function SetVehicleNumberPlateText(vehicle, plate) entities[vehicle].plate = plate end
function NetworkGetEntityFromNetworkId(netId) return entities[netId] and netId or 0 end
function GetEntityType(entity) return entities[entity] and entities[entity].type or 0 end

function SetResourceKvp(key, value) kvp[key] = value end
function GetResourceKvpString(key) return kvp[key] end
function SetResourceKvpInt(key, value) kvp[key] = value end
function GetResourceKvpInt(key) return kvp[key] or 0 end
local finds = {}
function StartFindKvp(prefix)
    local keys = {}
    for key in pairs(kvp) do if key:sub(1, #prefix) == prefix then keys[#keys + 1] = key end end
    table.sort(keys)
    finds[#finds + 1] = keys
    return #finds
end
function FindKvp(handle) return table.remove(finds[handle], 1) end
function EndFindKvp() end

function AddStateBagChangeHandler(key, _, fn) bagHandlers[#bagHandlers + 1] = { key = key, fn = fn } end
function GetPlayerFromStateBagName(bag) return tonumber(bag:match('^player:(%d+)$')) or 0 end
local function setState(id, key, value)
    for _, h in ipairs(bagHandlers) do
        if h.key == nil or h.key == key then h.fn('player:' .. id, key, value) end
    end
    if players[id] then players[id].state[key] = value end
end
function Player(id)
    return { state = { set = function(_, key, value) setState(tonumber(id), key, value) end } }
end

-- Connects a player. Returns true, or false and the message they were refused with.
local function join(id, name, opts)
    opts = opts or {}
    players[id] = {
        name = name,
        ids = opts.ids or { 'license:' .. name, 'discord:' .. id },
        tokens = opts.tokens or { '3:pc-' .. name },
        aces = opts.aces or {},
        ped = newEntity(1, opts.coords or vector3(100.0 * id, 50.0, 30.0)),
        state = {},
    }
    local refused
    local deferrals = { defer = function() end, update = function() end, done = function(message) refused = message end }
    source = id
    fire('playerConnecting', name, function() end, deferrals)
    if refused then
        players[id] = nil
        return false, refused
    end
    source = id
    fire('playerJoining')
    return true
end

-- Sends a menu request like the panel does and returns the server's answer.
local function rpc(id, action, payload)
    clockMs = clockMs + 250
    local before = #toClients
    source = id
    fire('preston-admin:rpc', 7, action, payload)
    runTimeouts()
    for i = #toClients, before + 1, -1 do
        local m = toClients[i]
        if m.name == 'preston-admin:rpcResult' and m.target == id then return m.args[2], m.args[3] end
    end
    error('the server did not answer ' .. action)
end

local function lastLog() return Logs.recent()[1] end
local function sentTo(id, event)
    for i = #toClients, 1, -1 do
        if toClients[i].target == id and toClients[i].name == event then return toClients[i].args end
    end
end

-- ---------------------------------------------------------------- load the resource

dofile('config.lua')
dofile('shared/vehicle_types.lua')
dofile('server/util.lua')
dofile('server/storage.lua')
dofile('server/logs.lua')
dofile('server/bans.lua')
dofile('server/reports.lua')
dofile('server/main.lua')
source = 0
fire('onResourceStart', 'preston-adminmenu')

local ADMIN, MOD, GUEST, CHEATER, OTHER = 1, 2, 3, 4, 5
assert(join(ADMIN, 'Owner', { aces = { adminmenu = true } }))
assert(join(MOD, 'Mod', { aces = { ['adminmenu.open'] = true, ['adminmenu.kick'] = true, ['adminmenu.reports'] = true } }))
assert(join(GUEST, 'Guest'))
assert(join(CHEATER, 'Cheater', { ids = { 'license:cheat', 'discord:666', 'ip:9.9.9.9' }, tokens = { '3:cheat-pc' } }))

-- ---------------------------------------------------------------- tests

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        say(('FAIL %s: %s'):format(name, tostring(err)))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
    end
end
local function contains(text, part, label)
    if type(text) ~= 'string' or not text:find(part, 1, true) then
        error(('%s: expected "%s" in "%s"'):format(label or 'text', part, tostring(text)), 2)
    end
end

test('players without access get a quiet "no" when they press the menu key', function()
    local logsBefore = #Logs.recent()
    local ok, data = rpc(GUEST, 'state')
    eq(ok, true)
    eq(data.allowed, false)
    eq(#Logs.recent(), logsBefore, 'nothing logged')
end)

test('admins get their permissions with the menu state', function()
    local ok, data = rpc(MOD, 'state')
    eq(ok, true)
    eq(data.allowed, true)
    eq(data.perms.kick, true)
    eq(data.perms.ban, false)
    eq(data.storage, 'kvp')
end)

test('a non-admin calling an action directly is refused and logged', function()
    local ok, message = rpc(GUEST, 'kick', { target = OTHER, reason = 'testing' })
    eq(ok, false)
    contains(message, "don't have access")
    eq(lastLog().action, 'Denied')
end)

test('unknown actions and bad payloads are refused', function()
    local ok, message = rpc(ADMIN, 'giveMoney', {})
    eq(ok, false)
    eq(message, 'Unknown action.')
    ok, message = rpc(ADMIN, 'kick', 'not a table')
    eq(ok, false)
    contains(message, 'no longer online')
end)

test('each action needs its own permission', function()
    local ok, message = rpc(MOD, 'ban', { target = GUEST, reason = 'nope', duration = '1d' })
    eq(ok, false)
    contains(message, "don't have permission")
end)

test('kicks need a reason', function()
    local ok, message = rpc(MOD, 'kick', { target = GUEST, reason = ' ' })
    eq(ok, false)
    contains(message, 'reason')
    eq(GetPlayerName(GUEST), 'Guest', 'still online')
end)

test('staff with the immune permission are protected', function()
    local ok, message = rpc(MOD, 'kick', { target = ADMIN, reason = 'revenge' })
    eq(ok, false)
    contains(message, 'protected')
    eq(GetPlayerName(ADMIN), 'Owner')
end)

test('bring and send back are done by the server', function()
    local start = GetEntityCoords(GetPlayerPed(GUEST))
    local ok = rpc(ADMIN, 'bring', { target = GUEST })
    eq(ok, true)
    local brought = GetEntityCoords(GetPlayerPed(GUEST))
    eq(brought.x, GetEntityCoords(GetPlayerPed(ADMIN)).x + 1.0, 'next to the admin')
    ok = rpc(ADMIN, 'sendBack', { target = GUEST })
    eq(ok, true)
    eq(GetEntityCoords(GetPlayerPed(GUEST)).x, start.x, 'back where they were')
end)

test('teleports outside the map are refused', function()
    local ok, message = rpc(ADMIN, 'teleportCoords', { x = 99999, y = 0, z = 0 })
    eq(ok, false)
    contains(message, 'outside the map')
end)

test('a ban saves, drops the player and blocks them when they come back', function()
    local ok, message = rpc(ADMIN, 'ban', { target = CHEATER, reason = 'Aimbot ^1lol', duration = '1d' })
    eq(ok, true)
    contains(message, 'ban #1')
    contains(dropped[CHEATER], 'Reason: Aimbot lol', 'color codes removed')
    contains(dropped[CHEATER], 'Ban ID: #1')
    eq(GetPlayerName(CHEATER), nil, 'dropped')
    eq(kvp['ban:1'] ~= nil, true, 'saved')
    eq(lastLog().tone, 'danger')

    local joined, refusal = join(CHEATER, 'TotallyNewGuy', { ids = { 'license:fresh', 'discord:777' }, tokens = { '3:cheat-pc' } })
    eq(joined, false, 'same PC, new account')
    contains(refusal, 'Ban ID: #1')
    joined = join(CHEATER, 'Cheater', { ids = { 'license:other', 'discord:1', 'ip:9.9.9.9' }, tokens = { '3:new' } })
    eq(joined, true, 'IP addresses are not banned by default')
    leave(CHEATER, 'quit')
end)

test('bans survive a restart', function()
    Bans.load()
    eq(Bans.list[1] ~= nil, true)
    eq(Bans.list[1].reason, 'Aimbot lol')
end)

test('unbanning lets them join again', function()
    local ok, message = rpc(ADMIN, 'unban', { id = 1 })
    eq(ok, true)
    contains(message, 'unbanned')
    eq(kvp['ban:1'].saved.active, false, 'kept for history, marked inactive')
    eq(join(CHEATER, 'Cheater', { ids = { 'license:cheat' }, tokens = { '3:cheat-pc' } }), true)
end)

test('players who quit can still be banned from the recently-left list', function()
    leave(CHEATER, 'Exiting')
    local _, bans = rpc(ADMIN, 'bans')
    local entry = bans.recentlyLeft[1]
    eq(entry.name, 'Cheater')
    local ok = rpc(ADMIN, 'banRecent', { leftId = entry.id, reason = 'Ran away', duration = 'perm' })
    eq(ok, true)
    local joined, refusal = join(CHEATER, 'Cheater', { ids = { 'license:cheat' }, tokens = {} })
    eq(joined, false)
    contains(refusal, 'permanent')
end)

test('ban lengths must be one of the allowed formats', function()
    local ok, message = rpc(ADMIN, 'ban', { target = GUEST, reason = 'test', duration = 'forever' })
    eq(ok, false)
    contains(message, 'how long')
    eq(GetPlayerName(GUEST), 'Guest')
end)

test('reports reach staff, with a cooldown', function()
    commands.report(GUEST, { 'someone', 'is', 'ramming', 'cars' })
    contains(sentTo(MOD, 'preston-admin:toast')[1].message, 'New report #1')
    commands.report(GUEST, { 'again', 'please' })
    contains(sentTo(GUEST, 'preston-admin:toast')[1].message, 'Please wait')
    local ok, list = rpc(MOD, 'reports')
    eq(ok, true)
    eq(#list, 1)
    eq(list[1].status, 'open')
    eq(rpc(MOD, 'reportClaim', { id = 1 }), true)
    contains(sentTo(GUEST, 'preston-admin:toast')[1].message, 'Mod is looking')
    eq(rpc(MOD, 'reportClose', { id = 1 }), true)
    local _, after = rpc(MOD, 'reports')
    eq(after[1].status, 'closed')
end)

test("a report keeps its reporter's name after they leave, and never reaches whoever gets their ID next", function()
    assert(join(OTHER, 'Witness'))
    commands.report(OTHER, { 'a', 'car', 'is', 'on', 'the', 'roof' })
    leave(OTHER, 'quit')
    assert(join(OTHER, 'Newcomer')) -- the server hands the free ID to the next player
    local _, list = rpc(MOD, 'reports')
    local report
    for _, r in ipairs(list) do if r.reporterName == 'Witness' then report = r end end
    eq(report ~= nil, true, 'still listed')
    eq(report.online, false, 'shown as gone')
    local ok, message = rpc(ADMIN, 'reportGoto', { id = report.id })
    eq(ok, false, 'no teleport to the newcomer')
    contains(message, 'Witness has left')
    local before = #toClients
    eq(rpc(MOD, 'reportClaim', { id = report.id }), true)
    for i = before + 1, #toClients do
        eq(toClients[i].target == OTHER and toClients[i].name == 'preston-admin:toast', false, 'the newcomer is not told')
    end
    commands.report(OTHER, { 'my', 'own', 'report' })
    contains(sentTo(OTHER, 'preston-admin:toast')[1].message, 'sent to staff', "the newcomer's limit isn't the witness's")
    leave(OTHER, 'quit')
end)

test('only the newest 100 closed reports are kept', function()
    for i = 1, 105 do
        local id = 100 + i
        assert(join(id, 'Reporter' .. i))
        commands.report(id, { 'report', 'number', tostring(i) })
        leave(id, 'quit')
    end
    local _, list = rpc(MOD, 'reports')
    for _, r in ipairs(list) do
        if r.status ~= 'closed' then
            clockMs = clockMs + 2000
            rpc(MOD, 'reportClose', { id = r.id })
        end
    end
    local _, after = rpc(MOD, 'reports')
    eq(#after, 100)
    local newest = 0
    for _, r in ipairs(after) do newest = math.max(newest, r.id) end
    eq(newest > 100, true, 'the newest ones stay')
end)

test('players joining while the saved bans are still loading wait for them', function()
    Bans.ready = false
    local realWait, waits = Wait, 0
    Wait = function() waits = waits + 1 if waits == 3 then Bans.ready = true end end
    local joined, refusal = join(CHEATER, 'Cheater', { ids = { 'license:cheat' }, tokens = {} })
    Wait = realWait
    eq(joined, false, 'still banned')
    contains(refusal, 'permanent')
    eq(waits >= 3, true, 'it waited')
end)

test('if the saved bans never load, players get in and it is logged', function()
    Bans.ready = false
    local joined = join(GUEST + 50, 'Latecomer')
    eq(joined, true)
    eq(lastLog().action, 'Ban check skipped')
    Bans.ready = true
    leave(GUEST + 50, 'quit')
end)

test('admin modes are set by the server, and tampering is put back', function()
    local ok, enabled = rpc(ADMIN, 'setMode', { mode = 'noclip', enabled = true })
    eq(ok, true)
    eq(enabled, true)
    eq(players[ADMIN].state.presAdmin_noclip, true)

    ok = rpc(MOD, 'setMode', { mode = 'god', enabled = true })
    eq(ok, false, 'the moderator has no god permission')

    -- The guest's cheat menu sets the state itself:
    setState(GUEST, 'presAdmin_god', true)
    runTimeouts()
    eq(players[GUEST].state.presAdmin_god, false, 'put back by the server')
    eq(lastLog().action, 'Blocked tampering')
end)

test("vehicles are created by the server in the admin's instance, and the admin's game gets in", function()
    local ok, message = rpc(ADMIN, 'spawnVehicle', { model = 'bad name', vehicleType = 'automobile' })
    eq(ok, false)
    contains(message, 'model name')
    players[ADMIN].bucket = 6
    local spawned, data = rpc(ADMIN, 'spawnVehicle', { model = 'adder', vehicleType = 'automobile' })
    eq(spawned, true)
    eq(data.model, 'adder')
    eq(entities[data.netId].plate, 'ADMIN')
    eq(entities[data.netId].bucket, 6, 'same instance as the admin')
    eq(GetVehiclePedIsIn(GetPlayerPed(ADMIN)), 0, 'the server no longer warps the admin before the car reaches their game')
    SetPedIntoVehicle(GetPlayerPed(ADMIN), data.netId) -- what the admin's game does once the car arrives
    local first = data.netId
    rpc(ADMIN, 'spawnVehicle', { model = 'sanchez', vehicleType = 'bike' })
    eq(entities[first], nil, 'previous vehicle deleted')
    ok = rpc(ADMIN, 'spawnVehicle', { model = 'adder', vehicleType = 'rocket' })
    eq(ok, false, 'unknown vehicle type')
    players[ADMIN].bucket = 0
end)

test('the vehicle type must match the model, looked up by model ID', function()
    contains(select(2, rpc(ADMIN, 'spawnVehicle', { model = 'buzzard2', vehicleType = 'automobile' })), 'is a heli')
    hashAlias.zz_heli = 'buzzard2'
    contains(select(2, rpc(ADMIN, 'spawnVehicle', { model = 'zz_heli', vehicleType = 'automobile' })), 'is a heli',
        'another name for the same model')
    contains(select(2, rpc(ADMIN, 'spawnVehicle', { model = 'freight', vehicleType = 'automobile' })), "Trains can't")
    eq(rpc(ADMIN, 'spawnVehicle', { model = 'buzzard2', vehicleType = 'heli' }), true)
    eq(rpc(ADMIN, 'spawnVehicle', { model = 'myaddonheli', vehicleType = 'heli' }), true, 'unlisted add-ons: the type from the game is used')
end)

test("a spawned car someone else is in is never deleted, and you can't spawn inside another car", function()
    local _, data = rpc(ADMIN, 'spawnVehicle', { model = 'adder', vehicleType = 'automobile' })
    SetPedIntoVehicle(GetPlayerPed(GUEST), data.netId)
    rpc(ADMIN, 'spawnVehicle', { model = 'sultan', vehicleType = 'automobile' })
    eq(entities[data.netId] ~= nil, true, 'kept for the guest')
    SetPedIntoVehicle(GetPlayerPed(ADMIN), data.netId)
    local ok, message = rpc(ADMIN, 'spawnVehicle', { model = 'adder', vehicleType = 'automobile' })
    eq(ok, false)
    eq(message, 'Get out of this vehicle first.')
    entities[GetPlayerPed(ADMIN)].vehicle, entities[GetPlayerPed(GUEST)].vehicle = nil, nil
end)

test("a car that never reaches the admin's game is removed, and other scripts' deletes are forgotten", function()
    local _, data = rpc(ADMIN, 'spawnVehicle', { model = 'adder', vehicleType = 'automobile' })
    eq(rpc(ADMIN, 'vehicleNotArrived', { netId = data.netId }), true)
    eq(entities[data.netId], nil)
    local _, again = rpc(ADMIN, 'spawnVehicle', { model = 'adder', vehicleType = 'automobile' })
    DeleteEntity(again.netId)
    fire('entityRemoved', again.netId)
    entities[again.netId] = { type = 2, model = 'taxi', coords = vector3(0, 0, 30) } -- the game reuses the handle
    rpc(ADMIN, 'spawnVehicle', { model = 'adder', vehicleType = 'automobile' })
    eq(entities[again.netId] ~= nil, true, "someone else's taxi survives")
end)

test('warnings are shown and reading them is logged', function()
    eq(rpc(ADMIN, 'warn', { target = GUEST, message = 'Stop ramming cars' }), true)
    eq(sentTo(GUEST, 'preston-admin:warn')[1].message, 'Stop ramming cars')
    source = GUEST
    fire('preston-admin:warnSeen')
    eq(lastLog().action, 'Read the warning')
    local count = #Logs.recent()
    fire('preston-admin:warnSeen')
    eq(#Logs.recent(), count, 'a second "seen" without a warning is ignored')
end)

test('requests are rate limited', function()
    local refused = 0
    for _ = 1, 30 do
        local before = #toClients
        source = GUEST
        fire('preston-admin:rpc', 1, 'state', {})
        local reply = toClients[#toClients]
        if #toClients > before and reply.args[2] == false and reply.args[3] == 'Slow down a little.' then refused = refused + 1 end
    end
    eq(refused, 10, '20 allowed, 10 refused')
end)

test('player lists hide identifiers from staff without that permission', function()
    clockMs = clockMs + 5000
    local _, forMod = rpc(MOD, 'players')
    eq(forMod[1].identifiers, nil)
    local _, forAdmin = rpc(ADMIN, 'players')
    for _, p in ipairs(forAdmin) do
        for _, id in ipairs(p.identifiers) do eq(id:sub(1, 3) ~= 'ip:', true, 'no IP addresses') end
    end
end)

test('Discord logs go out in batches, wait when Discord says to, and never pile up forever', function()
    local realConvar, realThread, realWait, realHttp = GetConvar, CreateThread, Wait, PerformHttpRequest
    local requests, answers, sendLoop = {}, {}, nil
    GetConvar = function(name, default) if name == 'preston_admin_webhook' then return 'https://discord.test/hook' end return default end
    CreateThread = function(fn) sendLoop = fn end
    PerformHttpRequest = function(_, cb, _, body)
        requests[#requests + 1] = body.saved
        local answer = table.remove(answers, 1) or { 204 }
        cb(answer[1], answer[2])
    end
    dofile('server/logs.lua') -- a fresh log module that sees the webhook
    GetConvar, CreateThread = realConvar, realThread
    -- Runs the send loop for a number of 1.5 second passes.
    local function pump(passes)
        local n = 0
        Wait = function(ms)
            n = n + 1
            if n > passes then error('stop', 0) end
            clockMs = clockMs + ms
        end
        pcall(sendLoop)
        Wait = realWait
    end

    for i = 1, 25 do Logs.add(ADMIN, 'Test action ' .. i, 'detail') end
    answers = { { 429, json.encode({ retry_after = 2 }) } }
    pump(5)
    eq(#requests, 4, 'one refused try, then three batches')
    eq(#requests[1].embeds, 10)
    eq(requests[2].embeds[1].title, 'Test action 1', 'the refused batch is sent again first')
    eq(#requests[3].embeds, 10)
    eq(#requests[4].embeds, 5)
    eq(#requests[4].allowed_mentions.parse, 0, 'never pings anyone')

    for i = 1, 520 do Logs.add(ADMIN, 'Flood ' .. i) end
    pump(1)
    local warned = false
    for _, line in ipairs(consoleLines) do if line:find('Discord fell behind: 20', 1, true) then warned = true end end
    eq(warned, true, 'the oldest 20 were dropped, and the console says so')
    eq(requests[#requests].embeds[1].title, 'Flood 21')
    PerformHttpRequest = realHttp
end)

say(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then
    say('Server console:')
    for _, line in ipairs(consoleLines) do say('  ' .. line) end
    error(('%d test(s) failed'):format(failed))
end
