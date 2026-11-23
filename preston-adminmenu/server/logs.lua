-- Records every admin action: in the server console, in the menu's Logs tab, and in Discord when a
-- webhook is set. The webhook URL is read from a server convar so it never reaches players' games.

Logs = {}

local U = PrestonAdminUtil
local recent = U.newRing(200)
local webhook = GetConvar('preston_admin_webhook', '')
local queue = {}
local dropped = 0        -- logs skipped because Discord fell too far behind
local MAX_QUEUE = 500    -- the newest logs win if Discord is down for a long time
local MAX_PER_MESSAGE = 10   -- Discord takes up to 10 embeds in one message...
local MAX_MESSAGE_CHARS = 5000 -- ...and about 6000 characters across them

local COLORS = { info = 3447003, warn = 15105570, danger = 15158332, success = 3066993 }

local function playerLabel(src)
    if not src or src == 0 then return 'Console' end
    return ('%s (#%d)'):format(GetPlayerName(src) or 'unknown', src)
end

local function license(src)
    if not src or src == 0 then return nil end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return nil
end

-- tone: 'info', 'warn', 'danger' or 'success' (the Discord embed color).
function Logs.add(actorSrc, action, detail, targetSrc, tone)
    local entry = {
        time = os.time(),
        actor = playerLabel(actorSrc),
        action = action,
        detail = detail or '',
        target = targetSrc and playerLabel(targetSrc) or nil,
        tone = COLORS[tone or 'info'] and tone or 'info',
    }
    recent.push(entry)
    print(('[preston-admin] %s: %s%s%s'):format(entry.actor, action,
        entry.target and (' -> ' .. entry.target) or '', entry.detail ~= '' and (' (' .. entry.detail .. ')') or ''))

    if webhook == '' then return end
    local fields = { { name = 'By', value = entry.actor .. (license(actorSrc) and ('\n`' .. license(actorSrc) .. '`') or ''), inline = true } }
    if entry.target then
        fields[#fields + 1] = { name = 'Player', value = entry.target .. (license(targetSrc) and ('\n`' .. license(targetSrc) .. '`') or ''), inline = true }
    end
    if #queue >= MAX_QUEUE then
        table.remove(queue, 1)
        dropped = dropped + 1
    end
    queue[#queue + 1] = {
        title = action,
        description = entry.detail ~= '' and entry.detail or nil,
        color = COLORS[entry.tone],
        fields = fields,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', entry.time),
        footer = { text = 'Preston Admin Menu v2' },
    }
end

function Logs.recent()
    return recent.list()
end

-- How many characters an embed adds to a message, as Discord counts them.
local function embedSize(embed)
    local n = #embed.title + #(embed.description or '') + #embed.footer.text
    for _, field in ipairs(embed.fields) do n = n + #field.name + #field.value end
    return n
end

-- Takes the next batch of embeds off the queue: up to 10, within Discord's size limit.
local function nextBatch()
    local batch, size = {}, 0
    while queue[1] and #batch < MAX_PER_MESSAGE do
        local add = embedSize(queue[1])
        if #batch > 0 and size + add > MAX_MESSAGE_CHARS then break end
        batch[#batch + 1] = table.remove(queue, 1)
        size = size + add
    end
    return batch
end

-- Sends the queue in batches, well under Discord's rate limit. If Discord says to slow down, the
-- batch goes back on the queue and is sent again after the wait Discord asked for.
CreateThread(function()
    if webhook == '' then return end
    local waitUntil = 0
    while true do
        Wait(1500)
        if dropped > 0 then
            print(('[preston-admin] Discord fell behind: %d older log(s) were not sent there.'):format(dropped))
            dropped = 0
        end
        local batch = GetGameTimer() >= waitUntil and nextBatch() or {}
        if #batch > 0 then
            PerformHttpRequest(webhook, function(status, body)
                if status == 200 or status == 204 then return end
                if status == 429 then
                    local ok, answer = pcall(json.decode, body or '')
                    local seconds = ok and type(answer) == 'table' and tonumber(answer.retry_after) or 5
                    waitUntil = GetGameTimer() + math.ceil(math.min(seconds, 300) * 1000)
                    for i = #batch, 1, -1 do table.insert(queue, 1, batch[i]) end
                    return
                end
                print(('[preston-admin] Discord webhook returned %s'):format(tostring(status)))
            end, 'POST', json.encode({
                username = 'Admin Menu',
                embeds = batch,
                -- Player names can contain @everyone; never let them ping anyone.
                allowed_mentions = { parse = {} },
            }), { ['Content-Type'] = 'application/json' })
        end
    end
end)
