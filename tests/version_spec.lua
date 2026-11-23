-- Tests for the update check (tools/version.lua) and the copy of it in every script.
-- Run from the repository's top folder with any Lua 5.3+:  lua tests/version_spec.lua

local SCRIPTS = {
    'preston-adminmenu', 'preston-els', 'preston-vehiclespawn', 'preston-vehicleskins',
    'preston-iowapolice', 'Prest_Sector-Cuffs', 'Prest_Sector-CAD',
}

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print(('FAIL %s: %s'):format(name, tostring(err)))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
    end
end
local function read(path)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('a'):gsub('\r\n', '\n')
    file:close()
    return text
end

local V = dofile('tools/version.lua')

test('versions are compared number by number', function()
    eq(V.isNewer('2.1.0', '2.0.0'), true)
    eq(V.isNewer('2.10.0', '2.9.3'), true, 'not compared as text')
    eq(V.isNewer('3.0', '2.9.9'), true, 'a missing patch number counts as 0')
    eq(V.isNewer('2.0.0', '2.0.0'), false)
    eq(V.isNewer('1.9.9', '2.0.0'), false)
    eq(V.isNewer('v2.2.0', '2.1.0'), true, 'a leading v is fine')
    eq(V.isNewer('banana', '1.0.0'), false, "unreadable versions don't count")
    eq(V.isNewer(nil, '1.0.0'), false)
end)

test('the version is read from a manifest', function()
    eq(V.manifestVersion("fx_version 'cerulean'\r\ngame 'gta5'\r\nversion '2.3.1'\r\n"), '2.3.1')
    eq(V.manifestVersion('version "4.0.0"'), '4.0.0', 'double quotes')
    eq(V.manifestVersion("fx_version 'cerulean'"), nil)
    eq(V.manifestVersion(nil), nil)
end)

test('the check asks GitHub and says when there is a newer version', function()
    local asked, printed = nil, {}
    local env = setmetatable({
        GetConvar = function(_, default) return default end,
        GetCurrentResourceName = function() return 'my-els' end,
        GetResourceMetadata = function(_, key) return ({ version = '2.1.0', portfolio_folder = 'preston-els' })[key] end,
        PerformHttpRequest = function(url, cb) asked = url cb(200, "version '2.2.0'\n") end,
        print = function(line) printed[#printed + 1] = line end,
    }, { __index = _G })
    local chunk = assert(loadfile('tools/version.lua', 't', env))
    chunk().check()
    eq(asked, 'https://raw.githubusercontent.com/fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO/main/preston-els/fxmanifest.lua')
    eq(#printed, 1)
    eq(printed[1]:find('Version 2.2.0 is out (this server has 2.1.0)', 1, true) ~= nil, true, printed[1])

    printed = {}
    env.PerformHttpRequest = function(_, cb) cb(200, "version '2.1.0'\n") end
    chunk().check()
    eq(#printed, 0, 'nothing said when up to date')

    env.PerformHttpRequest = function(_, cb) cb(404, 'Not Found') end
    chunk().check()
    eq(#printed, 0, 'nothing said when GitHub has no answer')

    env.GetConvar = function() return 'false' end
    asked = nil
    chunk().check()
    eq(asked, nil, 'turned off with set prest_check_updates false')
end)

test('every script ships the same update check and names its own folder', function()
    local original = read('tools/version.lua')
    for _, script in ipairs(SCRIPTS) do
        eq(read(script .. '/server/version.lua'), original, script .. '/server/version.lua matches tools/version.lua')
        local manifest = read(script .. '/fxmanifest.lua')
        eq(manifest:match("portfolio_folder%s+'([^']+)'"), script, script .. ' portfolio_folder')
        eq(manifest:find("server_script 'server/version.lua'", 1, true) ~= nil, true, script .. ' loads server/version.lua')
        eq(V.parse(V.manifestVersion(manifest)) ~= nil, true, script .. ' has a readable version')
    end
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then error(('%d test(s) failed'):format(failed)) end
