-- Prints a line in the server console when a newer version of this script is on GitHub. It only
-- downloads this script's fxmanifest.lua from the portfolio repository: nothing about your server
-- or players is sent. To turn it off, add this to server.cfg:
--   set prest_check_updates false
--
-- The same file ships in every script (server/version.lua). The original is tools/version.lua in
-- the repository, and tests/version_spec.lua checks every copy matches it.

local REPOSITORY = 'fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO'

local V = {}

-- '2.1.0' or 'v2.1' -> { 2, 1, 0 }; anything else -> nil.
function V.parse(text)
    if type(text) ~= 'string' then return nil end
    local major, minor, patch = text:match('^v?(%d+)%.(%d+)%.?(%d*)$')
    if not major then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch) or 0 }
end

-- Whether version `latest` is newer than `current`. Unreadable versions never count as newer.
function V.isNewer(latest, current)
    local a, b = V.parse(latest), V.parse(current)
    if not a or not b then return false end
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return false
end

-- The version line of an fxmanifest.lua, or nil.
function V.manifestVersion(text)
    if type(text) ~= 'string' then return nil end
    for line in (text .. '\n'):gmatch('([^\r\n]*)\r?\n') do
        local version = line:match("^%s*version%s*['\"]([^'\"]+)['\"]")
        if version then return version end
    end
    return nil
end

function V.check()
    if GetConvar('prest_check_updates', 'true') == 'false' then return end
    local resource = GetCurrentResourceName()
    local current = GetResourceMetadata(resource, 'version', 0)
    local folder = GetResourceMetadata(resource, 'portfolio_folder', 0)
    if not current or not folder or folder == '' then return end
    local url = ('https://raw.githubusercontent.com/%s/main/%s/fxmanifest.lua'):format(REPOSITORY, folder)
    PerformHttpRequest(url, function(status, body)
        if status ~= 200 then return end
        local latest = V.manifestVersion(body)
        if latest and V.isNewer(latest, current) then
            print(('[%s] Version %s is out (this server has %s). Get it at https://github.com/%s/tree/main/%s'):format(
                resource, latest, current, REPOSITORY, folder))
        end
    end, 'GET')
end

-- Wait until the server has finished starting, so the line isn't lost among the startup messages.
if CreateThread and PerformHttpRequest then
    CreateThread(function()
        Wait(10000)
        V.check()
    end)
end

return V
