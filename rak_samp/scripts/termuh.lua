-- Termuh: bundled Lua modules. Rebuild with tools/build_bundle.py.
package.preload["termuh-runtime"] = function(...)
-- Core runtime supplied with Termuh: no MoonLoader DLLs are required.
local M = {}
local codepoints = {1026,1027,8218,1107,8222,8230,8224,8225,8364,8240,1033,8249,1034,1036,1035,1039,1106,8216,8217,8220,8221,8226,8211,8212,65533,8482,1113,8250,1114,1116,1115,1119,160,1038,1118,1032,164,1168,166,167,1025,169,1028,171,172,173,174,1031,176,177,1030,1110,1169,181,182,183,1105,8470,1108,187,1112,1029,1109,1111,1040,1041,1042,1043,1044,1045,1046,1047,1048,1049,1050,1051,1052,1053,1054,1055,1056,1057,1058,1059,1060,1061,1062,1063,1064,1065,1066,1067,1068,1069,1070,1071,1072,1073,1074,1075,1076,1077,1078,1079,1080,1081,1082,1083,1084,1085,1086,1087,1088,1089,1090,1091,1092,1093,1094,1095,1096,1097,1098,1099,1100,1101,1102,1103}
local reverse = {}
for i, point in ipairs(codepoints) do reverse[point] = i + 127 end
local function utf8char(n)
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
    return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64)
end
M.UTF8 = {}
function M.UTF8:encode(text)
    return (text:gsub('[\128-\255]', function(c) return utf8char(codepoints[c:byte() - 127]) end))
end
function M.UTF8:decode(text)
    local result, pos = {}, 1
    while pos <= #text do
        local b, point, length = text:byte(pos), nil, 1
        if b < 128 then point = b
        elseif b >= 194 and b <= 223 then point, length = b - 192, 2
        elseif b >= 224 and b <= 239 then point, length = b - 224, 3
        elseif b >= 240 and b <= 244 then point, length = b - 240, 4 end
        if point then
            for i = 1, length - 1 do
                local c = text:byte(pos + i)
                if not c or c < 128 or c > 191 then point, length = nil, 1; break end
                point = point * 64 + c - 128
            end
        end
        result[#result + 1] = point and point < 128 and string.char(point)
            or point and reverse[point] and string.char(reverse[point]) or '?'
        pos = pos + length
    end
    return table.concat(result)
end
function M.loadIni(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local result, section = {}, nil
    for line in file:lines() do
        line = line:gsub('^\239\187\191', ''):gsub('\r$', '')
        local name = line:match('^%s*%[([^%]]+)%]%s*$')
        if name then
            section = name; result[section] = result[section] or {}
        elseif section and not line:match('^%s*[;#]') then
            local key, value = line:match('^%s*([^=%s]+)%s*=%s*(.-)%s*$')
            if key then
                if value == 'true' then value = true elseif value == 'false' then value = false end
                -- Preserve digit-only passwords and leading zeros as strings.
                result[section][key] = value
            end
        end
    end
    file:close()
    return result
end
local ok, socket = pcall(require, 'socket')
if ok and type(socket.gettime) == 'function' then
    M.gettime = socket.gettime
else
    local ffi = require('ffi')
    if ffi.os == 'Windows' then
        ffi.cdef('unsigned long long __stdcall GetTickCount64(void);')
        local kernel = ffi.load('kernel32')
        M.gettime = function() return tonumber(kernel.GetTickCount64()) / 1000 end
    else
        ffi.cdef('struct termuh_timespec { long tv_sec; long tv_nsec; }; int clock_gettime(int, struct termuh_timespec *);')
        local ts = ffi.new('struct termuh_timespec[1]')
        M.gettime = function()
            assert(ffi.C.clock_gettime(1, ts) == 0, 'monotonic clock unavailable')
            return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) / 1000000000
        end
    end
end
local ffi = require('ffi')
local address_field = ffi.os == 'Windows' and 'short' or 'int'
local call_type = ffi.os == 'Windows' and '__stdcall' or ''
ffi.cdef(([[
    struct termuh_hostent { char *name; char **aliases; %s addrtype; %s length; char **addresses; };
    struct termuh_hostent *%s gethostbyname(const char *name);
]]):format(address_field, address_field, call_type))
function M.resolveHost(host)
    local lib = ffi.os == 'Windows' and ffi.load('ws2_32') or ffi.C
    local entry = lib.gethostbyname(host)
    if entry == nil or entry.length ~= 4 or entry.addresses == nil or entry.addresses[0] == nil then
        return nil, 'DNS lookup failed'
    end
    local bytes = ffi.cast('unsigned char *', entry.addresses[0])
    return string.format('%d.%d.%d.%d', bytes[0], bytes[1], bytes[2], bytes[3])
end
return M

end
package.preload["termuh-servers"] = function(...)
-- Official launcher catalog, retrieved 2026-11-11. Hostnames allow DNS changes.
-- Source: https://api.arizona-five.com/launcher/servers
local M = {list = {
    {id=1, name="Phoenix", host="phoenix.arizona-rp.com", port=7777, mobile=false},
    {id=2, name="Tucson", host="tucson.arizona-rp.com", port=7777, mobile=false},
    {id=3, name="Scottdale", host="scottdale.arizona-rp.com", port=7777, mobile=false},
    {id=4, name="Chandler", host="chandler.arizona-rp.com", port=7777, mobile=false},
    {id=5, name="Brainburg", host="brainburg.arizona-rp.com", port=7777, mobile=false},
    {id=6, name="Saint-Rose", host="saintrose.arizona-rp.com", port=7777, mobile=false},
    {id=7, name="Mesa", host="mesa.arizona-rp.com", port=7777, mobile=false},
    {id=8, name="Red-Rock", host="redrock.arizona-rp.com", port=7777, mobile=false},
    {id=9, name="Yuma", host="yuma.arizona-rp.com", port=7777, mobile=false},
    {id=10, name="Surprise", host="surprise.arizona-rp.com", port=7777, mobile=false},
    {id=11, name="Prescott", host="prescott.arizona-rp.com", port=7777, mobile=false},
    {id=12, name="Glendale", host="glendale.arizona-rp.com", port=7777, mobile=false},
    {id=13, name="Kingman", host="kingman.arizona-rp.com", port=7777, mobile=false},
    {id=14, name="Winslow", host="winslow.arizona-rp.com", port=7777, mobile=false},
    {id=15, name="Payson", host="payson.arizona-rp.com", port=7777, mobile=false},
    {id=16, name="Gilbert", host="gilbert.arizona-rp.com", port=7777, mobile=false},
    {id=17, name="Show Low", host="showlow.arizona-rp.com", port=7777, mobile=false},
    {id=18, name="Casa-Grande", host="casagrande.arizona-rp.com", port=7777, mobile=false},
    {id=19, name="Page", host="page.arizona-rp.com", port=7777, mobile=false},
    {id=20, name="Sun-City", host="suncity.arizona-rp.com", port=7777, mobile=false},
    {id=21, name="Queen-Creek", host="queencreek.arizona-rp.com", port=7777, mobile=false},
    {id=22, name="Sedona", host="sedona.arizona-rp.com", port=7777, mobile=false},
    {id=23, name="Holiday", host="holiday.arizona-rp.com", port=7777, mobile=false},
    {id=24, name="Wednesday", host="wednesday.arizona-rp.com", port=7777, mobile=false},
    {id=25, name="Yava", host="yava.arizona-rp.com", port=7777, mobile=false},
    {id=26, name="Faraway", host="faraway.arizona-rp.com", port=7777, mobile=false},
    {id=27, name="Bumble Bee", host="bumblebee.arizona-rp.com", port=7777, mobile=false},
    {id=28, name="Christmas", host="christmas.arizona-rp.com", port=7777, mobile=false},
    {id=29, name="Mirage", host="mirage.arizona-rp.com", port=7777, mobile=false},
    {id=30, name="Love", host="love.arizona-rp.com", port=7777, mobile=false},
    {id=31, name="Drake", host="drake.arizona-rp.com", port=7777, mobile=false},
    {id=32, name="Space", host="space.arizona-rp.com", port=7777, mobile=false},
    {id=33, name="Home", host="home.arizona-rp.com", port=7777, mobile=false},
    {id=101, name="Mobile I", host="mobile1.arizona-rp.com", port=5125, mobile=true},
    {id=102, name="Mobile II", host="mobile2.arizona-rp.com", port=5125, mobile=true},
    {id=103, name="Mobile III", host="mobile3.arizona-rp.com", port=5125, mobile=true},
    {id=201, name="Vice City", host="80.66.82.147", port=7777, mobile=false},
}}
local function normalize(value) return tostring(value):lower():gsub('[%s%-_]','') end
function M.find(value)
    for _, server in ipairs(M.list) do
        if tostring(server.id) == tostring(value) or normalize(server.name) == normalize(value)
            or value == server.host or value == server.host .. ':' .. server.port then return server end
    end
end
return M

end
package.preload["termuh-preconnect"] = function(...)
-- Direct HTTP check based on the Blast.hk example supplied by the user.
-- Windows Winsock, nonblocking: update() never waits on the network.
local ffi = require('ffi')
local M = {}
if ffi.os ~= 'Windows' then
    function M.start() return nil, 'Windows Winsock unavailable' end
    return M
end
ffi.cdef[[
    typedef uintptr_t termuh_socket;
    struct termuh_sockaddr_in { uint16_t family; uint16_t port; uint32_t address; uint8_t zero[8]; };
    struct termuh_fd_set { uint32_t count; termuh_socket sockets[64]; };
    struct termuh_timeval { long sec; long usec; };
    int __stdcall WSAStartup(unsigned short version, void *data);
    int __stdcall WSACleanup(void);
    int __stdcall WSAGetLastError(void);
    termuh_socket __stdcall socket(int family, int type, int protocol);
    int __stdcall closesocket(termuh_socket s);
    int __stdcall ioctlsocket(termuh_socket s, long command, unsigned long *arg);
    int __stdcall connect(termuh_socket s, const void *addr, int len);
    int __stdcall select(int nfds, struct termuh_fd_set *readfds, struct termuh_fd_set *writefds,
                         struct termuh_fd_set *exceptfds, const struct termuh_timeval *timeout);
    int __stdcall getsockopt(termuh_socket s, int level, int name, void *value, int *len);
    int __stdcall send(termuh_socket s, const char *buf, int len, int flags);
    int __stdcall recv(termuh_socket s, char *buf, int len, int flags);
    unsigned long __stdcall inet_addr(const char *address);
    unsigned short __stdcall htons(unsigned short value);
]]
local winsock = ffi.load('ws2_32')
local invalid = ffi.cast('termuh_socket', -1)
local would_block = 10035
local function finish(self, ok, detail)
    if self.done then return end
    self.done, self.ok, self.detail = true, ok, detail
    if self.socket then winsock.closesocket(self.socket); self.socket = nil end
    if self.started then winsock.WSACleanup(); self.started = false end
end
function M.start(ip, clock, timeout_ms, port)
    -- No DNS lookup in this hook: use the already-selected game's IPv4 address.
    if type(ip) ~= 'string' or not ip:match('^%d+%.%d+%.%d+%.%d+$') then
        return nil, 'invalid IPv4 address'
    end
    local resolved = winsock.inet_addr(ip)
    if resolved == 0xffffffff then return nil, 'invalid IPv4 address' end
    local data = ffi.new('uint8_t[512]')
    local started = winsock.WSAStartup(0x0202, data)
    if started ~= 0 then return nil, 'WSAStartup error ' .. started end
    local self = {started = true, clock = clock, deadline = clock() + timeout_ms / 1000,
        state = 'connecting', request = 'GET / HTTP/1.1\r\nHost: ' .. ip .. '\r\nConnection: close\r\n\r\n',
        written = 0, response = ''}
    self.socket = winsock.socket(2, 1, 6)
    if self.socket == invalid then self.socket = nil; finish(self, false, 'socket error'); return self end
    local mode = ffi.new('unsigned long[1]', 1)
    -- FIONBIO, bit-preserving signed long argument.
    if winsock.ioctlsocket(self.socket, -2147195266, mode) ~= 0 then finish(self, false, 'nonblocking mode error'); return self end
    local address = ffi.new('struct termuh_sockaddr_in')
    address.family, address.port, address.address = 2, winsock.htons(port or 80), resolved
    if winsock.connect(self.socket, address, ffi.sizeof(address)) ~= 0 then
        local err = winsock.WSAGetLastError()
        if err ~= would_block and err ~= 10036 then finish(self, false, 'connect error ' .. err) end
    end
    return self
end
function M.cancel(self)
    if self then finish(self, false, 'cancelled') end
end
function M.update(self)
    if self.done then return self.ok, self.detail end
    if self.clock() >= self.deadline then finish(self, false, 'timeout'); return self.ok, self.detail end
    if self.state == 'connecting' then
        local writefds, exceptfds = ffi.new('struct termuh_fd_set'), ffi.new('struct termuh_fd_set')
        writefds.count, writefds.sockets[0] = 1, self.socket
        exceptfds.count, exceptfds.sockets[0] = 1, self.socket
        local timeout = ffi.new('struct termuh_timeval')
        local ready = winsock.select(0, nil, writefds, exceptfds, timeout)
        if ready < 0 then finish(self, false, 'select error'); return self.ok, self.detail end
        if ready == 0 then return end
        local error_code, length = ffi.new('int[1]'), ffi.new('int[1]', ffi.sizeof('int'))
        if winsock.getsockopt(self.socket, 0xffff, 0x1007, error_code, length) ~= 0 or error_code[0] ~= 0 or exceptfds.count ~= 0 then
            finish(self, false, 'connect error ' .. error_code[0]); return self.ok, self.detail
        end
        self.state = 'sending'
    end
    if self.state == 'sending' then
        local remaining = self.request:sub(self.written + 1)
        local sent = winsock.send(self.socket, remaining, #remaining, 0)
        if sent < 0 then
            if winsock.WSAGetLastError() ~= would_block then finish(self, false, 'send error') end
            return self.ok, self.detail
        elseif sent == 0 then
            finish(self, false, 'connection closed'); return self.ok, self.detail
        end
        self.written = self.written + sent
        if self.written < #self.request then return end
        self.state = 'reading'
    end
    if self.state == 'reading' then
        local buffer = ffi.new('char[512]')
        local received = winsock.recv(self.socket, buffer, 512, 0)
        if received < 0 then
            if winsock.WSAGetLastError() ~= would_block then finish(self, false, 'receive error') end
        elseif received == 0 then
            finish(self, false, 'connection closed before HTTP status')
        else
            self.response = self.response .. ffi.string(buffer, received)
            local line = self.response:match('^([^\r\n]*)\r?\n')
            if line then
                local status = tonumber(line:match('^HTTP/%d%.%d%s+(%d%d%d)%s'))
                if status then finish(self, status == 200 or status == 404, 'HTTP ' .. status)
                else finish(self, false, 'invalid HTTP status') end
            elseif #self.response > 1024 then finish(self, false, 'HTTP status line too long') end
        end
    end
    if self.done then return self.ok, self.detail end
end
return M

end
package.preload["termuh-launcher"] = function(...)
-- Experimental Arizona handshake adapted from the user-supplied new_launcher_emulation.lua.
-- It does not implement a browser or prove the authenticity of an official launcher.
local M = {}
local auth_key = '263083C359F5AE44AD3AFC8551F4208E6C84A36F6CC'
local validation = '5429be308f3dba94adc47932121cb424386fb1d5d2232617da3a4aae9c24d659'

local function secureId()
    local ffi = require('ffi')
    if ffi.os ~= 'Windows' then return nil, 'Windows random source unavailable' end
    ffi.cdef('long __stdcall BCryptGenRandom(void *, unsigned char *, unsigned long, unsigned long);')
    local ok, bcrypt = pcall(ffi.load, 'bcrypt')
    if not ok then return nil, 'Windows random source unavailable' end
    local buf = ffi.new('unsigned char[32]')
    if bcrypt.BCryptGenRandom(nil, buf, 32, 2) ~= 0 then return nil, 'Windows random source failed' end
    local result = {}
    for i=0,31 do result[#result+1] = string.format('%02x', buf[i]) end
    return table.concat(result)
end

function M.ensureId(path, random)
    local file = io.open(path, 'rb')
    if file then
        local value = file:read('*a'); file:close()
        if #value == 64 and value:match('^[0-9a-f]+$') then return value end
        return nil, 'Invalid saved launcher identifier'
    end
    local value, err = (random or secureId)()
    if not value or #value ~= 64 or not value:match('^[0-9a-f]+$') then return nil, err or 'Invalid generated launcher identifier' end
    file = io.open(path, 'wb')
    if not file then return nil, 'Cannot save launcher identifier' end
    local written = file:write(value)
    local closed = file:close()
    if not written or not closed then return nil, 'Cannot save launcher identifier' end
    return value
end

local function packet(prefix, payload)
    local bs = bitStream.new()
    for _, v in ipairs(prefix) do bs:writeUInt8(v) end
    if payload then bs:writeString(payload) end
    bs:sendPacket()
end

local function cef(text)
    local bs = bitStream.new()
    bs:writeUInt8(220); bs:writeUInt8(18); bs:writeUInt16(#text)
    bs:writeString(text); bs:writeUInt32(0); bs:writeUInt16(0)
    bs:sendPacket()
end

function M.bootstrap()
    cef('onSvelteAppInit')
    cef('onSvelteAppVersion|1.0.0|ea94b29b')
end

function M.validate(nickname, id)
    packet({220,20,128,7,0,0,56,4,0,0})
    packet({220,50,1})
    packet({220,38}, validation)
    local path = ('"gta_sa.exe"  -c -h  -p 7777 -n %s -mem 2048 -window -x -widescreen -graphics -enable_grass -arizona -userId %s -cdn 0,0,0 -referrer'):format(nickname, id)
    local bs = bitStream.new()
    bs:writeUInt8(220); bs:writeUInt8(140); bs:writeUInt32(#path)
    bs:writeString(path); bs:writeUInt8(0); bs:sendPacket()
end

function M.attach(events, enabled, allowed, schedule, getId)
    local previous = events.onSendClientJoin
    local epoch = 0
    registerHandler('onDisconnect', function() epoch = epoch + 1 end)
    events.onSendClientJoin = function(version, mod, nickname, challenge, key, client, challenge2)
        local old = previous and previous(version, mod, nickname, challenge, key, client, challenge2)
        if old == false then return false end
        local args = type(old) == 'table' and old or {version, mod, nickname, challenge, key, client, challenge2}
        if not enabled() or not allowed() then return old end
        if type(args[3]) ~= 'string' or #args[3] > 24 or not args[3]:match('^[A-Za-z0-9_]+$') then return old end
        local id, err = getId()
        if not id then print('[LAUNCHER] ' .. tostring(err) .. '; join cancelled'); return false end
        epoch = epoch + 1
        local expected_epoch, address = epoch, getServerAddress()
        M.bootstrap()
        schedule(function()
            wait(100)
            if epoch == expected_epoch and isBotConnected() and getServerAddress() == address and allowed() then
                M.validate(args[3], id)
                print('[LAUNCHER] Validation packets sent')
            end
        end)
        print('[LAUNCHER] Experimental handshake scheduled')
        return {4057, 1, args[3], args[4], auth_key, 'Arizona PC', args[7]}
    end
end
return M

end
package.preload["termuh-panel"] = function(...)
-- Per-instance local IPC. Dialog text is local and response input is short-lived.
local M = {}
function M.start(runtime, sessionTask)
    local origin, spawn_seen, last_write, stats = nil, nil, 0, {}
    local dead, deaths, spawns, last_dialog, stats_at = false, 0, 0, 'none', 0
    local was_connected = false
    local events = require('samp.events')
    local dialogs = require('arizona-cef-dialogs')
    local ffi = require('ffi')
    local publish = os.rename
    if ffi.os == 'Windows' then
        ffi.cdef('int __stdcall MoveFileExA(const char *, const char *, unsigned long);')
        local kernel = ffi.load('kernel32')
        publish = function(from, to) return kernel.MoveFileExA(from, to, 1) ~= 0 end
    end
    local function hex(value)
        return (value:gsub('.', function(c) return string.format('%02x', c:byte()) end))
    end
    local function unhex(value)
        if #value > 510 or #value % 2 ~= 0 then return nil end
        return (value:gsub('(%x%x)', function(pair) return string.char(tonumber(pair, 16)) end))
    end
    local function clearSession()
        origin, spawn_seen, stats, dead = nil, nil, {}, false
        deaths, spawns, last_dialog, stats_at = 0, 0, 'none', 0
        last_write = 0
    end
    registerHandler('onConnect', function() clearSession(); was_connected = true end)
    registerHandler('onDisconnect', function() clearSession(); was_connected = false end)
    local previous_spawn = events.onSendSpawn
    events.onSendSpawn = function(...)
        local result = previous_spawn and previous_spawn(...)
        if result ~= false then
            origin, spawn_seen, dead = nil, nil, false
            spawns = spawns + 1
        end
        return result
    end
    local previous_death = events.onSendDeathNotification
    events.onSendDeathNotification = function(...)
        local result = previous_death and previous_death(...)
        if result ~= false and not dead then
            origin, spawn_seen, dead = nil, nil, true
            deaths = deaths + 1
        end
        return result
    end
    local previous_health = events.onSetPlayerHealth
    events.onSetPlayerHealth = function(health)
        local result = previous_health and previous_health(health)
        local effective_health = type(result) == 'table' and result[1] or health
        if result ~= false and type(effective_health) == 'number' and effective_health <= 0 and not dead then
            origin, spawn_seen, dead = nil, nil, true
            deaths = deaths + 1
        end
        return result
    end
    local previous = events.onShowDialog
    events.onShowDialog = function(id, style, title, b1, b2, body)
        local clean_title = runtime.UTF8:encode(title):gsub('%{......%}', '')
        if id == 65535 then
            last_dialog = 'none'
        elseif clean_title == 'Основная статистика' and style == 0 then
            last_dialog = 'stats'
            stats_at = os.time()
            local text = runtime.UTF8:encode(body):gsub('%{......%}', '')
            stats.level = text:match('Уровень:%s*%[(%d+)%]') or ''
            stats.cash = text:match('Наличные деньги %(SA%$%)%s*:%s*:?CASH:?([%d%.]+)') or ''
            stats.bank = text:match('Деньги в банке:%s*:?CASH:?([%d%.]+)') or ''
            stats.paydays = text:match('Талон X4 PayDay:%s*Осталось:%s*(%d+)') or ''
        elseif clean_title:find('Авторизация',1,true) then last_dialog = 'auth'
        elseif clean_title:find('Игровое меню',1,true) then last_dialog = 'menu'
        else last_dialog = 'other' end
        if previous then return previous(id, style, title, b1, b2, body) end
    end
    registerHandler('onUpdate', function()
        local now = runtime.gettime()
        if now - last_write < 2 then return end
        last_write = now
        local connected = isBotConnected()
        if was_connected and not connected then
            clearSession()
        end
        was_connected = connected
        local spawned = connected and not dead and isBotSpawned()
        local x, y, z, drift, health, armor, level = 0, 0, 0, 0, 0, 0, 0
        if spawned then
            x, y, z = getBotPosition()
            spawn_seen = spawn_seen or now
            if not origin and now - spawn_seen >= 8 then origin = {x=x, y=y, z=z} end
            if origin then drift = math.sqrt((x-origin.x)^2 + (y-origin.y)^2 + (z-origin.z)^2) end
            health, armor, level = getBotHealth(), getBotArmor(), getBotScore()
        else origin = nil; spawn_seen = nil end
        local file = io.open('termuh\\panel-state.tmp', 'w')
        if file then
            file:write(('connected=%s\nspawned=%s\nsettling=%s\nx=%.3f\ny=%.3f\nz=%.3f\ndrift=%.3f\nhealth=%d\narmor=%d\nlevel=%d\ndead=%s\ndeaths=%d\nspawns=%d\ndialog=%s\nstats_at=%d\ncash=%s\nbank=%s\npaydays=%s\n'):format(
                tostring(connected), tostring(spawned), tostring(spawned and not origin), x,y,z,drift,health,armor,level,tostring(dead),deaths,spawns,last_dialog,stats_at,stats.cash or '',stats.bank or '',stats.paydays or ''))
            if connected and dialogs.IsDialogActive() then
                file:write(('dialog_active=true\ndialog_revision=%d\ndialog_id=%d\ndialog_style=%d\ndialog_title=%s\ndialog_text=%s\ndialog_button1=%s\ndialog_button2=%s\n'):format(
                    dialogs.generation, dialogs.GetId(), dialogs.GetStyle(), hex(dialogs.GetTitle()),
                    hex(dialogs.GetDialogText()), hex(dialogs.GetButton1()), hex(dialogs.GetButton2())))
            else
                file:write('dialog_active=false\n')
            end
            local closed = file:close()
            if closed then publish('termuh\\panel-state.tmp', 'termuh\\panel-state.txt') end
        end
        local cmd = io.open('termuh\\panel-command.txt', 'r')
        if cmd then
            local command = cmd:read('*l'); cmd:close()
            local removed = os.remove('termuh\\panel-command.txt')
            if not removed then return end
            if spawned and command == '!anchor' then
                origin, spawn_seen = nil, now
            elseif spawned and (command == '/stats' or command == '/mm') then
                runCommand(command)
            elseif connected and type(command) == 'string' then
                local revision, id, button, list, input = command:match('^dialog|(%d+)|(%d+)|([01])|(-?%d+)|([%x]*)$')
                input = input and unhex(input)
                if revision and input and dialogs.IsDialogActive() and dialogs.generation == tonumber(revision)
                    and dialogs.GetId() == tonumber(id) and type(humanDialogResponse) == 'function' then
                    humanDialogResponse(tonumber(id), tonumber(button), tonumber(list), input)
                end
            end
        end
    end)
end
return M

end
package.preload["vector3d"] = function(...)
-- This file is part of SA MoonLoader package.
-- Licensed under the MIT License.
-- Copyright (c) 2016, BlastHack Team <blast.hk>

-- Vector3D class
-- authors: MTA Team (original MTA's CVector), FYP (lua implementation)


local EPSILON = 0.0001
local function isNearZero(f)
	return math.abs(f) < EPSILON
end

Vector3D = function(x, y, z)
	local mt = {}
	local obj = {
		x = x,
		y = y,
		z = z
	}

	function obj:get()
		return self.x, self.y, self.z
	end

	function obj:length()
		return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
	end

	function obj:normalize()
		local len = self:length()
		if len < EPSILON then return 0 end
		self.x = self.x / len
		self.y = self.y / len
		self.z = self.z / len
		return len
	end

	function obj:zeroNearZero()
		if isNearZero(self.x) then self.x = 0 end
		if isNearZero(self.y) then self.y = 0 end
		if isNearZero(self.z) then self.z = 0 end
	end

	function obj:dotProduct(v)
		return self.x * v.x + self.y * v.y + self.z * v.z
	end

	function obj:crossProduct(v)
		local x, y, z = self.x, self.y, self.z
		self.x = y * v.z - v.y * z
		self.y = z * v.x - v.z * x
		self.z = x * v.y - v.x * y
	end

	obj.zero_near_zero = obj.zeroNearZero
	obj.dot_product = obj.dotProduct
	obj.cross_product = obj.crossProduct

	-- meta
	function mt:__add(v)
		return Vector3D(self.x + v.x, self.y + v.y, self.z + v.z)
	end

	function mt:__mul(v)
		if type(v) == "number" then
			return Vector3D(self.x * v, self.y * v, self.z * v)
		end
		return Vector3D(self.x * v.x, self.y * v.y, self.z * v.z)
	end

	function mt:__sub(v)
		return Vector3D(self.x - v.x, self.y - v.y, self.z - v.z)
	end

	setmetatable(obj, mt)
	return obj
end

return Vector3D

end
package.preload["sampfuncs"] = function(...)
-- This file is part of SA MoonLoader package.
-- Licensed under the MIT License.
-- Copyright (c) 2016, BlastHack Team <blast.hk>

local sampfuncs = {

-- RPCs
RPC_CLICKPLAYER                                = 23,
RPC_CLIENTJOIN                                 = 25,
RPC_ENTERVEHICLE                               = 26,
RPC_ENTEREDITOBJECT                            = 27,
RPC_SCRIPTCASH                                 = 31,
RPC_SERVERCOMMAND                              = 50,
RPC_SPAWN                                      = 52,
RPC_DEATH                                      = 53,
RPC_NPCJOIN                                    = 54,
RPC_DIALOGRESPONSE                             = 62,
RPC_CLICKTEXTDRAW                              = 83,
RPC_SCMEVENT                                   = 96,
RPC_WEAPONPICKUPDESTROY                        = 97,
RPC_CHAT                                       = 101,
RPC_SRVNETSTATS                                = 102,
RPC_CLIENTCHECK                                = 103,
RPC_DAMAGEVEHICLE                              = 106,
RPC_GIVETAKEDAMAGE                             = 115,
RPC_EDITATTACHEDOBJECT                         = 116,
RPC_EDITOBJECT                                 = 117,
RPC_SETINTERIORID                              = 118,
RPC_MAPMARKER                                  = 119,
RPC_REQUESTCLASS                               = 128,
RPC_REQUESTSPAWN                               = 129,
RPC_PICKEDUPPICKUP                             = 131,
RPC_MENUSELECT                                 = 132,
RPC_VEHICLEDESTROYED                           = 136,
RPC_MENUQUIT                                   = 140,
RPC_EXITVEHICLE                                = 154,
RPC_UPDATESCORESPINGSIPS                       = 155,

RPC_SCRSETPLAYERNAME                           = 11,
RPC_SCRSETPLAYERPOS                            = 12,
RPC_SCRSETPLAYERPOSFINDZ                       = 13,
RPC_SCRSETPLAYERHEALTH                         = 14,
RPC_SCRTOGGLEPLAYERCONTROLLABLE                = 15,
RPC_SCRPLAYSOUND                               = 16,
RPC_SCRSETPLAYERWORLDBOUNDS                    = 17,
RPC_SCRGIVEPLAYERMONEY                         = 18,
RPC_SCRSETPLAYERFACINGANGLE                    = 19,
RPC_SCRRESETPLAYERMONEY                        = 20,
RPC_SCRRESETPLAYERWEAPONS                      = 21,
RPC_SCRGIVEPLAYERWEAPON                        = 22,
RPC_SCRSETVEHICLEPARAMSEX                      = 24,
RPC_SCRCANCELEDIT                              = 28,
RPC_SCRSETPLAYERTIME                           = 29,
RPC_SCRTOGGLECLOCK                             = 30,
RPC_SCRWORLDPLAYERADD                          = 32,
RPC_SCRSETPLAYERSHOPNAME                       = 33,
RPC_SCRSETPLAYERSKILLLEVEL                     = 34,
RPC_SCRSETPLAYERDRUNKLEVEL                     = 35,
RPC_SCRCREATE3DTEXTLABEL                       = 36,
RPC_SCRDISABLECHECKPOINT                       = 37,
RPC_SCRSETRACECHECKPOINT                       = 38,
RPC_SCRDISABLERACECHECKPOINT                   = 39,
RPC_SCRGAMEMODERESTART                         = 40,
RPC_SCRPLAYAUDIOSTREAM                         = 41,
RPC_SCRSTOPAUDIOSTREAM                         = 42,
RPC_SCRREMOVEBUILDINGFORPLAYER                 = 43,
RPC_SCRCREATEOBJECT                            = 44,
RPC_SCRSETOBJECTPOS                            = 45,
RPC_SCRSETOBJECTROT                            = 46,
RPC_SCRDESTROYOBJECT                           = 47,
RPC_SCRDEATHMESSAGE                            = 55,
RPC_SCRSETPLAYERMAPICON                        = 56,
RPC_SCRREMOVEVEHICLECOMPONENT                  = 57,
RPC_SCRUPDATE3DTEXTLABEL                       = 58,
RPC_SCRCHATBUBBLE                              = 59,
RPC_SCRSOMEUPDATE                              = 60,
RPC_SCRSHOWDIALOG                              = 61,
RPC_SCRDESTROYPICKUP                           = 63,
RPC_SCRLINKVEHICLETOINTERIOR                   = 65,
RPC_SCRSETPLAYERARMOUR                         = 66,
RPC_SCRSETPLAYERARMEDWEAPON                    = 67,
RPC_SCRSETSPAWNINFO                            = 68,
RPC_SCRSETPLAYERTEAM                           = 69,
RPC_SCRPUTPLAYERINVEHICLE                      = 70,
RPC_SCRREMOVEPLAYERFROMVEHICLE                 = 71,
RPC_SCRSETPLAYERCOLOR                          = 72,
RPC_SCRDISPLAYGAMETEXT                         = 73,
RPC_SCRFORCECLASSSELECTION                     = 74,
RPC_SCRATTACHOBJECTTOPLAYER                    = 75,
RPC_SCRINITMENU                                = 76,
RPC_SCRSHOWMENU                                = 77,
RPC_SCRHIDEMENU                                = 78,
RPC_SCRCREATEEXPLOSION                         = 79,
RPC_SCRSHOWPLAYERNAMETAGFORPLAYER              = 80,
RPC_SCRATTACHCAMERATOOBJECT                    = 81,
RPC_SCRINTERPOLATECAMERA                       = 82,
RPC_SCRSETOBJECTMATERIAL                       = 84,
RPC_SCRGANGZONESTOPFLASH                       = 85,
RPC_SCRAPPLYANIMATION                          = 86,
RPC_SCRCLEARANIMATIONS                         = 87,
RPC_SCRSETPLAYERSPECIALACTION                  = 88,
RPC_SCRSETPLAYERFIGHTINGSTYLE                  = 89,
RPC_SCRSETPLAYERVELOCITY                       = 90,
RPC_SCRSETVEHICLEVELOCITY                      = 91,
RPC_SCRCLIENTMESSAGE                           = 93,
RPC_SCRSETWORLDTIME                            = 94,
RPC_SCRCREATEPICKUP                            = 95,
RPC_SCRMOVEOBJECT                              = 99,
RPC_SCRENABLESTUNTBONUSFORPLAYER               = 104,
RPC_SCRTEXTDRAWSETSTRING                       = 105,
RPC_SCRSETCHECKPOINT                           = 107,
RPC_SCRGANGZONECREATE                          = 108,
RPC_SCRPLAYCRIMEREPORT                         = 112,
RPC_SCRSETPLAYERATTACHEDOBJECT                 = 113,
RPC_SCRGANGZONEDESTROY                         = 120,
RPC_SCRGANGZONEFLASH                           = 121,
RPC_SCRSTOPOBJECT                              = 122,
RPC_SCRSETNUMBERPLATE                          = 123,
RPC_SCRTOGGLEPLAYERSPECTATING                  = 124,
RPC_SCRPLAYERSPECTATEPLAYER                    = 126,
RPC_SCRPLAYERSPECTATEVEHICLE                   = 127,
RPC_SCRSETPLAYERWANTEDLEVEL                    = 133,
RPC_SCRSHOWTEXTDRAW                            = 134,
RPC_SCRTEXTDRAWHIDEFORPLAYER                   = 135,
RPC_SCRSERVERJOIN                              = 137,
RPC_SCRSERVERQUIT                              = 138,
RPC_SCRINITGAME                                = 139,
RPC_SCRREMOVEPLAYERMAPICON                     = 144,
RPC_SCRSETPLAYERAMMO                           = 145,
RPC_SCRSETGRAVITY                              = 146,
RPC_SCRSETVEHICLEHEALTH                        = 147,
RPC_SCRATTACHTRAILERTOVEHICLE                  = 148,
RPC_SCRDETACHTRAILERFROMVEHICLE                = 149,
RPC_SCRSETWEATHER                              = 152,
RPC_SCRSETPLAYERSKIN                           = 153,
RPC_SCRSETPLAYERINTERIOR                       = 156,
RPC_SCRSETPLAYERCAMERAPOS                      = 157,
RPC_SCRSETPLAYERCAMERALOOKAT                   = 158,
RPC_SCRSETVEHICLEPOS                           = 159,
RPC_SCRSETVEHICLEZANGLE                        = 160,
RPC_SCRSETVEHICLEPARAMSFORPLAYER               = 161,
RPC_SCRSETCAMERABEHINDPLAYER                   = 162,
RPC_SCRWORLDPLAYERREMOVE                       = 163,
RPC_SCRWORLDVEHICLEADD                         = 164,
RPC_SCRWORLDVEHICLEREMOVE                      = 165,
RPC_SCRWORLDPLAYERDEATH                        = 166,

-- Packets
PACKET_INTERNAL_PING                           = 6,
PACKET_PING                                    = 7,
PACKET_PING_OPEN_CONNECTIONS                   = 8,
PACKET_CONNECTED_PONG                          = 9,
PACKET_REQUEST_STATIC_DATA                     = 10,
PACKET_CONNECTION_REQUEST                      = 11,
PACKET_AUTH_KEY                                = 12,
PACKET_BROADCAST_PINGS                         = 14,
PACKET_SECURED_CONNECTION_RESPONSE             = 15,
PACKET_SECURED_CONNECTION_CONFIRMATION         = 16,
PACKET_RPC_MAPPING                             = 17,
PACKET_SET_RANDOM_NUMBER_SEED                  = 19,
PACKET_RPC                                     = 20,
PACKET_RPC_REPLY                               = 21,
PACKET_DETECT_LOST_CONNECTIONS                 = 23,
PACKET_OPEN_CONNECTION_REQUEST                 = 24,
PACKET_OPEN_CONNECTION_REPLY                   = 25,
PACKET_CONNECTION_COOKIE                       = 26,
PACKET_RSA_PUBLIC_KEY_MISMATCH                 = 28,
PACKET_CONNECTION_ATTEMPT_FAILED               = 29,
PACKET_NEW_INCOMING_CONNECTION                 = 30,
PACKET_NO_FREE_INCOMING_CONNECTIONS            = 31,
PACKET_DISCONNECTION_NOTIFICATION              = 32,
PACKET_CONNECTION_LOST                         = 33,
PACKET_CONNECTION_REQUEST_ACCEPTED             = 34,
PACKET_INITIALIZE_ENCRYPTION                   = 35,
PACKET_CONNECTION_BANNED                       = 36,
PACKET_INVALID_PASSWORD                        = 37,
PACKET_MODIFIED_PACKET                         = 38,
PACKET_PONG                                    = 39,
PACKET_TIMESTAMP                               = 40,
PACKET_RECEIVED_STATIC_DATA                    = 41,
PACKET_REMOTE_DISCONNECTION_NOTIFICATION       = 42,
PACKET_REMOTE_CONNECTION_LOST                  = 43,
PACKET_REMOTE_NEW_INCOMING_CONNECTION          = 44,
PACKET_REMOTE_EXISTING_CONNECTION              = 45,
PACKET_REMOTE_STATIC_DATA                      = 46,
PACKET_ADVERTISE_SYSTEM                        = 56,

PACKET_VEHICLE_SYNC                            = 200,
PACKET_RCON_COMMAND                            = 201,
PACKET_RCON_RESPONCE                           = 202,
PACKET_AIM_SYNC                                = 203,
PACKET_WEAPONS_UPDATE                          = 204,
PACKET_STATS_UPDATE                            = 205,
PACKET_BULLET_SYNC                             = 206,
PACKET_PLAYER_SYNC                             = 207,
PACKET_MARKERS_SYNC                            = 208,
PACKET_UNOCCUPIED_SYNC                         = 209,
PACKET_TRAILER_SYNC                            = 210,
PACKET_PASSENGER_SYNC                          = 211,
PACKET_SPECTATOR_SYNC                          = 212,

-- Gamestates
GAMESTATE_NONE                                 = 0,
GAMESTATE_WAIT_CONNECT                         = 1,
GAMESTATE_AWAIT_JOIN                           = 2,
GAMESTATE_CONNECTED                            = 3,
GAMESTATE_RESTARTING                           = 4,
GAMESTATE_DISCONNECTED                         = 5,

-- BitStream
BS_TYPE_BYTE                                   = 0,
BS_TYPE_BOOL                                   = 1,
BS_TYPE_SHORT                                  = 2,
BS_TYPE_INT                                    = 3,
BS_TYPE_FLOAT                                  = 4,
BS_TYPE_ARRAY                                  = 5,
BS_TYPE_BITSTREAM                              = 6,

-- Priorities
SYSTEM_PRIORITY                                = 0,
HIGH_PRIORITY                                  = 1,
MEDIUM_PRIORITY                                = 2,
LOW_PRIORITY                                   = 3,

-- Reliability
UNRELIABLE                                     = 6,
UNRELIABLE_SEQUENCED                           = 7,
RELIABLE                                       = 8,
RELIABLE_ORDERED                               = 9,
RELIABLE_SEQUENCED                             = 10,

-- Sendrates
ONFOOTSENDRATE                                 = 1,
INCARSENDRATE                                  = 2,
AIMSENDRATE                                    = 3,

-- SAMP Limits
MAX_PLAYERS                                    = 1004,
MAX_VEHICLES                                   = 2000,
MAX_PICKUPS                                    = 4096,
MAX_OBJECTS                                    = 1000,
MAX_GANGZONES                                  = 1024,
MAX_3DTEXTS                                    = 2048,
MAX_TEXTDRAWS                                  = 2048,
MAX_CLIENTCMDS                                 = 144,
MAX_MENUS                                      = 128,

-- Text Styles
FCR_NONE                                       = 0x0,
FCR_BOLD                                       = 0x1,
FCR_ITALICS                                    = 0x2,
FCR_BORDER                                     = 0x4,
FCR_SHADOW                                     = 0x8,
FCR_UNDERLINE                                  = 0x10,
FCR_STRIKEOUT                                  = 0x20,

-- SAMP SCM Events
SCMEVENT_PAINTJOB                              = 1,
SCMEVENT_UPGRADE                               = 2,
SCMEVENT_COLOR                                 = 3,
SCMEVENT_MODSHOPENTEREXIT                      = 4,

-- Special Actions
SPECIAL_ACTION_NONE                            = 0,
SPECIAL_ACTION_DUCK                            = 1,
SPECIAL_ACTION_USEJETPACK                      = 2,
SPECIAL_ACTION_ENTER_VEHICLE                   = 3,
SPECIAL_ACTION_EXIT_VEHICLE                    = 4,
SPECIAL_ACTION_DANCE1                          = 5,
SPECIAL_ACTION_DANCE2                          = 6,
SPECIAL_ACTION_DANCE3                          = 7,
SPECIAL_ACTION_DANCE4                          = 8,
SPECIAL_ACTION_HANDSUP                         = 10,
SPECIAL_ACTION_USECELLPHONE                    = 11,
SPECIAL_ACTION_SITTING                         = 12,
SPECIAL_ACTION_STOPUSECELLPHONE                = 13,
SPECIAL_ACTION_DRINK_BEER                      = 20,
SPECIAL_ACTION_SMOKE_CIGGY                     = 21,
SPECIAL_ACTION_DRINK_WINE                      = 22,
SPECIAL_ACTION_DRINK_SPRUNK                    = 23,
SPECIAL_ACTION_CUFFED                          = 24,
SPECIAL_ACTION_CARRY                           = 25,
SPECIAL_ACTION_URINATE                         = 68,

-- SAMP Dialog Styles
DIALOG_STYLE_MSGBOX                            = 0,
DIALOG_STYLE_INPUT                             = 1,
DIALOG_STYLE_LIST                              = 2,
DIALOG_STYLE_PASSWORD                          = 3,
DIALOG_STYLE_TABLIST                           = 4,
DIALOG_STYLE_TABLIST_HEADERS                   = 5,

-- SAMP Cursor Modes
CMODE_DISABLED                                 = 0,
CMODE_LOCKKEYS_NOCURSOR                        = 1,
CMODE_LOCKCAMANDCONTROL                        = 2,
CMODE_LOCKCAM                                  = 3,
CMODE_LOCKCAM_NOCURSOR                         = 4,

-- Primitive Types
D3DPT_POINTLIST                                = 1,
D3DPT_LINELIST                                 = 2,
D3DPT_LINESTRIP                                = 3,
D3DPT_TRIANGLELIST                             = 4,
D3DPT_TRIANGLESTRIP                            = 5,
D3DPT_TRIANGLEFAN                              = 6
}

-- Copy table 'sampfuncs' to a global scope
for k, v in pairs(sampfuncs) do
	_G[k] = v
end

return sampfuncs
end
package.preload["samp.synchronization"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local mod =
{
	MODULEINFO = {
		name = 'samp.synchronization',
		version = 2
	}
}
local ffi = require 'ffi'

ffi.cdef[[
#pragma pack(push, 1)

typedef struct VectorXYZ {
	float x, y, z;
} VectorXYZ;

typedef struct SampKeys {
	uint8_t primaryFire : 1;
	uint8_t horn_crouch : 1;
	uint8_t secondaryFire_shoot : 1;
	uint8_t accel_zoomOut : 1;
	uint8_t enterExitCar : 1;
	uint8_t decel_jump : 1;
	uint8_t circleRight : 1;
	uint8_t aim : 1;
	uint8_t circleLeft : 1;
	uint8_t landingGear_lookback : 1;
	uint8_t unknown_walkSlow : 1;
	uint8_t specialCtrlUp : 1;
	uint8_t specialCtrlDown : 1;
	uint8_t specialCtrlLeft : 1;
	uint8_t specialCtrlRight : 1;
	uint8_t _unknown : 1;
} SampKeys;

typedef struct PlayerSyncData {
	uint16_t leftRightKeys;
	uint16_t upDownKeys;
	union {
		uint16_t keysData;
		SampKeys keys;
	};
	VectorXYZ position;
	float     quaternion[4];
	uint8_t   health;
	uint8_t   armor;
	uint8_t   weapon : 6;
	uint8_t   specialKey : 2;
	uint8_t   specialAction;
	VectorXYZ moveSpeed;
	VectorXYZ surfingOffsets;
	uint16_t  surfingVehicleId;
	union {
		struct {
			uint16_t id;
			uint8_t  frameDelta;
			union {
				struct {
					bool    loop : 1;
					bool    lockX : 1;
					bool    lockY : 1;
					bool    freeze : 1;
					uint8_t time : 2;
					uint8_t _unused : 1;
					bool    regular : 1;
				};
				uint8_t value;
			} flags;
		} animation;
		struct {
			uint16_t  animationId;
			uint16_t  animationFlags;
		};
	};
} PlayerSyncData;

typedef struct VehicleSyncData {
	uint16_t vehicleId;
	uint16_t leftRightKeys;
	uint16_t upDownKeys;
	union {
		uint16_t keysData;
		SampKeys keys;
	};
	float     quaternion[4];
	VectorXYZ position;
	VectorXYZ moveSpeed;
	float     vehicleHealth;
	uint8_t   playerHealth;
	uint8_t   armor;
	uint8_t   currentWeapon : 6;
	uint8_t   specialKey : 2;
	uint8_t   siren;
	uint8_t   landingGearState;
	uint16_t  trailerId;
	union {
		float    bikeLean;
		float    trainSpeed;
		uint16_t hydraThrustAngle[2];
	};
} VehicleSyncData;

typedef struct PassengerSyncData {
	uint16_t vehicleId;
	uint8_t  seatId : 6;
	bool     driveBy : 1;
	bool     cuffed : 1;
	uint8_t  currentWeapon : 6;
	uint8_t  specialKey : 2;
	uint8_t  health;
	uint8_t  armor;
	uint16_t leftRightKeys;
	uint16_t upDownKeys;
	union {
		uint16_t keysData;
		SampKeys keys;
	};
	VectorXYZ position;
} PassengerSyncData;

typedef struct UnoccupiedSyncData {
	uint16_t  vehicleId;
	uint8_t   seatId;
	VectorXYZ roll;
	VectorXYZ direction;
	VectorXYZ position;
	VectorXYZ moveSpeed;
	VectorXYZ turnSpeed;
	float     vehicleHealth;
} UnoccupiedSyncData;

typedef struct TrailerSyncData {
	uint16_t  trailerId;
	VectorXYZ position;
	union {
		struct {
			float quaternion[4];
			VectorXYZ moveSpeed;
			VectorXYZ turnSpeed;
		};
		/* Invalid. Retained for backwards compatibility. */
		struct {
			VectorXYZ roll;
			VectorXYZ direction;
			VectorXYZ speed;
			uint32_t  unk;
		};
	};
} TrailerSyncData;

typedef struct SpectatorSyncData {
	uint16_t leftRightKeys;
	uint16_t upDownKeys;
	union {
		uint16_t keysData;
		SampKeys keys;
	};
	VectorXYZ position;
} SpectatorSyncData;

typedef struct BulletSyncData {
	uint8_t   targetType;
	uint16_t  targetId;
	VectorXYZ origin;
	VectorXYZ target;
	VectorXYZ center;
	uint8_t   weaponId;
} BulletSyncData;

typedef struct AimSyncData {
	uint8_t   camMode;
	VectorXYZ camFront;
	VectorXYZ camPos;
	float     aimZ;
	uint8_t   camExtZoom : 6;
	uint8_t   weaponState : 2;
	uint8_t   aspectRatio;
} AimSyncData;

#pragma pack(pop)
]]

assert(ffi.sizeof('VectorXYZ') == 12)
assert(ffi.sizeof('SampKeys') == 2)
assert(ffi.sizeof('PlayerSyncData') == 68)
assert(ffi.sizeof('VehicleSyncData') == 63)
assert(ffi.sizeof('PassengerSyncData') == 24)
assert(ffi.sizeof('UnoccupiedSyncData') == 67)
assert(ffi.sizeof('TrailerSyncData') == 54)
assert(ffi.sizeof('SpectatorSyncData') == 18)
assert(ffi.sizeof('BulletSyncData') == 40)
assert(ffi.sizeof('AimSyncData') == 31)

return mod

end
package.preload["samp.raknet"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local mod =
{
	MODULEINFO = {
		name = 'samp.raknet',
		version = 2
	}
}
require 'sampfuncs'

mod.RPC = {
	CLICKPLAYER                   = RPC_CLICKPLAYER,
	CLIENTJOIN                    = RPC_CLIENTJOIN,
	ENTERVEHICLE                  = RPC_ENTERVEHICLE,
	SCRIPTCASH                    = RPC_SCRIPTCASH,
	SERVERCOMMAND                 = RPC_SERVERCOMMAND,
	SPAWN                         = RPC_SPAWN,
	DEATH                         = RPC_DEATH,
	NPCJOIN                       = RPC_NPCJOIN,
	DIALOGRESPONSE                = RPC_DIALOGRESPONSE,
	CLICKTEXTDRAW                 = RPC_CLICKTEXTDRAW,
	SCMEVENT                      = RPC_SCMEVENT,
	WEAPONPICKUPDESTROY           = RPC_WEAPONPICKUPDESTROY,
	CHAT                          = RPC_CHAT,
	SRVNETSTATS                   = RPC_SRVNETSTATS,
	CLIENTCHECK                   = RPC_CLIENTCHECK,
	DAMAGEVEHICLE                 = RPC_DAMAGEVEHICLE,
	GIVETAKEDAMAGE                = RPC_GIVETAKEDAMAGE,
	EDITATTACHEDOBJECT            = RPC_EDITATTACHEDOBJECT,
	EDITOBJECT                    = RPC_EDITOBJECT,
	SETINTERIORID                 = RPC_SETINTERIORID,
	MAPMARKER                     = RPC_MAPMARKER,
	REQUESTCLASS                  = RPC_REQUESTCLASS,
	REQUESTSPAWN                  = RPC_REQUESTSPAWN,
	PICKEDUPPICKUP                = RPC_PICKEDUPPICKUP,
	MENUSELECT                    = RPC_MENUSELECT,
	VEHICLEDESTROYED              = RPC_VEHICLEDESTROYED,
	MENUQUIT                      = RPC_MENUQUIT,
	EXITVEHICLE                   = RPC_EXITVEHICLE,
	UPDATESCORESPINGSIPS          = RPC_UPDATESCORESPINGSIPS,
	CAMTARGETUPDATE = 168,
	GIVEACTORDAMAGE = 177,

	CONNECTIONREJECTED            = 130,
	SETPLAYERNAME                 = RPC_SCRSETPLAYERNAME,
	SETPLAYERPOS                  = RPC_SCRSETPLAYERPOS,
	SETPLAYERPOSFINDZ             = RPC_SCRSETPLAYERPOSFINDZ,
	SETPLAYERHEALTH               = RPC_SCRSETPLAYERHEALTH,
	TOGGLEPLAYERCONTROLLABLE      = RPC_SCRTOGGLEPLAYERCONTROLLABLE,
	PLAYSOUND                     = RPC_SCRPLAYSOUND,
	SETPLAYERWORLDBOUNDS          = RPC_SCRSETPLAYERWORLDBOUNDS,
	GIVEPLAYERMONEY               = RPC_SCRGIVEPLAYERMONEY,
	SETPLAYERFACINGANGLE          = RPC_SCRSETPLAYERFACINGANGLE,
	RESETPLAYERMONEY              = RPC_SCRRESETPLAYERMONEY,
	RESETPLAYERWEAPONS            = RPC_SCRRESETPLAYERWEAPONS,
	GIVEPLAYERWEAPON              = RPC_SCRGIVEPLAYERWEAPON,
	SETVEHICLEPARAMSEX            = RPC_SCRSETVEHICLEPARAMSEX,
	CANCELEDIT                    = RPC_SCRCANCELEDIT,
	SETPLAYERTIME                 = RPC_SCRSETPLAYERTIME,
	TOGGLECLOCK                   = RPC_SCRTOGGLECLOCK,
	WORLDPLAYERADD                = RPC_SCRWORLDPLAYERADD,
	SETPLAYERSHOPNAME             = RPC_SCRSETPLAYERSHOPNAME,
	SETPLAYERSKILLLEVEL           = RPC_SCRSETPLAYERSKILLLEVEL,
	SETPLAYERDRUNKLEVEL           = RPC_SCRSETPLAYERDRUNKLEVEL,
	CREATE3DTEXTLABEL             = RPC_SCRCREATE3DTEXTLABEL,
	DISABLECHECKPOINT             = RPC_SCRDISABLECHECKPOINT,
	SETRACECHECKPOINT             = RPC_SCRSETRACECHECKPOINT,
	DISABLERACECHECKPOINT         = RPC_SCRDISABLERACECHECKPOINT,
	GAMEMODERESTART               = RPC_SCRGAMEMODERESTART,
	PLAYAUDIOSTREAM               = RPC_SCRPLAYAUDIOSTREAM,
	STOPAUDIOSTREAM               = RPC_SCRSTOPAUDIOSTREAM,
	REMOVEBUILDINGFORPLAYER       = RPC_SCRREMOVEBUILDINGFORPLAYER,
	CREATEOBJECT                  = RPC_SCRCREATEOBJECT,
	SETOBJECTPOS                  = RPC_SCRSETOBJECTPOS,
	SETOBJECTROT                  = RPC_SCRSETOBJECTROT,
	DESTROYOBJECT                 = RPC_SCRDESTROYOBJECT,
	DEATHMESSAGE                  = RPC_SCRDEATHMESSAGE,
	SETPLAYERMAPICON              = RPC_SCRSETPLAYERMAPICON,
	REMOVEVEHICLECOMPONENT        = RPC_SCRREMOVEVEHICLECOMPONENT,
	CHATBUBBLE                    = RPC_SCRCHATBUBBLE,
	UPDATETIME                    = RPC_SCRSOMEUPDATE,
	SHOWDIALOG                    = RPC_SCRSHOWDIALOG,
	DESTROYPICKUP                 = RPC_SCRDESTROYPICKUP,
	LINKVEHICLETOINTERIOR         = RPC_SCRLINKVEHICLETOINTERIOR,
	SETPLAYERARMOUR               = RPC_SCRSETPLAYERARMOUR,
	SETPLAYERARMEDWEAPON          = RPC_SCRSETPLAYERARMEDWEAPON,
	SETSPAWNINFO                  = RPC_SCRSETSPAWNINFO,
	SETPLAYERTEAM                 = RPC_SCRSETPLAYERTEAM,
	PUTPLAYERINVEHICLE            = RPC_SCRPUTPLAYERINVEHICLE,
	REMOVEPLAYERFROMVEHICLE       = RPC_SCRREMOVEPLAYERFROMVEHICLE,
	SETPLAYERCOLOR                = RPC_SCRSETPLAYERCOLOR,
	DISPLAYGAMETEXT               = RPC_SCRDISPLAYGAMETEXT,
	FORCECLASSSELECTION           = RPC_SCRFORCECLASSSELECTION,
	ATTACHOBJECTTOPLAYER          = RPC_SCRATTACHOBJECTTOPLAYER,
	INITMENU                      = RPC_SCRINITMENU,
	SHOWMENU                      = RPC_SCRSHOWMENU,
	HIDEMENU                      = RPC_SCRHIDEMENU,
	CREATEEXPLOSION               = RPC_SCRCREATEEXPLOSION,
	SHOWPLAYERNAMETAGFORPLAYER    = RPC_SCRSHOWPLAYERNAMETAGFORPLAYER,
	ATTACHCAMERATOOBJECT          = RPC_SCRATTACHCAMERATOOBJECT,
	INTERPOLATECAMERA             = RPC_SCRINTERPOLATECAMERA,
	SETOBJECTMATERIAL             = RPC_SCRSETOBJECTMATERIAL,
	GANGZONESTOPFLASH             = RPC_SCRGANGZONESTOPFLASH,
	APPLYANIMATION                = RPC_SCRAPPLYANIMATION,
	CLEARANIMATIONS               = RPC_SCRCLEARANIMATIONS,
	SETPLAYERSPECIALACTION        = RPC_SCRSETPLAYERSPECIALACTION,
	SETPLAYERFIGHTINGSTYLE        = RPC_SCRSETPLAYERFIGHTINGSTYLE,
	SETPLAYERVELOCITY             = RPC_SCRSETPLAYERVELOCITY,
	SETVEHICLEVELOCITY            = RPC_SCRSETVEHICLEVELOCITY,
	CLIENTMESSAGE                 = RPC_SCRCLIENTMESSAGE,
	SETWORLDTIME                  = RPC_SCRSETWORLDTIME,
	CREATEPICKUP                  = RPC_SCRCREATEPICKUP,
	MOVEOBJECT                    = RPC_SCRMOVEOBJECT,
	ENABLESTUNTBONUSFORPLAYER     = RPC_SCRENABLESTUNTBONUSFORPLAYER,
	TEXTDRAWSETSTRING             = RPC_SCRTEXTDRAWSETSTRING,
	SETCHECKPOINT                 = RPC_SCRSETCHECKPOINT,
	GANGZONECREATE                = RPC_SCRGANGZONECREATE,
	PLAYCRIMEREPORT               = RPC_SCRPLAYCRIMEREPORT,
	SETPLAYERATTACHEDOBJECT       = RPC_SCRSETPLAYERATTACHEDOBJECT,
	GANGZONEDESTROY               = RPC_SCRGANGZONEDESTROY,
	GANGZONEFLASH                 = RPC_SCRGANGZONEFLASH,
	STOPOBJECT                    = RPC_SCRSTOPOBJECT,
	SETNUMBERPLATE                = RPC_SCRSETNUMBERPLATE,
	TOGGLEPLAYERSPECTATING        = RPC_SCRTOGGLEPLAYERSPECTATING,
	PLAYERSPECTATEPLAYER          = RPC_SCRPLAYERSPECTATEPLAYER,
	PLAYERSPECTATEVEHICLE         = RPC_SCRPLAYERSPECTATEVEHICLE,
	SETPLAYERWANTEDLEVEL          = RPC_SCRSETPLAYERWANTEDLEVEL,
	SHOWTEXTDRAW                  = RPC_SCRSHOWTEXTDRAW,
	TEXTDRAWHIDEFORPLAYER         = RPC_SCRTEXTDRAWHIDEFORPLAYER,
	SERVERJOIN                    = RPC_SCRSERVERJOIN,
	SERVERQUIT                    = RPC_SCRSERVERQUIT,
	INITGAME                      = RPC_SCRINITGAME,
	REMOVEPLAYERMAPICON           = RPC_SCRREMOVEPLAYERMAPICON,
	SETPLAYERAMMO                 = RPC_SCRSETPLAYERAMMO,
	SETGRAVITY                    = RPC_SCRSETGRAVITY,
	SETVEHICLEHEALTH              = RPC_SCRSETVEHICLEHEALTH,
	ATTACHTRAILERTOVEHICLE        = RPC_SCRATTACHTRAILERTOVEHICLE,
	DETACHTRAILERFROMVEHICLE      = RPC_SCRDETACHTRAILERFROMVEHICLE,
	SETWEATHER                    = RPC_SCRSETWEATHER,
	SETPLAYERSKIN                 = RPC_SCRSETPLAYERSKIN,
	SETPLAYERINTERIOR             = RPC_SCRSETPLAYERINTERIOR,
	SETPLAYERCAMERAPOS            = RPC_SCRSETPLAYERCAMERAPOS,
	SETPLAYERCAMERALOOKAT         = RPC_SCRSETPLAYERCAMERALOOKAT,
	SETVEHICLEPOS                 = RPC_SCRSETVEHICLEPOS,
	SETVEHICLEZANGLE              = RPC_SCRSETVEHICLEZANGLE,
	SETVEHICLEPARAMSFORPLAYER     = RPC_SCRSETVEHICLEPARAMSFORPLAYER,
	SETCAMERABEHINDPLAYER         = RPC_SCRSETCAMERABEHINDPLAYER,
	WORLDPLAYERREMOVE             = RPC_SCRWORLDPLAYERREMOVE,
	WORLDVEHICLEADD               = RPC_SCRWORLDVEHICLEADD,
	WORLDVEHICLEREMOVE            = RPC_SCRWORLDVEHICLEREMOVE,
	WORLDPLAYERDEATH              = RPC_SCRWORLDPLAYERDEATH,
	CREATEACTOR                   = 171,
	DESTROYACTOR = 172,
	DESTROY3DTEXTLABEL = 58,
	DESTROYWEAPONPICKUP = 151,
	TOGGLECAMERATARGET = 170,
	SELECTOBJECT = 27,
	DISABLEVEHICLECOLLISIONS = 167,
	TOGGLEWIDESCREEN = 111,
	SETVEHICLETIRES = 98,
	SETPLAYERDRUNKVISUALS = 92,
	SETPLAYERDRUNKHANDLING = 150,
	APPLYACTORANIMATION = 173,
	CLEARACTORANIMATION = 174,
	SETACTORROTATION = 175,
	SETACTORPOSITION = 176,
	SETACTORHEALTH = 178,
	SETPLAYEROBJECTNOCAMCOL = 169,

	-- Invalid. Retained only for backward compatibility.
	ENTEREDITOBJECT = RPC_ENTEREDITOBJECT,
	UPDATE3DTEXTLABEL = RPC_SCRUPDATE3DTEXTLABEL,
}

mod.PACKET = {
	VEHICLE_SYNC                      = PACKET_VEHICLE_SYNC,
	RCON_COMMAND                      = PACKET_RCON_COMMAND,
	RCON_RESPONCE                     = PACKET_RCON_RESPONCE,
	AIM_SYNC                          = PACKET_AIM_SYNC,
	WEAPONS_UPDATE                    = PACKET_WEAPONS_UPDATE,
	STATS_UPDATE                      = PACKET_STATS_UPDATE,
	BULLET_SYNC                       = PACKET_BULLET_SYNC,
	PLAYER_SYNC                       = PACKET_PLAYER_SYNC,
	MARKERS_SYNC                      = PACKET_MARKERS_SYNC,
	UNOCCUPIED_SYNC                   = PACKET_UNOCCUPIED_SYNC,
	TRAILER_SYNC                      = PACKET_TRAILER_SYNC,
	PASSENGER_SYNC                    = PACKET_PASSENGER_SYNC,
	SPECTATOR_SYNC                    = PACKET_SPECTATOR_SYNC,

	INTERNAL_PING                     = PACKET_INTERNAL_PING,
	PING                              = PACKET_PING,
	PING_OPEN_CONNECTIONS             = PACKET_PING_OPEN_CONNECTIONS,
	CONNECTED_PONG                    = PACKET_CONNECTED_PONG,
	REQUEST_STATIC_DATA               = PACKET_REQUEST_STATIC_DATA,
	CONNECTION_REQUEST                = PACKET_CONNECTION_REQUEST,
	AUTHENTICATION                    = PACKET_AUTH_KEY,
	BROADCAST_PINGS                   = PACKET_BROADCAST_PINGS,
	SECURED_CONNECTION_RESPONSE       = PACKET_SECURED_CONNECTION_RESPONSE,
	SECURED_CONNECTION_CONFIRMATION   = PACKET_SECURED_CONNECTION_CONFIRMATION,
	RPC_MAPPING                       = PACKET_RPC_MAPPING,
	SET_RANDOM_NUMBER_SEED            = PACKET_SET_RANDOM_NUMBER_SEED,
	RPC                               = PACKET_RPC,
	RPC_REPLY                         = PACKET_RPC_REPLY,
	DETECT_LOST_CONNECTIONS           = PACKET_DETECT_LOST_CONNECTIONS,
	OPEN_CONNECTION_REQUEST           = PACKET_OPEN_CONNECTION_REQUEST,
	OPEN_CONNECTION_REPLY             = PACKET_OPEN_CONNECTION_REPLY,
	CONNECTION_COOKIE                 = PACKET_CONNECTION_COOKIE,
	RSA_PUBLIC_KEY_MISMATCH           = PACKET_RSA_PUBLIC_KEY_MISMATCH,
	CONNECTION_ATTEMPT_FAILED         = PACKET_CONNECTION_ATTEMPT_FAILED,
	NEW_INCOMING_CONNECTION           = PACKET_NEW_INCOMING_CONNECTION,
	NO_FREE_INCOMING_CONNECTIONS      = PACKET_NO_FREE_INCOMING_CONNECTIONS,
	DISCONNECTION_NOTIFICATION        = PACKET_DISCONNECTION_NOTIFICATION,
	CONNECTION_LOST                   = PACKET_CONNECTION_LOST,
	CONNECTION_REQUEST_ACCEPTED       = PACKET_CONNECTION_REQUEST_ACCEPTED,
	INITIALIZE_ENCRYPTION             = PACKET_INITIALIZE_ENCRYPTION,
	CONNECTION_BANNED                 = PACKET_CONNECTION_BANNED,
	INVALID_PASSWORD                  = PACKET_INVALID_PASSWORD,
	MODIFIED_PACKET                   = PACKET_MODIFIED_PACKET,
	PONG                              = PACKET_PONG,
	TIMESTAMP                         = PACKET_TIMESTAMP,
	RECEIVED_STATIC_DATA              = PACKET_RECEIVED_STATIC_DATA,
	REMOTE_DISCONNECTION_NOTIFICATION = PACKET_REMOTE_DISCONNECTION_NOTIFICATION,
	REMOTE_CONNECTION_LOST            = PACKET_REMOTE_CONNECTION_LOST,
	REMOTE_NEW_INCOMING_CONNECTION    = PACKET_REMOTE_NEW_INCOMING_CONNECTION,
	REMOTE_EXISTING_CONNECTION        = PACKET_REMOTE_EXISTING_CONNECTION,
	REMOTE_STATIC_DATA                = PACKET_REMOTE_STATIC_DATA,
	ADVERTISE_SYSTEM                  = PACKET_ADVERTISE_SYSTEM,

	AUTH_KEY                          = PACKET_AUTH_KEY,
}

return mod

end
package.preload["samp.events.bitstream_io"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local mod = {}
local vector3d = require 'vector3d'
local ffi = require 'ffi'

local function bitstream_read_fixed_string(bs, size)
	local buf = ffi.new('uint8_t[?]', size + 1)
	bs:readBuffer(tonumber(ffi.cast('intptr_t', buf)), size)
	buf[size] = 0
	-- Length is not specified to throw off trailing zeros.
	return ffi.string(buf)
end

local function bitstream_write_fixed_string(bs, str, size)
	local buf = ffi.new('uint8_t[?]', size, string.sub(str, 1, size))
	bs:writeBuffer(tonumber(ffi.cast('intptr_t', buf)), size)
end

mod.bool = {
	read = function(bs) return bs:readBool() end,
	write = function(bs, value) return bs:writeBool(value) end
}

mod.uint8 = {
	read = function(bs) return bs:readUInt8() end,
	write = function(bs, value) return bs:writeUInt8(value) end
}

mod.uint16 = {
	read = function(bs) return bs:readUInt16() end,
	write = function(bs, value) return bs:writeUInt16(value) end
}

mod.uint32 = {
	read = function(bs) return bs:readUInt32() end,
	write = function(bs, value) return bs:writeUInt32(value) end
}

mod.int8 = {
	read = function(bs) return bs:readInt8() end,
	write = function(bs, value) return bs:writeInt8(value) end
}

mod.int16 = {
	read = function(bs) return bs:readInt16() end,
	write = function(bs, value) return bs:writeInt16(value) end
}

mod.int32 = {
	read = function(bs) return bs:readInt32() end,
	write = function(bs, value) return bs:writeInt32(value) end
}

mod.float = {
	read = function(bs) return bs:readFloat() end,
	write = function(bs, value) return bs:writeFloat(value) end
}

mod.string8 = {
	read = function(bs)
		local len =  bs:readUInt8()
		if len <= 0 then return '' end
		return bs:readString(len)
	end,
	write = function(bs, value)
		bs:writeUInt8(#value)
		bs:writeString(value)
	end
}

mod.string16 = {
	read = function(bs)
		local len = bs:readUInt16()
		if len <= 0 then return '' end
		return bs:readString(len)
	end,
	write = function(bs, value)
		bs:writeUInt16(#value)
		bs:writeString(value)
	end
}

mod.string32 = {
	read = function(bs)
		local len = bs:readUInt32()
		if len <= 0 then return '' end
		return bs:readString(len)
	end,
	write = function(bs, value)
		bs:writeUInt32(#value)
		bs:writeString(value)
	end
}

mod.bool8 = {
	read = function(bs)
		return bs:readUInt8() ~= 0
	end,
	write = function(bs, value)
		bs:writeUInt8(value == true and 1 or 0)
	end
}

mod.bool32 = {
	read = function(bs)
		return bs:readUInt32() ~= 0
	end,
	write = function(bs, value)
		bs:writeUInt32(value == true and 1 or 0)
	end
}

mod.int1 = {
	read = function(bs)
		if bs:readBool() == true then return 1 else return 0 end
	end,
	write = function(bs, value)
		bs:writeBool(value ~= 0 and true or false)
	end
}

mod.fixedString32 = {
	read = function(bs)
		return bitstream_read_fixed_string(bs, 32)
	end,
	write = function(bs, value)
		bitstream_write_fixed_string(bs, value, 32)
	end
}

mod.string256 = mod.fixedString32

mod.encodedString2048 = {
	read = function(bs) return bs:readEncoded(2048) end,
	write = function(bs, value) bs:writeEncoded(value) end
}

mod.encodedString4096 = {
	read = function(bs) return bs:readEncoded(4096) end,
	write = function(bs, value) bs:writeEncoded(value) end
}

mod.compressedFloat = {
	read = function(bs)
		return bs:readUInt16() / 32767.5 - 1
	end,
	write = function(bs, value)
		if value < -1 then
			value = -1
		elseif value > 1 then
			value = 1
		end
		bs:writeUInt16((value + 1) * 32767.5)
	end
}

mod.compressedVector = {
	read = function(bs)
		local magnitude = bs:readFloat()
		if magnitude ~= 0 then
			return vector3d(mod.compressedFloat.read(bs) * magnitude, mod.compressedFloat.read(bs) * magnitude, mod.compressedFloat.read(bs) * magnitude)
		else
			return vector3d(0, 0, 0)
		end
	end,
	write = function(bs, data)
		local x, y, z = data.x, data.y, data.z
		local magnitude = math.sqrt(x * x + y * y + z * z)
		bs:writeFloat(magnitude)
		if magnitude > 0 then
			mod.compressedFloat.write(bs, x / magnitude)
			mod.compressedFloat.write(bs, y / magnitude)
			mod.compressedFloat.write(bs, z / magnitude)
		end
	end
}

mod.normQuat = {
	read = function(bs)
		local cwNeg, cxNeg, cyNeg, czNeg = bs:readBool(), bs:readBool(), bs:readBool(), bs:readBool()
		local cx, cy, cz = bs:readUInt16(), bs:readUInt16(), bs:readUInt16()
		local x = cx / 65535
		local y = cy / 65535
		local z = cz / 65535
		if cxNeg then x = -x end
		if cyNeg then y = -y end
		if czNeg then z = -z end
		local diff = 1 - x * x - y * y - z * z
		if diff < 0 then diff = 0 end
		local w = math.sqrt(diff)
		if cwNeg then w = -w end
		return {w, x, y, z}
	end,
	write = function(bs, value)
		local w, x, y, z = value[1], value[2], value[3], value[4]
		bs:writeBool(w < 0)
		bs:writeBool(x < 0)
		bs:writeBool(y < 0)
		bs:writeBool(z < 0)
		bs:writeUInt16(math.abs(x) * 65535)
		bs:writeUInt16(math.abs(y) * 65535)
		bs:writeUInt16(math.abs(z) * 65535)
		-- w is calculated on the target
	end
}

mod.vector3d = {
	read = function(bs)
		local x, y, z =
			bs:readFloat(),
			bs:readFloat(),
			bs:readFloat()
		return vector3d(x, y, z)
	end,
	write = function(bs, value)
		bs:writeFloat(value.x)
		bs:writeFloat(value.y)
		bs:writeFloat(value.z)
	end
}

mod.vector2d = {
	read = function(bs)
		local x = bs:readFloat()
		local y = bs:readFloat()
		return {x = x, y = y}
	end,
	write = function(bs, value)
		bs:writeFloat(value.x)
		bs:writeFloat(value.y)
	end
}

local function bitstream_io_interface(field)
	return setmetatable({}, {
		__index = function(t, index)
			return mod[index][field]
		end
	})
end

mod.bs_read = bitstream_io_interface('read')
mod.bs_write = bitstream_io_interface('write')

return mod

end
package.preload["samp.events.utils"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local ffi = require 'ffi'
local utils = {}

function utils.decompress_health_and_armor(hpAp)
	local hp = math.min(bit.rshift(hpAp, 4) * 7, 100)
	local armor = math.min(bit.band(hpAp, 0x0F) * 7, 100)
	return hp, armor
end

function utils.compress_health_and_armor(health, armor)
	local hp = health >= 100 and 0xF0 or bit.lshift(health / 7, 4)
	local ap = armor >= 100 and 0x0F or bit.band(armor / 7, 0x0F)
	return bit.bor(hp, ap)
end

function utils.create_sync_data(st)
	require 'samp.synchronization'
	return ffi.new(st)
end

function utils.read_sync_data(bs, st)
	local dataStruct = utils.create_sync_data(st)
	local ptr = tonumber(ffi.cast('intptr_t', ffi.cast('void*', dataStruct)))
	bs:readBuffer(ptr, ffi.sizeof(dataStruct))
	return dataStruct
end

function utils.write_sync_data(bs, st, ffiobj)
	require 'samp.synchronization'
	local ptr = tonumber(ffi.cast('intptr_t', ffi.cast('void*', ffiobj)))
	bs:writeBuffer(ptr, ffi.sizeof(st))
end

function utils.process_outcoming_sync_data(bs, st)
	local data = bs:getDataPtr() + 1
	require 'samp.synchronization'
	return {ffi.cast(st .. '*', data)}
end

return utils

end
package.preload["samp.events.handlers"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local bs_io = require 'samp.events.bitstream_io'
local utils = require 'samp.events.utils'
local bsread, bswrite = bs_io.bs_read, bs_io.bs_write
local handler = {}

--- onSendGiveDamage, onSendTakeDamage
function handler.rpc_send_give_take_damage_reader(bs)
	local take = bsread.bool(bs) -- 'true' is take damage
	local data = {
		bsread.uint16(bs), -- playerId
		bsread.float(bs), -- damage
		bsread.int32(bs), -- weapon
		bsread.int32(bs), -- bodypart
		take,
	}
	return (take and 'onSendTakeDamage' or 'onSendGiveDamage'), data
end

function handler.rpc_send_give_take_damage_writer(bs, data)
	bswrite.bool(bs, data[5]) -- give or take
	bswrite.uint16(bs, data[1]) -- playerId
	bswrite.float(bs, data[2]) -- damage
	bswrite.int32(bs, data[3]) -- weapon
	bswrite.int32(bs, data[4]) -- bodypart
end

--- onInitGame
function handler.rpc_init_game_reader(bs)
	local settings                 = {}
	settings.zoneNames             = bsread.bool(bs)
	settings.useCJWalk             = bsread.bool(bs)
	settings.allowWeapons          = bsread.bool(bs)
	settings.limitGlobalChatRadius = bsread.bool(bs)
	settings.globalChatRadius      = bsread.float(bs)
	settings.stuntBonus            = bsread.bool(bs)
	settings.nametagDrawDist       = bsread.float(bs)
	settings.disableEnterExits     = bsread.bool(bs)
	settings.nametagLOS            = bsread.bool(bs)
	settings.tirePopping           = bsread.bool(bs)
	settings.classesAvailable      = bsread.int32(bs)
	local playerId                 = bsread.uint16(bs)
	settings.showPlayerTags        = bsread.bool(bs)
	settings.playerMarkersMode     = bsread.int32(bs)
	settings.worldTime             = bsread.uint8(bs)
	settings.worldWeather          = bsread.uint8(bs)
	settings.gravity               = bsread.float(bs)
	settings.lanMode               = bsread.bool(bs)
	settings.deathMoneyDrop        = bsread.int32(bs)
	settings.instagib              = bsread.bool(bs)
	settings.normalOnfootSendrate  = bsread.int32(bs)
	settings.normalIncarSendrate   = bsread.int32(bs)
	settings.normalFiringSendrate  = bsread.int32(bs)
	settings.sendMultiplier        = bsread.int32(bs)
	settings.lagCompMode           = bsread.int32(bs)
	local hostName                 = bsread.string8(bs)
	local vehicleModels = {}
	for i = 0, 212 - 1 do
		vehicleModels[i] = bsread.uint8(bs)
	end
	settings.vehicleFriendlyFire = bsread.bool32(bs)
	return {playerId, hostName, settings, vehicleModels, settings.vehicleFriendlyFire}
end

function handler.rpc_init_game_writer(bs, data)
	local settings = data[3]
	local vehicleModels = data[4]
	bswrite.bool(bs, settings.zoneNames)
	bswrite.bool(bs, settings.useCJWalk)
	bswrite.bool(bs, settings.allowWeapons)
	bswrite.bool(bs, settings.limitGlobalChatRadius)
	bswrite.float(bs, settings.globalChatRadius)
	bswrite.bool(bs, settings.stuntBonus)
	bswrite.float(bs, settings.nametagDrawDist)
	bswrite.bool(bs, settings.disableEnterExits)
	bswrite.bool(bs, settings.nametagLOS)
	bswrite.bool(bs, settings.tirePopping)
	bswrite.int32(bs, settings.classesAvailable)
	bswrite.uint16(bs, data[1]) -- playerId
	bswrite.bool(bs, settings.showPlayerTags)
	bswrite.int32(bs, settings.playerMarkersMode)
	bswrite.uint8(bs, settings.worldTime)
	bswrite.uint8(bs, settings.worldWeather)
	bswrite.float(bs, settings.gravity)
	bswrite.bool(bs, settings.lanMode)
	bswrite.int32(bs, settings.deathMoneyDrop)
	bswrite.bool(bs, settings.instagib)
	bswrite.int32(bs, settings.normalOnfootSendrate)
	bswrite.int32(bs, settings.normalIncarSendrate)
	bswrite.int32(bs, settings.normalFiringSendrate)
	bswrite.int32(bs, settings.sendMultiplier)
	bswrite.int32(bs, settings.lagCompMode)
	bswrite.string8(bs, data[2]) -- hostName
	for i = 1, 212 do
		bswrite.uint8(bs, vehicleModels[i])
	end
	bswrite.bool32(bs, settings.vehicleFriendlyFire)
end

--- onInitMenu
function handler.rpc_init_menu_reader(bs)
	local colWidth2
	local rows = {}
	local columns = {}
	local readColumn = function(width)
		local title = bsread.fixedString32(bs)
		local rowCount = bsread.uint8(bs)
		local column = {title = title, width = width, text = {}}
		for i = 1, rowCount do
			column.text[i] = bsread.fixedString32(bs)
		end
		return column
	end
	local menuId = bsread.uint8(bs)
	local twoColumns = bsread.bool32(bs)
	local menuTitle = bsread.fixedString32(bs)
	local x = bsread.float(bs)
	local y = bsread.float(bs)
	local colWidth1 = bsread.float(bs)
	if twoColumns then
		colWidth2 = bsread.float(bs)
	end
	local menu = bsread.bool32(bs)
	for i = 1, 12 do
		rows[i] = bsread.int32(bs)
	end
	columns[1] = readColumn(colWidth1)
	if twoColumns then
		columns[2] = readColumn(colWidth2)
	end
	return {menuId, menuTitle, x, y, twoColumns, columns, rows, menu}
end

function handler.rpc_init_menu_writer(bs, data)
	local columns = data[6]
	bswrite.uint8(bs, data[1])      -- menuId
	bswrite.bool32(bs, data[5])    -- twoColumns
	bswrite.fixedString32(bs, data[2]) -- title
	bswrite.float(bs, data[3])     -- x
	bswrite.float(bs, data[4])     -- y
	-- columns width
	bswrite.float(bs, columns[1].width)
	if data[5] then
		bswrite.float(bs, columns[2].width)
	end
	bswrite.bool32(bs, data[8]) -- menu
	 -- rows
	for i = 1, 12 do
		bswrite.int32(bs, data[7][i])
	end
	-- columns
	for i = 1, (data[5] and 2 or 1) do
		bswrite.fixedString32(bs, columns[i].title)
		bswrite.uint8(bs, #columns[i].text)
		for r, t in ipairs(columns[i].text) do
			bswrite.fixedString32(bs, t)
		end
	end
end

--- onMarkersSync
function handler.packet_markers_sync_reader(bs)
	local markers = {}
	local players = bsread.int32(bs)
	for i = 1, players do
		local playerId = bsread.uint16(bs)
		local active = bsread.bool(bs)
		if active then
			local vector3d = require 'vector3d'
			local x, y, z = bsread.int16(bs), bsread.int16(bs), bsread.int16(bs)
			table.insert(markers, {playerId = playerId, active = true, coords = vector3d(x, y, z)})
		else
			table.insert(markers, {playerId = playerId, active = false})
		end
	end
	return {markers}
end

function handler.packet_markers_sync_writer(bs, data)
	bswrite.int32(bs, #data)
	for i = 1, #data do
		local it = data[i]
		bswrite.uint16(bs, it.playerId)
		bswrite.bool(bs, it.active)
		if it.active then
			bswrite.uint16(bs, it.coords.x)
			bswrite.uint16(bs, it.coords.y)
			bswrite.uint16(bs, it.coords.z)
		end
	end
end

--- onPlayerSync
function handler.packet_player_sync_reader(bs)
	local has_value = bsread.bool
	local data = {}
	local playerId = bsread.uint16(bs)
	if has_value(bs) then data.leftRightKeys = bsread.uint16(bs) end
	if has_value(bs) then data.upDownKeys = bsread.uint16(bs) end
	data.keysData = bsread.uint16(bs)
	data.position = bsread.vector3d(bs)
	data.quaternion = bsread.normQuat(bs)
	data.health, data.armor = utils.decompress_health_and_armor(bsread.uint8(bs))
	data.weapon = bsread.uint8(bs)
	data.specialAction = bsread.uint8(bs)
	data.moveSpeed = bsread.compressedVector(bs)
	if has_value(bs) then
		data.surfingVehicleId = bsread.uint16(bs)
		data.surfingOffsets = bsread.vector3d(bs)
	end
	if has_value(bs) then
		data.animationId = bsread.uint16(bs)
		data.animationFlags = bsread.uint16(bs)
	end
	return {playerId, data}
end

function handler.packet_player_sync_writer(bs, data)
	local playerId = data[1]
	local data = data[2]
	bswrite.uint16(bs, playerId)
	bswrite.bool(bs, data.leftRightKeys ~= nil)
	if data.leftRightKeys then bswrite.uint16(bs, data.leftRightKeys) end
	bswrite.bool(bs, data.upDownKeys ~= nil)
	if data.upDownKeys then bswrite.uint16(bs, data.upDownKeys) end
	bswrite.uint16(bs, data.keysData)
	bswrite.vector3d(bs, data.position)
	bswrite.normQuat(bs, data.quaternion)
	bswrite.uint8(bs, utils.compress_health_and_armor(data.health, data.armor))
	bswrite.uint8(bs, data.weapon)
	bswrite.uint8(bs, data.specialAction)
	bswrite.compressedVector(bs, data.moveSpeed)
	bswrite.bool(bs, data.surfingVehicleId ~= nil)
	if data.surfingVehicleId then
		bswrite.uint16(bs, data.surfingVehicleId)
		bswrite.vector3d(bs, data.surfingOffsets)
	end
	bswrite.bool(bs, data.animationId ~= nil)
	if data.animationId then
		bswrite.uint16(bs, data.animationId)
		bswrite.uint16(bs, data.animationFlags)
	end
end

--- onVehicleSync
function handler.packet_vehicle_sync_reader(bs)
	local data = {}
	local playerId = bsread.uint16(bs)
	local vehicleId = bsread.uint16(bs)
	data.leftRightKeys = bsread.uint16(bs)
	data.upDownKeys = bsread.uint16(bs)
	data.keysData = bsread.uint16(bs)
	data.quaternion = bsread.normQuat(bs)
	data.position = bsread.vector3d(bs)
	data.moveSpeed = bsread.compressedVector(bs)
	data.vehicleHealth = bsread.uint16(bs)
	data.playerHealth, data.armor = utils.decompress_health_and_armor(bsread.uint8(bs))
	data.currentWeapon = bsread.uint8(bs)
	data.siren = bsread.bool(bs)
	data.landingGear = bsread.bool(bs)
	if bsread.bool(bs) then
		data.trainSpeed = bsread.int32(bs)
	end
	if bsread.bool(bs) then
		data.trailerId = bsread.uint16(bs)
	end
	return {playerId, vehicleId, data}
end

function handler.packet_vehicle_sync_writer(bs, data)
	local playerId = data[1]
	local vehicleId = data[2]
	local data = data[3]
	bswrite.uint16(bs, playerId)
	bswrite.uint16(bs, vehicleId)
	bswrite.uint16(bs, data.leftRightKeys)
	bswrite.uint16(bs, data.upDownKeys)
	bswrite.uint16(bs, data.keysData)
	bswrite.normQuat(bs, data.quaternion)
	bswrite.vector3d(bs, data.position)
	bswrite.compressedVector(bs, data.moveSpeed)
	bswrite.uint16(bs, data.vehicleHealth)
	bswrite.uint8(bs, utils.compress_health_and_armor(data.playerHealth, data.armor))
	bswrite.uint8(bs, data.currentWeapon)
	bswrite.bool(bs, data.siren)
	bswrite.bool(bs, data.landingGear)
	bswrite.bool(bs, data.trainSpeed ~= nil)
	if data.trainSpeed ~= nil then
		bswrite.int32(bs, data.trainSpeed)
	end
	bswrite.bool(bs, data.trailerId ~= nil)
	if data.trailerId ~= nil then
		bswrite.uint16(bs, data.trailerId)
	end
end

--- onVehicleStreamIn
function handler.rpc_vehicle_stream_in_reader(bs)
	local data = {modSlots = {}}
	local vehicleId = bsread.uint16(bs)
	data.type = bsread.int32(bs)
	data.position = bsread.vector3d(bs)
	data.rotation = bsread.float(bs)
	data.bodyColor1 = bsread.uint8(bs)
	data.bodyColor2 = bsread.uint8(bs)
	data.health = bsread.float(bs)
	data.interiorId = bsread.uint8(bs)
	data.doorDamageStatus = bsread.int32(bs)
	data.panelDamageStatus = bsread.int32(bs)
	data.lightDamageStatus = bsread.uint8(bs)
	data.tireDamageStatus = bsread.uint8(bs)
	data.addSiren = bsread.uint8(bs)
	for i = 1, 14 do
		data.modSlots[i] = bsread.uint8(bs)
	end
	data.paintJob = bsread.uint8(bs)
	data.interiorColor1 = bsread.int32(bs)
	data.interiorColor2 = bsread.int32(bs)
	return {vehicleId, data}
end

function handler.rpc_vehicle_stream_in_writer(bs, data)
	local vehicleId = data[1]
	local data = data[2]
	bswrite.uint16(bs, vehicleId)
	bswrite.int32(bs, data.type)
	bswrite.vector3d(bs, data.position)
	bswrite.float(bs, data.rotation)
	bswrite.uint8(bs, data.bodyColor1)
	bswrite.uint8(bs, data.bodyColor2)
	bswrite.float(bs, data.health)
	bswrite.uint8(bs, data.interiorId)
	bswrite.int32(bs, data.doorDamageStatus)
	bswrite.int32(bs, data.panelDamageStatus)
	bswrite.uint8(bs, data.lightDamageStatus)
	bswrite.uint8(bs, data.tireDamageStatus)
	bswrite.uint8(bs, data.addSiren)
	for i = 1, 14 do
		bswrite.uint8(bs, data.modSlots[i])
	end
	bswrite.uint8(bs, data.paintJob)
	bswrite.int32(bs, data.interiorColor1)
	bswrite.int32(bs, data.interiorColor2)
end

local MATERIAL_TYPE = {
	NONE = 0,
	TEXTURE = 1,
	TEXT = 2,
}

local function read_object_material(bs)
	local data = {}
	data.materialId = bsread.uint8(bs)
	data.modelId = bsread.uint16(bs)
	data.libraryName = bsread.string8(bs)
	data.textureName = bsread.string8(bs)
	data.color = bsread.int32(bs)
	data.type = MATERIAL_TYPE.TEXTURE
	return data
end

local function write_object_material(bs, data)
	bswrite.uint8(bs, data.type)
	bswrite.uint8(bs, data.materialId)
	bswrite.uint16(bs, data.modelId)
	bswrite.string8(bs, data.libraryName)
	bswrite.string8(bs, data.textureName)
	bswrite.int32(bs, data.color)
end

local function read_object_material_text(bs)
	local data = {}
	data.materialId = bsread.uint8(bs)
	data.materialSize = bsread.uint8(bs)
	data.fontName = bsread.string8(bs)
	data.fontSize = bsread.uint8(bs)
	data.bold = bsread.uint8(bs)
	data.fontColor = bsread.int32(bs)
	data.backGroundColor = bsread.int32(bs)
	data.align = bsread.uint8(bs)
	data.text = bsread.encodedString2048(bs)
	data.type = MATERIAL_TYPE.TEXT
	return data
end

local function write_object_material_text(bs, data)
	bswrite.uint8(bs, data.type)
	bswrite.uint8(bs, data.materialId)
	bswrite.uint8(bs, data.materialSize)
	bswrite.string8(bs, data.fontName)
	bswrite.uint8(bs, data.fontSize)
	bswrite.uint8(bs, data.bold)
	bswrite.int32(bs, data.fontColor)
	bswrite.int32(bs, data.backGroundColor)
	bswrite.uint8(bs, data.align)
	bswrite.encodedString2048(bs, data.text)
end

--- onSetObjectMaterial
function handler.rpc_set_object_material_reader(bs)
	local objectId = bsread.uint16(bs)
	local materialType = bsread.uint8(bs)
	local material
	if materialType == MATERIAL_TYPE.TEXTURE then
		material = read_object_material(bs)
	elseif materialType == MATERIAL_TYPE.TEXT then
		material = read_object_material_text(bs)
	end
	local ev = materialType == MATERIAL_TYPE.TEXTURE and 'onSetObjectMaterial' or 'onSetObjectMaterialText'
	return ev, {objectId, material}
end

function handler.rpc_set_object_material_writer(bs, data)
	local objectId = data[1]
	local mat = data[2]
	bswrite.uint16(bs, objectId)
	if mat.type == MATERIAL_TYPE.TEXTURE then
		write_object_material(bs, mat)
	elseif mat.type == MATERIAL_TYPE.TEXT then
		write_object_material_text(bs, mat)
	end
end

--- onCreateObject
function handler.rpc_create_object_reader(bs)
	local data = {materials = {}, materialText = {}}
	local objectId = bsread.uint16(bs)
	data.modelId = bsread.int32(bs)
	data.position = bsread.vector3d(bs)
	data.rotation = bsread.vector3d(bs)
	data.drawDistance = bsread.float(bs)
	data.noCameraCol = bsread.bool8(bs)
	data.attachToVehicleId = bsread.uint16(bs)
	data.attachToObjectId = bsread.uint16(bs)
	if data.attachToVehicleId ~= 0xFFFF or data.attachToObjectId ~= 0xFFFF then
		data.attachOffsets = bsread.vector3d(bs)
		data.attachRotation = bsread.vector3d(bs)
		data.syncRotation = bsread.bool8(bs)
	end
	data.texturesCount = bsread.uint8(bs)
	while bs:getNumberOfUnreadBits() >= 8 do
		local materialType = bsread.uint8(bs)
		if materialType == MATERIAL_TYPE.TEXTURE then
			table.insert(data.materials, read_object_material(bs))
		elseif materialType == MATERIAL_TYPE.TEXT then
			table.insert(data.materialText, read_object_material_text(bs))
		end
	end
	data.materials_text = data.materialText -- obsolete
	return {objectId, data}
end

function handler.rpc_create_object_writer(bs, data)
	local objectId = data[1]
	local data = data[2]
	bswrite.uint16(bs, objectId)
	bswrite.int32(bs, data.modelId)
	bswrite.vector3d(bs, data.position)
	bswrite.vector3d(bs, data.rotation)
	bswrite.float(bs, data.drawDistance)
	bswrite.bool8(bs, data.noCameraCol)
	bswrite.uint16(bs, data.attachToVehicleId)
	bswrite.uint16(bs, data.attachToObjectId)
	if data.attachToVehicleId ~= 0xFFFF or data.attachToObjectId ~= 0xFFFF then
		bswrite.vector3d(bs, data.attachOffsets)
		bswrite.vector3d(bs, data.attachRotation)
		bswrite.bool8(bs, data.syncRotation)
	end
	bswrite.uint8(bs, data.texturesCount)
	for _, it in ipairs(data.materials) do
		write_object_material(bs, it)
	end
	for _, it in ipairs(data.materialText) do
		write_object_material_text(bs, it)
	end
end

function handler.rpc_update_scores_and_pings_reader(bs)
	local data = {}
	for i = 1, bs:getNumberOfUnreadBytes() / 10 do
		local playerId = bsread.uint16(bs)
		local playerScore = bsread.int32(bs)
		local playerPing = bsread.int32(bs)
		data[playerId] = {score = playerScore, ping = playerPing}
	end
	return {data}
end

function handler.rpc_update_scores_and_pings_writer(bs, data)
	for id, info in pairs(data[1]) do
		bswrite.uint16(bs, id)
		bswrite.int32(bs, info.score)
		bswrite.int32(bs, info.ping)
	end
end

function handler.packet_weapons_update_reader(bs)
	local playerTarget = bsread.uint16(bs)
	local actorTarget = bsread.uint16(bs)
	local weapons = {}
	local count = bs:getNumberOfUnreadBits() / 32
	for i = 1, count do
		local slot = bsread.uint8(bs)
		local weapon = bsread.uint8(bs)
		local ammo = bsread.uint16(bs)
		weapons[i] = {slot = slot, weapon = weapon, ammo = ammo}
	end
	return {playerTarget, actorTarget, weapons}
end

function handler.packet_weapons_update_writer(bs, data)
	bswrite.uint16(bs, data[1])
	bswrite.uint16(bs, data[2])
	for i, weap in ipairs(data[3]) do
		bswrite.uint8(bs, weap.slot)
		bswrite.uint8(bs, weap.weapon)
		bswrite.uint16(bs, weap.ammo)
	end
end

return handler

end
package.preload["samp.events.extra_types"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local BitStreamIO = require 'samp.events.bitstream_io'
local utils = require 'samp.events.utils'

BitStreamIO.Int32Array3 = {
	read = function(bs)
		local arr = {}
		for i = 1, 3 do arr[i] = bs:readInt32() end
		return arr
	end,
	write = function(bs, value)
		for i = 1, 3 do bs:writeInt32(value[i]) end
	end
}

BitStreamIO.AimSyncData = {
	read = function(bs) return utils.read_sync_data(bs, 'AimSyncData')  end,
	write = function(bs, value) utils.write_sync_data(bs, 'AimSyncData', value) end
}

BitStreamIO.UnoccupiedSyncData = {
	read = function(bs) return utils.read_sync_data(bs, 'UnoccupiedSyncData')  end,
	write = function(bs, value) utils.write_sync_data(bs, 'UnoccupiedSyncData', value) end
}

BitStreamIO.PassengerSyncData = {
	read = function(bs) 	return utils.read_sync_data(bs, 'PassengerSyncData')  end,
	write = function(bs, value) utils.write_sync_data(bs, 'PassengerSyncData', value) end
}

BitStreamIO.BulletSyncData = {
	read = function(bs) return utils.read_sync_data(bs, 'BulletSyncData')  end,
	write = function(bs, value) utils.write_sync_data(bs, 'BulletSyncData', value) end
}

BitStreamIO.TrailerSyncData = {
	read = function(bs) return utils.read_sync_data(bs, 'TrailerSyncData')  end,
	write = function(bs, value) utils.write_sync_data(bs, 'TrailerSyncData', value) end
}

return BitStreamIO

end
package.preload["samp.events.core"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local MODULE = {
	MODULEINFO = {
		name = 'samp.events',
		version = 4
	},
	INTERFACE = {
		OUTCOMING_RPCS    = {},
		OUTCOMING_PACKETS = {},
		INCOMING_RPCS     = {},
		INCOMING_PACKETS  = {}
	},
	EXPORTS = {}
}

local BitStreamIO            = require 'samp.events.bitstream_io'
MODULE.INTERFACE.BitStreamIO = BitStreamIO


local function read_data(bs, dataType)
	if type(dataType) ~= 'table' then
		return BitStreamIO[dataType].read(bs)
	else -- process nested structures
		local values = {}
		for _, it in ipairs(dataType) do
			local name, t = next(it)
			values[name] = read_data(bs, t)
		end
		return values
	end
end

local function write_data(bs, dataType, value)
	if type(dataType) ~= 'table' then
		BitStreamIO[dataType].write(bs, value)
	else -- process nested structures
		for _, it in ipairs(dataType) do
			local name, t = next(it)
			write_data(bs, t, value[name])
		end
	end
end

local function process_event(bs, callback, struct, ignorebits)
	local args = {}
	if bs ~= 0 then
		if ignorebits then
			bs:ignoreBits(ignorebits)
		end
		if type(struct[2]) == 'function' then
			local r1, r2 = struct[2](bs) -- call custom reading function
			if type(callback) == 'table' and type(r1) == 'string' then
				callback = callback[r1]
				if callback then
					args = r2
				else
					return
				end
			else
				args = r1
			end
		else
			-- skip event name
			for i = 2, #struct do
				local _, t = next(struct[i]) -- type
				table.insert(args, read_data(bs, t))
			end
		end
	end
	local result = callback(unpack(args))
	if result == false then
		return false -- consume packet
	end
	if bs ~= 0 and type(result) == 'table' then
		bs:setWriteOffset(ignorebits or 0)
		if type(struct[3]) == 'function' then
			struct[3](bs, result) -- call custom writing function
		else
			assert(#struct - 1 == #result)
			for i = 2, #struct do
				local _, t = next(struct[i]) -- type
				write_data(bs, t, result[i - 1])
			end
		end
	end
end

local function process_packet(id, bs, event_table, ignorebits)
	local entry = event_table[id]
	if entry ~= nil then
		local key = entry[1]
		local callback = nil
		if type(key) == 'table' then
			for i, name in ipairs(key) do
				if type(MODULE[name]) == 'function' then
					if not callback then callback = {} end
					callback[name] = MODULE[name]
				end
			end
		elseif type(MODULE[key]) == 'function' then
			callback = MODULE[key]
		end
		if callback then
			return process_event(bs, callback, entry, ignorebits)
		end
	end
end


local interface = MODULE.INTERFACE
local function samp_on_send_rpc(id, bs)
	return process_packet(id, bs, interface.OUTCOMING_RPCS)
end

local function samp_on_send_packet(id, bs)
	return process_packet(id, bs, interface.OUTCOMING_PACKETS, 8)
end

local function samp_on_receive_rpc(id, bs)
	return process_packet(id, bs, interface.INCOMING_RPCS)
end

local function samp_on_receive_packet(id, bs)
	return process_packet(id, bs, interface.INCOMING_PACKETS, 8)
end

registerHandler("onSendRPC", samp_on_send_rpc)
registerHandler("onSendPacket", samp_on_send_packet)
registerHandler("onReceiveRPC", samp_on_receive_rpc)
registerHandler("onReceivePacket", samp_on_receive_packet)

return MODULE

end
package.preload["samp.events"] = function(...)
-- This file is part of the SAMP.Lua project.
-- Licensed under the MIT License.
-- Copyright (c) 2016, FYP @ BlastHack Team <blast.hk>
-- https://github.com/THE-FYP/SAMP.Lua

local raknet                                  = require 'samp.raknet'
local events                                  = require 'samp.events.core'
local utils                                   = require 'samp.events.utils'
local handler                                 = require 'samp.events.handlers'
                                                require 'samp.events.extra_types'
local RPC                                     = raknet.RPC
local PACKET                                  = raknet.PACKET
local OUTCOMING_RPCS                          = events.INTERFACE.OUTCOMING_RPCS
local OUTCOMING_PACKETS                       = events.INTERFACE.OUTCOMING_PACKETS
local INCOMING_RPCS                           = events.INTERFACE.INCOMING_RPCS
local INCOMING_PACKETS                        = events.INTERFACE.INCOMING_PACKETS

-- Outgoing rpcs
OUTCOMING_RPCS[RPC.ENTERVEHICLE]              = {'onSendEnterVehicle', {vehicleId = 'uint16'}, {passenger = 'bool8'}}
OUTCOMING_RPCS[RPC.CLICKPLAYER]               = {'onSendClickPlayer', {playerId = 'uint16'}, {source = 'uint8'}}
OUTCOMING_RPCS[RPC.CLIENTJOIN]                = {'onSendClientJoin', {version = 'int32'}, {mod = 'uint8'}, {nickname = 'string8'}, {challengeResponse = 'int32'}, {joinAuthKey = 'string8'}, {clientVer = 'string8'}, {challengeResponse2 = 'int32'}}
--OUTCOMING_RPCS[RPC.SELECTOBJECT]              = {'onSendSelectObject', {type = 'int32'}, {objectId = 'uint16'}, {model = 'int32'}, {position = 'vector3d'}}
OUTCOMING_RPCS[RPC.SELECTOBJECT]              = {'onSendEnterEditObject', {type = 'int32'}, {objectId = 'uint16'}, {model = 'int32'}, {position = 'vector3d'}}
OUTCOMING_RPCS[RPC.SERVERCOMMAND]             = {'onSendCommand', {command = 'string32'}}
OUTCOMING_RPCS[RPC.SPAWN]                     = {'onSendSpawn'}
OUTCOMING_RPCS[RPC.DEATH]                     = {'onSendDeathNotification', {reason = 'uint8'}, {killerId = 'uint16'}}
OUTCOMING_RPCS[RPC.DIALOGRESPONSE]            = {'onSendDialogResponse', {dialogId = 'uint16'}, {button = 'uint8'}, {listboxId = 'uint16'}, {input = 'string8'}}
OUTCOMING_RPCS[RPC.CLICKTEXTDRAW]             = {'onSendClickTextDraw', {textdrawId = 'uint16'}}
OUTCOMING_RPCS[RPC.SCMEVENT]                  = {'onSendVehicleTuningNotification', {vehicleId = 'int32'}, {param1 = 'int32'}, {param2 = 'int32'}, {event = 'int32'}}
OUTCOMING_RPCS[RPC.CHAT]                      = {'onSendChat', {message = 'string8'}}
OUTCOMING_RPCS[RPC.CLIENTCHECK]               = {'onSendClientCheckResponse', {requestType = 'uint8'}, {result1 = 'int32'}, {result2 = 'uint8'}}
OUTCOMING_RPCS[RPC.DAMAGEVEHICLE]             = {'onSendVehicleDamaged', {vehicleId = 'uint16'}, {panelDmg = 'int32'}, {doorDmg = 'int32'}, {lights = 'uint8'}, {tires = 'uint8'}}
OUTCOMING_RPCS[RPC.EDITATTACHEDOBJECT]        = {'onSendEditAttachedObject', {response = 'int32'}, {index = 'int32'}, {model = 'int32'}, {bone = 'int32'}, {position = 'vector3d'}, {rotation = 'vector3d'}, {scale = 'vector3d'}, {color1 = 'int32'}, {color2 = 'int32'}}
OUTCOMING_RPCS[RPC.EDITOBJECT]                = {'onSendEditObject', {playerObject = 'bool'}, {objectId = 'uint16'}, {response = 'int32'}, {position = 'vector3d'}, {rotation = 'vector3d'}}
OUTCOMING_RPCS[RPC.SETINTERIORID]             = {'onSendInteriorChangeNotification', {interior = 'uint8'}}
OUTCOMING_RPCS[RPC.MAPMARKER]                 = {'onSendMapMarker', {position = 'vector3d'}}
OUTCOMING_RPCS[RPC.REQUESTCLASS]              = {'onSendRequestClass', {classId = 'int32'}}
OUTCOMING_RPCS[RPC.REQUESTSPAWN]              = {'onSendRequestSpawn'}
OUTCOMING_RPCS[RPC.PICKEDUPPICKUP]            = {'onSendPickedUpPickup', {pickupId = 'int32'}}
OUTCOMING_RPCS[RPC.MENUSELECT]                = {'onSendMenuSelect', {row = 'uint8'}}
OUTCOMING_RPCS[RPC.VEHICLEDESTROYED]          = {'onSendVehicleDestroyed', {vehicleId = 'uint16'}}
OUTCOMING_RPCS[RPC.MENUQUIT]                  = {'onSendQuitMenu'}
OUTCOMING_RPCS[RPC.EXITVEHICLE]               = {'onSendExitVehicle', {vehicleId = 'uint16'}}
OUTCOMING_RPCS[RPC.UPDATESCORESPINGSIPS]      = {'onSendUpdateScoresAndPings'}
-- playerId = 'uint16', damage = 'float', weapon = 'int32', bodypart ='int32'
OUTCOMING_RPCS[RPC.GIVETAKEDAMAGE]            = {{'onSendGiveDamage', 'onSendTakeDamage'}, handler.rpc_send_give_take_damage_reader, handler.rpc_send_give_take_damage_writer}
OUTCOMING_RPCS[RPC.SCRIPTCASH] = {'onSendMoneyIncreaseNotification', {amount = 'int32'}, {increaseType = 'int32'}}
OUTCOMING_RPCS[RPC.NPCJOIN] = {'onSendNPCJoin', {version = 'int32'}, {mod = 'uint8'}, {nickname = 'string8'}, {challengeResponse = 'int32'}}
OUTCOMING_RPCS[RPC.SRVNETSTATS] = {'onSendServerStatisticsRequest'}
OUTCOMING_RPCS[RPC.WEAPONPICKUPDESTROY] = {'onSendPickedUpWeapon', {id = 'uint16'}}
OUTCOMING_RPCS[RPC.CAMTARGETUPDATE] = {'onSendCameraTargetUpdate', {objectId = 'uint16'}, {vehicleId = 'uint16'}, {playerId = 'uint16'}, {actorId = 'uint16'}}
OUTCOMING_RPCS[RPC.GIVEACTORDAMAGE] = {'onSendGiveActorDamage', {_unused = 'bool'}, {actorId = 'uint16'}, {damage = 'float'}, {weapon = 'int32'}, {bodypart ='int32'}}

-- Incoming rpcs
-- int playerId, string hostName, table settings, table vehicleModels, bool vehicleFriendlyFire
INCOMING_RPCS[RPC.INITGAME]                   = {'onInitGame', handler.rpc_init_game_reader, handler.rpc_init_game_writer}
INCOMING_RPCS[RPC.SERVERJOIN]                 = {'onPlayerJoin', {playerId = 'uint16'}, {color = 'int32'}, {isNpc = 'bool8'}, {nickname = 'string8'}}
INCOMING_RPCS[RPC.SERVERQUIT]                 = {'onPlayerQuit', {playerId = 'uint16'}, {reason = 'uint8'}}
INCOMING_RPCS[RPC.REQUESTCLASS]               = {'onRequestClassResponse', {canSpawn = 'bool8'}, {team = 'uint8'}, {skin = 'int32'}, {_unused = 'uint8'}, {positon = 'vector3d'}, {rotation = 'float'}, {weapons = 'Int32Array3'}, {ammo = 'Int32Array3'}}
INCOMING_RPCS[RPC.REQUESTSPAWN]               = {'onRequestSpawnResponse', {response = 'bool8'}}
INCOMING_RPCS[RPC.SETPLAYERNAME]              = {'onSetPlayerName', {playerId = 'uint16'}, {name = 'string8'}, {success = 'bool8'}}
INCOMING_RPCS[RPC.SETPLAYERPOS]               = {'onSetPlayerPos', {position = 'vector3d'}}
INCOMING_RPCS[RPC.SETPLAYERPOSFINDZ]          = {'onSetPlayerPosFindZ', {position = 'vector3d'}}
INCOMING_RPCS[RPC.SETPLAYERHEALTH]            = {'onSetPlayerHealth', {health = 'float'}}
INCOMING_RPCS[RPC.TOGGLEPLAYERCONTROLLABLE]   = {'onTogglePlayerControllable', {controllable = 'bool8'}}
INCOMING_RPCS[RPC.PLAYSOUND]                  = {'onPlaySound', {soundId = 'int32'}, {position = 'vector3d'}}
INCOMING_RPCS[RPC.SETPLAYERWORLDBOUNDS]       = {'onSetWorldBounds', {maxX = 'float'}, {minX = 'float'}, {maxY = 'float'}, {minY = 'float'}}
INCOMING_RPCS[RPC.GIVEPLAYERMONEY]            = {'onGivePlayerMoney', {money = 'int32'}}
INCOMING_RPCS[RPC.SETPLAYERFACINGANGLE]       = {'onSetPlayerFacingAngle', {angle = 'float'}}
INCOMING_RPCS[RPC.RESETPLAYERMONEY]           = {'onResetPlayerMoney'}
INCOMING_RPCS[RPC.RESETPLAYERWEAPONS]         = {'onResetPlayerWeapons'}
INCOMING_RPCS[RPC.GIVEPLAYERWEAPON]           = {'onGivePlayerWeapon', {weaponId = 'int32'}, {ammo = 'int32'}}
INCOMING_RPCS[RPC.CANCELEDIT]                 = {'onCancelEdit'}
INCOMING_RPCS[RPC.SETPLAYERTIME]              = {'onSetPlayerTime', {hour = 'uint8'}, {minute = 'uint8'}}
INCOMING_RPCS[RPC.TOGGLECLOCK]                = {'onSetToggleClock', {state = 'bool8'}}
INCOMING_RPCS[RPC.WORLDPLAYERADD]             = {'onPlayerStreamIn', {playerId = 'uint16'}, {team = 'uint8'}, {model = 'int32'}, {position = 'vector3d'}, {rotation = 'float'}, {color = 'int32'}, {fightingStyle = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERSHOPNAME]          = {'onSetShopName', {name = 'fixedString32'}}
INCOMING_RPCS[RPC.SETPLAYERSKILLLEVEL]        = {'onSetPlayerSkillLevel', {playerId = 'uint16'}, {skill = 'int32'}, {level = 'uint16'}}
INCOMING_RPCS[RPC.SETPLAYERDRUNKLEVEL]        = {'onSetPlayerDrunk', {drunkLevel = 'int32'}}
INCOMING_RPCS[RPC.CREATE3DTEXTLABEL]          = {'onCreate3DText', {id = 'uint16'}, {color = 'int32'}, {position = 'vector3d'}, {distance = 'float'}, {testLOS = 'bool8'}, {attachedPlayerId = 'uint16'}, {attachedVehicleId = 'uint16'}, {text = 'encodedString4096'}}
INCOMING_RPCS[RPC.DISABLECHECKPOINT]          = {'onDisableCheckpoint'}
INCOMING_RPCS[RPC.SETRACECHECKPOINT]          = {'onSetRaceCheckpoint', {type = 'uint8'}, {position = 'vector3d'}, {nextPosition = 'vector3d'}, {size = 'float'}}
INCOMING_RPCS[RPC.DISABLERACECHECKPOINT]      = {'onDisableRaceCheckpoint'}
INCOMING_RPCS[RPC.GAMEMODERESTART]            = {'onGamemodeRestart'}
INCOMING_RPCS[RPC.PLAYAUDIOSTREAM]            = {'onPlayAudioStream', {url = 'string8'}, {position = 'vector3d'}, {radius = 'float'}, {usePosition = 'bool8'}}
INCOMING_RPCS[RPC.STOPAUDIOSTREAM]            = {'onStopAudioStream'}
INCOMING_RPCS[RPC.REMOVEBUILDINGFORPLAYER]    = {'onRemoveBuilding', {modelId = 'int32'}, {position = 'vector3d'}, {radius = 'float'}}
INCOMING_RPCS[RPC.CREATEOBJECT]               = {'onCreateObject', handler.rpc_create_object_reader, handler.rpc_create_object_writer}
INCOMING_RPCS[RPC.SETOBJECTPOS]               = {'onSetObjectPosition', {objectId = 'uint16'}, {position = 'vector3d'}}
INCOMING_RPCS[RPC.SETOBJECTROT]               = {'onSetObjectRotation', {objectId = 'uint16'}, {rotation = 'vector3d'}}
INCOMING_RPCS[RPC.DESTROYOBJECT]              = {'onDestroyObject', {objectId = 'uint16'}}
INCOMING_RPCS[RPC.DEATHMESSAGE]               = {'onPlayerDeathNotification', {killerId = 'uint16'}, {killedId = 'uint16'}, {reason = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERMAPICON]           = {'onSetMapIcon', {iconId = 'uint8'}, {position = 'vector3d'}, {type = 'uint8'}, {color = 'int32'}, {style = 'uint8'}}
INCOMING_RPCS[RPC.REMOVEVEHICLECOMPONENT]     = {'onRemoveVehicleComponent', {vehicleId = 'uint16'}, {componentId = 'uint16'}}
INCOMING_RPCS[RPC.DESTROY3DTEXTLABEL]         = {'onRemove3DTextLabel', {textLabelId = 'uint16'}}
INCOMING_RPCS[RPC.CHATBUBBLE]                 = {'onPlayerChatBubble', {playerId = 'uint16'}, {color = 'int32'}, {distance = 'float'}, {duration = 'int32'}, {message = 'string8'}}
INCOMING_RPCS[RPC.UPDATETIME]                 = {'onUpdateGlobalTimer', {time = 'int32'}}
INCOMING_RPCS[RPC.SHOWDIALOG]                 = {'onShowDialog', {dialogId = 'uint16'}, {style = 'uint8'}, {title = 'string8'}, {button1 = 'string8'}, {button2 = 'string8'}, {text = 'encodedString4096'}}
INCOMING_RPCS[RPC.DESTROYPICKUP]              = {'onDestroyPickup', {id = 'int32'}}
INCOMING_RPCS[RPC.LINKVEHICLETOINTERIOR]      = {'onLinkVehicleToInterior', {vehicleId = 'uint16'}, {interiorId = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERARMOUR]            = {'onSetPlayerArmour', {armour = 'float'}}
INCOMING_RPCS[RPC.SETPLAYERARMEDWEAPON]       = {'onSetPlayerArmedWeapon', {weaponId = 'int32'}}
INCOMING_RPCS[RPC.SETSPAWNINFO]               = {'onSetSpawnInfo', {team = 'uint8'}, {skin = 'int32'}, {_unused = 'uint8'}, {position = 'vector3d'}, {rotation = 'float'}, {weapons = 'Int32Array3'}, {ammo = 'Int32Array3'}}
INCOMING_RPCS[RPC.SETPLAYERTEAM]              = {'onSetPlayerTeam', {playerId = 'uint16'}, {teamId = 'uint8'}}
INCOMING_RPCS[RPC.PUTPLAYERINVEHICLE]         = {'onPutPlayerInVehicle', {vehicleId = 'uint16'}, {seatId = 'uint8'}}
INCOMING_RPCS[RPC.REMOVEPLAYERFROMVEHICLE]    = {'onRemovePlayerFromVehicle'}
INCOMING_RPCS[RPC.SETPLAYERCOLOR]             = {'onSetPlayerColor', {playerId = 'uint16'}, {color = 'int32'}}
INCOMING_RPCS[RPC.DISPLAYGAMETEXT]            = {'onDisplayGameText', {style = 'int32'}, {time = 'int32'}, {text = 'string32'}}
INCOMING_RPCS[RPC.FORCECLASSSELECTION]        = {'onForceClassSelection'}
INCOMING_RPCS[RPC.ATTACHOBJECTTOPLAYER]       = {'onAttachObjectToPlayer', {objectId = 'uint16'}, {playerId = 'uint16'}, {offsets = 'vector3d'}, {rotation = 'vector3d'}}
-- menuId = 'uint8', menuTitle = 'fixedString32', x = 'float', y = 'float', twoColumns = 'bool32', columns = 'table', rows = 'table', menu = 'bool32'
INCOMING_RPCS[RPC.INITMENU]                   = {'onInitMenu', handler.rpc_init_menu_reader, handler.rpc_init_menu_writer}
INCOMING_RPCS[RPC.SHOWMENU]                   = {'onShowMenu', {menuId = 'uint8'}}
INCOMING_RPCS[RPC.HIDEMENU]                   = {'onHideMenu', {menuId = 'uint8'}}
INCOMING_RPCS[RPC.CREATEEXPLOSION]            = {'onCreateExplosion', {position = 'vector3d'}, {style = 'int32'}, {radius = 'float'}}
INCOMING_RPCS[RPC.SHOWPLAYERNAMETAGFORPLAYER] = {'onShowPlayerNameTag', {playerId = 'uint16'}, {show = 'bool8'}}
INCOMING_RPCS[RPC.ATTACHCAMERATOOBJECT]       = {'onAttachCameraToObject', {objectId = 'uint16'}}
INCOMING_RPCS[RPC.INTERPOLATECAMERA]          = {'onInterpolateCamera', {setPos = 'bool'}, {fromPos = 'vector3d'}, {destPos = 'vector3d'}, {time = 'int32'}, {mode = 'uint8'}}
INCOMING_RPCS[RPC.GANGZONESTOPFLASH]          = {'onGangZoneStopFlash', {zoneId = 'uint16'}}
INCOMING_RPCS[RPC.APPLYANIMATION]             = {'onApplyPlayerAnimation', {playerId = 'uint16'}, {animLib = 'string8'}, {animName = 'string8'}, {frameDelta = 'float'}, {loop = 'bool'}, {lockX = 'bool'}, {lockY = 'bool'}, {freeze = 'bool'}, {time = 'int32'}}
INCOMING_RPCS[RPC.CLEARANIMATIONS]            = {'onClearPlayerAnimation', {playerId = 'uint16'}}
INCOMING_RPCS[RPC.SETPLAYERSPECIALACTION]     = {'onSetPlayerSpecialAction', {actionId = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERFIGHTINGSTYLE]     = {'onSetPlayerFightingStyle', {playerId = 'uint16'}, {styleId = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERVELOCITY]          = {'onSetPlayerVelocity', {velocity = 'vector3d'}}
INCOMING_RPCS[RPC.SETVEHICLEVELOCITY]         = {'onSetVehicleVelocity', {turn = 'bool8'}, {velocity = 'vector3d'}}
INCOMING_RPCS[RPC.CLIENTMESSAGE]              = {'onServerMessage', {color = 'int32'}, {text = 'string32'}}
INCOMING_RPCS[RPC.SETWORLDTIME]               = {'onSetWorldTime', {hour = 'uint8'}}
INCOMING_RPCS[RPC.CREATEPICKUP]               = {'onCreatePickup', {id = 'int32'}, {model = 'int32'}, {pickupType = 'int32'}, {position = 'vector3d'}}
INCOMING_RPCS[RPC.MOVEOBJECT]                 = {'onMoveObject', {objectId = 'uint16'}, {fromPos = 'vector3d'}, {destPos = 'vector3d'}, {speed = 'float'}, {rotation = 'vector3d'}}
INCOMING_RPCS[RPC.ENABLESTUNTBONUSFORPLAYER]  = {'onEnableStuntBonus', {state = 'bool'}}
INCOMING_RPCS[RPC.TEXTDRAWSETSTRING]          = {'onTextDrawSetString', {id = 'uint16'}, {text = 'string16'}}
INCOMING_RPCS[RPC.SETCHECKPOINT]              = {'onSetCheckpoint', {position = 'vector3d'}, {radius = 'float'}}
INCOMING_RPCS[RPC.GANGZONECREATE]             = {'onCreateGangZone', {zoneId = 'uint16'}, {squareStart = 'vector2d'}, {squareEnd = 'vector2d'}, {color = 'int32'}}
INCOMING_RPCS[RPC.PLAYCRIMEREPORT]            = {'onPlayCrimeReport', {suspectId = 'uint16'}, {inVehicle = 'bool32'}, {vehicleModel = 'int32'}, {vehicleColor = 'int32'}, {crime = 'int32'}, {coordinates = 'vector3d'}}
INCOMING_RPCS[RPC.GANGZONEDESTROY]            = {'onGangZoneDestroy', {zoneId = 'uint16'}}
INCOMING_RPCS[RPC.GANGZONEFLASH]              = {'onGangZoneFlash', {zoneId = 'uint16'}, {color = 'int32'}}
INCOMING_RPCS[RPC.STOPOBJECT]                 = {'onStopObject', {objectId = 'uint16'}}
INCOMING_RPCS[RPC.SETNUMBERPLATE]             = {'onSetVehicleNumberPlate', {vehicleId = 'uint16'}, {text = 'string8'}}
INCOMING_RPCS[RPC.TOGGLEPLAYERSPECTATING]     = {'onTogglePlayerSpectating', {state = 'bool32'}}
INCOMING_RPCS[RPC.PLAYERSPECTATEPLAYER]       = {'onSpectatePlayer', {playerId = 'uint16'}, {camType = 'uint8'}}
INCOMING_RPCS[RPC.PLAYERSPECTATEVEHICLE]      = {'onSpectateVehicle', {vehicleId = 'uint16'}, {camType = 'uint8'}}
INCOMING_RPCS[RPC.SHOWTEXTDRAW]               = {'onShowTextDraw',
  {textdrawId = 'uint16'},
  {textdraw = {
    {flags = 'uint8'},
    {letterWidth = 'float'},
    {letterHeight = 'float'},
    {letterColor = 'int32'},
    {lineWidth = 'float'},
    {lineHeight = 'float'},
    {boxColor = 'int32'},
    {shadow = 'uint8'},
    {outline = 'uint8'},
    {backgroundColor = 'int32'},
    {style = 'uint8'},
    {selectable = 'uint8'},
    {position = 'vector2d'},
    {modelId = 'uint16'},
    {rotation = 'vector3d'},
    {zoom = 'float'},
    {color1 = 'int16'},
    {color2 = 'int16'},
    {text = 'string16'}
  }}
}
INCOMING_RPCS[RPC.SETPLAYERWANTEDLEVEL]       = {'onSetPlayerWantedLevel', {wantedLevel = 'uint8'}}
INCOMING_RPCS[RPC.TEXTDRAWHIDEFORPLAYER]      = {'onTextDrawHide', {textDrawId = 'uint16'}}
INCOMING_RPCS[RPC.REMOVEPLAYERMAPICON]        = {'onRemoveMapIcon', {iconId = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERAMMO]              = {'onSetWeaponAmmo', {weaponId = 'uint8'}, {ammo = 'uint16'}}
INCOMING_RPCS[RPC.SETGRAVITY]                 = {'onSetGravity', {gravity = 'float'}}
INCOMING_RPCS[RPC.SETVEHICLEHEALTH]           = {'onSetVehicleHealth', {vehicleId = 'uint16'}, {health = 'float'}}
INCOMING_RPCS[RPC.ATTACHTRAILERTOVEHICLE]     = {'onAttachTrailerToVehicle', {trailerId = 'uint16'}, {vehicleId = 'uint16'}}
INCOMING_RPCS[RPC.DETACHTRAILERFROMVEHICLE]   = {'onDetachTrailerFromVehicle', {vehicleId = 'uint16'}}
INCOMING_RPCS[RPC.SETWEATHER]                 = {'onSetWeather', {weatherId = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERSKIN]              = {'onSetPlayerSkin', {playerId = 'int32'}, {skinId = 'int32'}}
INCOMING_RPCS[RPC.SETPLAYERINTERIOR]          = {'onSetInterior', {interior = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERCAMERAPOS]         = {'onSetCameraPosition', {position = 'vector3d'}}
INCOMING_RPCS[RPC.SETPLAYERCAMERALOOKAT]      = {'onSetCameraLookAt', {lookAtPosition = 'vector3d'}, {cutType = 'uint8'}}
INCOMING_RPCS[RPC.SETVEHICLEPOS]              = {'onSetVehiclePosition', {vehicleId = 'uint16'}, {position = 'vector3d'}}
INCOMING_RPCS[RPC.SETVEHICLEZANGLE]           = {'onSetVehicleAngle', {vehicleId = 'uint16'}, {angle = 'float'}}
INCOMING_RPCS[RPC.SETVEHICLEPARAMSFORPLAYER]  = {'onSetVehicleParams', {vehicleId = 'uint16'}, {objective = 'bool8'}, {doorsLocked = 'bool8'}}
INCOMING_RPCS[RPC.SETCAMERABEHINDPLAYER]      = {'onSetCameraBehind'}
INCOMING_RPCS[RPC.CHAT]                       = {'onChatMessage', {playerId = 'uint16'}, {text = 'string8'}}
INCOMING_RPCS[RPC.CONNECTIONREJECTED]         = {'onConnectionRejected', {reason = 'uint8'}}
INCOMING_RPCS[RPC.WORLDPLAYERREMOVE]          = {'onPlayerStreamOut', {playerId = 'uint16'}}
INCOMING_RPCS[RPC.WORLDVEHICLEADD]            = {'onVehicleStreamIn', handler.rpc_vehicle_stream_in_reader, handler.rpc_vehicle_stream_in_writer}
INCOMING_RPCS[RPC.WORLDVEHICLEREMOVE]         = {'onVehicleStreamOut', {vehicleId = 'uint16'}}
INCOMING_RPCS[RPC.WORLDPLAYERDEATH]           = {'onPlayerDeath', {playerId = 'uint16'}}
INCOMING_RPCS[RPC.ENTERVEHICLE]               = {'onPlayerEnterVehicle', {playerId = 'uint16'}, {vehicleId = 'uint16'}, {passenger = 'bool8'}}
INCOMING_RPCS[RPC.UPDATESCORESPINGSIPS]       = {'onUpdateScoresAndPings', handler.rpc_update_scores_and_pings_reader, handler.rpc_update_scores_and_pings_writer}
INCOMING_RPCS[RPC.SETOBJECTMATERIAL]          = {{'onSetObjectMaterial', 'onSetObjectMaterialText'}, handler.rpc_set_object_material_reader, handler.rpc_set_object_material_writer}
INCOMING_RPCS[RPC.CREATEACTOR]                = {'onCreateActor', {actorId = 'uint16'}, {skinId = 'int32'}, {position = 'vector3d'}, {rotation = 'float'}, {health = 'float'}}
INCOMING_RPCS[RPC.CLICKTEXTDRAW]              = {'onToggleSelectTextDraw', {state = 'bool'}, {hovercolor = 'int32'}}
INCOMING_RPCS[RPC.SETVEHICLEPARAMSEX]         = {'onSetVehicleParamsEx',
  {vehicleId = 'uint16'},
  {params = {
    {engine = 'uint8'},
    {lights = 'uint8'},
    {alarm = 'uint8'},
    {doors = 'uint8'},
    {bonnet = 'uint8'},
    {boot = 'uint8'},
    {objective = 'uint8'},
    {unknown = 'uint8'}
  }},
  {doors = {
    {driver = 'uint8'},
    {passenger = 'uint8'},
    {backleft = 'uint8'},
    {backright = 'uint8'}
  }},
  {windows = {
    {driver = 'uint8'},
    {passenger = 'uint8'},
    {backleft = 'uint8'},
    {backright = 'uint8'}
  }}
}
INCOMING_RPCS[RPC.SETPLAYERATTACHEDOBJECT]    = {'onSetPlayerAttachedObject',
  {playerId = 'uint16'},
  {index = 'int32'},
  {create = 'bool'},
  {object = {
    {modelId = 'int32'},
    {bone = 'int32'},
    {offset = 'vector3d'},
    {rotation = 'vector3d'},
    {scale = 'vector3d'},
    {color1 = 'int32'},
    {color2 = 'int32'}}
  }
}
INCOMING_RPCS[RPC.CLIENTCHECK] = {'onClientCheck', {requestType = 'uint8'}, {subject = 'int32'}, {offset = 'uint16'}, {length = 'uint16'}}
INCOMING_RPCS[RPC.DESTROYACTOR] = {'onDestroyActor', {actorId = 'uint16'}}
INCOMING_RPCS[RPC.DESTROYWEAPONPICKUP] = {'onDestroyWeaponPickup', {id = 'uint8'}}
INCOMING_RPCS[RPC.EDITATTACHEDOBJECT] = {'onEditAttachedObject', {index = 'int32'}}
INCOMING_RPCS[RPC.TOGGLECAMERATARGET] = {'onToggleCameraTargetNotifying', {enable = 'bool'}}
INCOMING_RPCS[RPC.SELECTOBJECT] = {'onEnterSelectObject'}
INCOMING_RPCS[RPC.EXITVEHICLE] = {'onPlayerExitVehicle', {playerId = 'uint16'}, {vehicleId = 'uint16'}}
INCOMING_RPCS[RPC.SCMEVENT] = {'onVehicleTuningNotification', {playerId = 'uint16'}, {event = 'int32'}, {vehicleId = 'int32'}, {param1 = 'int32'}, {param2 = 'int32'}}
INCOMING_RPCS[RPC.SRVNETSTATS] = {'onServerStatisticsResponse'} --, {data = 'RakNetStatisticsStruct'}}
INCOMING_RPCS[RPC.EDITOBJECT] = {'onEnterEditObject', {playerObject = 'bool'}, {objectId = 'uint16'}}
INCOMING_RPCS[RPC.DAMAGEVEHICLE] = {'onVehicleDamageStatusUpdate', {vehicleId = 'uint16'}, {panelDmg = 'int32'}, {doorDmg = 'int32'}, {lights = 'uint8'}, {tires = 'uint8'}}
INCOMING_RPCS[RPC.DISABLEVEHICLECOLLISIONS] = {'onDisableVehicleCollisions', {disable = 'bool'}}
INCOMING_RPCS[RPC.TOGGLEWIDESCREEN] = {'onToggleWidescreen', {enable = 'bool8'}}
INCOMING_RPCS[RPC.SETVEHICLETIRES] = {'onSetVehicleTires', {vehicleId = 'uint16'}, {tires = 'uint8'}}
INCOMING_RPCS[RPC.SETPLAYERDRUNKVISUALS] = {'onSetPlayerDrunkVisuals', {level = 'int32'}}
INCOMING_RPCS[RPC.SETPLAYERDRUNKHANDLING] = {'onSetPlayerDrunkHandling', {level = 'int32'}}
INCOMING_RPCS[RPC.APPLYACTORANIMATION] = {'onApplyActorAnimation', {actorId = 'uint16'}, {animLib = 'string8'}, {animName = 'string8'}, {frameDelta = 'float'}, {loop = 'bool'}, {lockX = 'bool'}, {lockY = 'bool'}, {freeze = 'bool'}, {time = 'int32'}}
INCOMING_RPCS[RPC.CLEARACTORANIMATION] = {'onClearActorAnimation', {actorId = 'uint16'}}
INCOMING_RPCS[RPC.SETACTORROTATION] = {'onSetActorFacingAngle', {actorId = 'uint16'}, {angle = 'float'}}
INCOMING_RPCS[RPC.SETACTORPOSITION] = {'onSetActorPos', {actorId = 'uint16'}, {position = 'vector3d'}}
INCOMING_RPCS[RPC.SETACTORHEALTH] = {'onSetActorHealth', {actorId = 'uint16'}, {health = 'float'}}
INCOMING_RPCS[RPC.SETPLAYEROBJECTNOCAMCOL] = {'onSetPlayerObjectNoCameraCol', {objectId = 'uint16'}}
INCOMING_RPCS[125] = {'_dummy125'}
INCOMING_RPCS[64] = {'_dummy64', {'uint16'}}
INCOMING_RPCS[48] = {'_unused48', {'int32'}}


-- Outgoing packets
OUTCOMING_PACKETS[PACKET.RCON_COMMAND]        = {'onSendRconCommand', {command = 'string32'}}
OUTCOMING_PACKETS[PACKET.STATS_UPDATE]        = {'onSendStatsUpdate', {money = 'int32'}, {drunkLevel = 'int32'}}
local function empty_writer() end
OUTCOMING_PACKETS[PACKET.PLAYER_SYNC]         = {'onSendPlayerSync', function(bs) return utils.process_outcoming_sync_data(bs, 'PlayerSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.VEHICLE_SYNC]        = {'onSendVehicleSync', function(bs) return utils.process_outcoming_sync_data(bs, 'VehicleSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.PASSENGER_SYNC]      = {'onSendPassengerSync', function(bs) return utils.process_outcoming_sync_data(bs, 'PassengerSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.AIM_SYNC]            = {'onSendAimSync', function(bs) return utils.process_outcoming_sync_data(bs, 'AimSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.UNOCCUPIED_SYNC]     = {'onSendUnoccupiedSync', function(bs) return utils.process_outcoming_sync_data(bs, 'UnoccupiedSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.TRAILER_SYNC]        = {'onSendTrailerSync', function(bs) return utils.process_outcoming_sync_data(bs, 'TrailerSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.BULLET_SYNC]         = {'onSendBulletSync', function(bs) return utils.process_outcoming_sync_data(bs, 'BulletSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.SPECTATOR_SYNC]      = {'onSendSpectatorSync', function(bs) return utils.process_outcoming_sync_data(bs, 'SpectatorSyncData') end, empty_writer}
OUTCOMING_PACKETS[PACKET.WEAPONS_UPDATE] = {'onSendWeaponsUpdate', handler.packet_weapons_update_reader, handler.packet_weapons_update_writer}
OUTCOMING_PACKETS[PACKET.AUTHENTICATION] = {'onSendAuthenticationResponse', {response = 'string8'}}

-- Incoming packets
INCOMING_PACKETS[PACKET.PLAYER_SYNC]          = {'onPlayerSync', handler.packet_player_sync_reader, handler.packet_player_sync_writer}
INCOMING_PACKETS[PACKET.VEHICLE_SYNC]         = {'onVehicleSync', handler.packet_vehicle_sync_reader, handler.packet_vehicle_sync_writer}
INCOMING_PACKETS[PACKET.MARKERS_SYNC]         = {'onMarkersSync', handler.packet_markers_sync_reader, handler.packet_markers_sync_writer}
INCOMING_PACKETS[PACKET.AIM_SYNC]             = {'onAimSync', {playerId = 'uint16'}, {data = 'AimSyncData'}}
INCOMING_PACKETS[PACKET.BULLET_SYNC]          = {'onBulletSync', {playerId = 'uint16'}, {data = 'BulletSyncData'}}
INCOMING_PACKETS[PACKET.UNOCCUPIED_SYNC]      = {'onUnoccupiedSync', {playerId = 'uint16'}, {data = 'UnoccupiedSyncData'}}
INCOMING_PACKETS[PACKET.TRAILER_SYNC]         = {'onTrailerSync', {playerId = 'uint16'}, {data = 'TrailerSyncData'}}
INCOMING_PACKETS[PACKET.PASSENGER_SYNC]       = {'onPassengerSync', {playerId = 'uint16'}, {data = 'PassengerSyncData'}}
INCOMING_PACKETS[PACKET.AUTHENTICATION] = {'onAuthenticationRequest', {key = 'string8'}}
INCOMING_PACKETS[PACKET.CONNECTION_REQUEST_ACCEPTED] = {'onConnectionRequestAccepted', {ip = 'int32'}, {port = 'uint16'}, {playerId = 'uint16'}, {challenge = 'int32'}}
INCOMING_PACKETS[PACKET.CONNECTION_LOST] = {'onConnectionLost'}
INCOMING_PACKETS[PACKET.CONNECTION_BANNED] = {'onConnectionBanned'}
INCOMING_PACKETS[PACKET.CONNECTION_ATTEMPT_FAILED] = {'onConnectionAttemptFailed'}
INCOMING_PACKETS[PACKET.NO_FREE_INCOMING_CONNECTIONS] = {'onConnectionNoFreeSlot'}
INCOMING_PACKETS[PACKET.INVALID_PASSWORD] = {'onConnectionPasswordInvalid'}
INCOMING_PACKETS[PACKET.DISCONNECTION_NOTIFICATION] = {'onConnectionClosed'}

return events

end
package.preload["addon"] = function(...)
local vector3d = require("vector3d")


function isBotInAnyVehicle()
	return getBotVehicle() ~= 0
end

function sendSpawnRequest()
	bitStream.new():sendRPC(129)
end

function sendDialogResponse(id, button, list, input)
	assert(type(input) == "string" and #input <= 255, "dialog input must be at most 255 bytes")
	assert(type(id) == "number" and id >= 0 and id <= 32767 and id % 1 == 0, "invalid dialog id")
	assert(button == 0 or button == 1, "invalid dialog button")
	assert(type(list) == "number" and list >= -1 and list <= 32767 and list % 1 == 0, "invalid dialog list")
	local bs = bitStream.new()
	bs:writeUInt16(id)
	bs:writeUInt8(button)
	bs:writeUInt16(list)
	bs:writeUInt8(input:len())
	bs:writeString(input)
	bs:sendRPC(62)
end

function sendClickTextdraw(id)
	assert(type(id) == "number", "number expected, got "..type(id))
	local bs = bitStream.new()
	bs:writeUInt16(id)
	bs:sendRPC(83)
end

function sendPickedUpPickup(id)
	assert(type(id) == "number", "number expected, got "..type(id))
	local bs = bitStream.new()
	bs:writeUInt32(id)
	bs:sendRPC(131)
end

function sendVehicleEnter(id, passenger)
	assert(type(id) == "number", "number expected, got "..type(id))
	local bs = bitStream.new()
	bs:writeUInt16(id)
	bs:writeBool8(passenger)
	bs:sendRPC(26)
end

function sendVehicleExit(id)
	assert(type(id) == "number", "number expected, got "..type(id))
	local bs = bitStream.new()
	bs:writeUInt16(id)
	bs:sendRPC(154)
end

function sendTargetUpdate(object, vehicle, player, actor)
	local bs = bitStream.new()
	bs:writeUInt16(object)
	bs:writeUInt16(vehicle)
	bs:writeUInt16(player)
	bs:writeUInt16(actor)
	bs:sendRPC(168)
end

function sendInput(text)
	assert(type(text) == "string", "string expected, got "..type(text))
	local bs = bitStream.new()
	if text:sub(1, 1) == "/" then
		bs:writeUInt32(text:len())
		bs:writeString(text)
		bs:sendRPC(50)
	else
		bs:writeUInt8(text:len())
		bs:writeString(text)
		bs:sendRPC(101)
	end
end

function bitStream:readString8()
	return self:readString(self:readUInt8())
end

function bitStream:writeString8(v)
	assert(type(v) == "string", "string expected, got "..type(v))
	assert(#v <= 255, "string8 exceeds 255 bytes")
	self:writeUInt8(#v)
	self:writeString(v)
end

function bitStream:readBool8()
	return (self:readUInt8() ~= 0)
end

function bitStream:writeBool8(v)
	self:writeUInt8(v and 1 or 0)
end

function bitStream:writeArray(v)
	assert(type(v) == "table", "table expected, got "..type(v))
	for _, byte in ipairs(v) do
		assert(type(byte) == "number", "number expected, got "..type(byte))
		self:writeUInt8(byte)
	end
end

function bitStream:writeVector3(v)
	assert(type(v) == "table", "table expected, got "..type(v))
	self:writeFloat(v.x)
	self:writeFloat(v.y)
	self:writeFloat(v.z)
end

function bitStream:readVector3()
	local vec = vector3d()
	vec.x = self:readFloat()
	vec.y = self:readFloat()
	vec.z = self:readFloat()
	return vec
end

---------------- TASKS ----------------

local taskClock = require("termuh-runtime").gettime
local count = 0
local tasks = {}


function wait(time)
	coroutine.yield(time / 1000)
end

function newTask(f, halted, ...)
	assert(type(f) == "function", "function expected, got "..type(f))
	count = count + 1
	tasks[count] = {
		id = count,
		f = coroutine.create(f),
		wake_time = type(halted) == "number" and taskClock() + halted / 1000 or taskClock(),
		halted = type(halted) == "boolean" and halted or false,
		args = {...},

		isAlive = function(self)
			return tasks[self.id] ~= nil
		end,
		isHalted = function(self)
			return self.halted
		end,
		halt = function(self)
			self.halted = true
		end,
		resume = function(self)
			self.halted = false
		end,
		kill = function(self)
			tasks[self.id] = nil
		end,
		tick = function(self)
			if self.halted or self.wake_time > taskClock() then
				return
			elseif coroutine.status(self.f) == "dead" then
				self:kill()
				return
			end
			local resumed, result = coroutine.resume(self.f, (table.unpack or unpack)(self.args))
			if not resumed then
				self:kill()
			error(result, 2)
			elseif result then
				self.wake_time = taskClock() + result
			end
		end
	}
	local task = tasks[count]
	task:tick()
	return task
end

function clearTasks()
	tasks = {}
end

registerHandler("onUpdate", function()
	for id, task in pairs(tasks) do
		task:tick()
	end
end)
end
package.preload["damage_status"] = function(...)
local bit = require("bit")
require("sampfuncs")

local module = {}

module._NAME = "VehicleDamageStatus"
module._AUTHOR = "Ulong"
module._VERSION = "1.0.0"
module._DESCRIPTION = "Manipulate damage status of vehicle components"

module.VEH_COMP_POOL = {}
module.onVehicleDamageStatusChanged = function(vehicleId, updatedComponents, streamed) end

module.COMPONENTS = {
	DOORS = {
        HOOD          		= 0x0,
        TRUNK         		= 0x1,
        DRIVER_DOOR   		= 0x2,
        PASSENGER_DOOR 		= 0x3,
		STATES = {
			NORMAL     		= 0x0,
			OPENED     		= 0x1,
			DAMAGED    		= 0x2,
			REMOVED   	 	= 0x4
		}
    },
	PANELS = {
        FRONT_LEFT     		= 0x0,
        FRONT_RIGHT    		= 0x1,
        BACK_LEFT      		= 0x2,
        BACK_RIGHT     		= 0x3,
        WINDSHIELD     		= 0x4,
        FRONT_BUMPER   		= 0x5,
        BACK_BUMPER			= 0x6,
        STATES = {
			NORMAL        	= 0x0,
			CRUSHED      	= 0x1,
            HANGING_LOOSE 	= 0x2,
            REMOVED       	= 0x3
		}
	},
	TIRES = {
		BACK_RIGHT			= 0x0,
		FRONT_RIGHT			= 0x1,
		BACK_LEFT			= 0x2,
		FRONT_LEFT			= 0x3,
		STATES = {
			NORMAL			= 0x0,
			POPPED			= 0x1,
		}
	},
	LIGHTS = {
		FRONT_LEFT			= 0x0,
		FRONT_RIGHT			= 0x2,
		BACK_LIGHT			= 0x6,
		STATES = {
			NORMAL			= 0x0,
			BROKEN      	= 0x1
		}
	},
	UPDATE = {
		door = "door",
		panel = "panel",
		light = "light",
		tire = "tire"
	}
}

print(string.format("[%s] Module loaded! Author %s. Version %s", module._NAME, module._AUTHOR, module._VERSION))

local function checkDamageStatusUpdated(vehicleId, new_components)
    local old_components = module.VEH_COMP_POOL[vehicleId]
	if old_components ~= nil then
		local flags = {}
		for key in pairs(module.COMPONENTS.UPDATE) do
			flags[key] = (old_components[key] ~= new_components[key])
		end
		module.VEH_COMP_POOL[vehicleId] = new_components
		module.onVehicleDamageStatusChanged(vehicleId, flags, true)
	end
end

local function sendUpdateVehicleDamageStatus(vehicleId, data)
	local bs = bitStream.new()
	bs:writeUInt16(vehicleId)
	bs:writeUInt32(data.panel)
	bs:writeUInt32(data.door)
	bs:writeUInt8(data.light)
	bs:writeUInt8(data.tire)
	bs:sendRPC(RPC_DAMAGEVEHICLE)
end

registerHandler("onReceiveRPC", function(id, bs)
	if id == RPC_SCRWORLDVEHICLEADD then
		local vehicleId = bs:readUInt16()
		bs:setReadOffset(16 + 32 + 32 + 32 + 32 + 32 + 8 + 8 + 32 + 8)
		module.VEH_COMP_POOL[vehicleId] = {door = bs:readUInt32(), panel = bs:readUInt32(), light = bs:readUInt8(), tire = bs:readUInt8()}
		module.onVehicleDamageStatusChanged(vehicleId, {door = true, panel = true, light = true, tire = true}, false)
	elseif id == RPC_DAMAGEVEHICLE then
		local vehicleId = bs:readUInt16()
		local updated_comp = {}
		updated_comp.panel = bs:readUInt32()
		updated_comp.door = bs:readUInt32()
		updated_comp.light = bs:readUInt8()
		updated_comp.tire = bs:readUInt8()
		checkDamageStatusUpdated(vehicleId, updated_comp)
	elseif id == RPC_SCRWORLDVEHICLEREMOVE then
		local vehicleId = bs:readUInt16()
		module.VEH_COMP_POOL[vehicleId] = nil
	end
end)

registerHandler("onReceivePacket", function(id, bs)
	if id == PACKET_DISCONNECTION_NOTIFICATION or id == PACKET_CONNECTION_LOST then
		module.VEH_COMP_POOL = {}
	end
end)

function module.getVehicleDoorState(vehicleId, door, state)
	if module.VEH_COMP_POOL[vehicleId] ~= nil then
		local all_doors = module.VEH_COMP_POOL[vehicleId].door
		return bit.band(bit.rshift(all_doors, (8 * door)), state) ~= 0
	end
	return false
end

function module.setVehicleDoorState(door, state)
    local vehicleId = getBotVehicle()
	if vehicleId ~= 0 then
		if module.VEH_COMP_POOL[vehicleId] ~= nil then
			local all_doors = module.VEH_COMP_POOL[vehicleId].door
			all_doors = bit.bor(bit.band(all_doors, bit.bnot(bit.lshift(0x7, 8 * door))), bit.lshift(state, 8 * door))
            if state == module.COMPONENTS.DOORS.STATES.NORMAL then
                all_doors = bit.band(all_doors, bit.bnot(bit.lshift(0x7, (8 * door))))
            end
			module.VEH_COMP_POOL[vehicleId].door = all_doors
			sendUpdateVehicleDamageStatus(vehicleId, module.VEH_COMP_POOL[vehicleId])
			return true
		end
	end
	return false
end

function module.getVehiclePanelState(vehicleId, panel, state)
    if module.VEH_COMP_POOL[vehicleId] ~= nil then
		local all_panels = module.VEH_COMP_POOL[vehicleId].panel
        return bit.band(bit.rshift(all_panels, (4 * panel)), 0x0F) == state
    end
    return false
end

function module.setVehiclePanelState(panel, state)
    local vehicleId = getBotVehicle()
    if vehicleId ~= 0 then
        if module.VEH_COMP_POOL[vehicleId] ~= nil then
            local all_panels = module.VEH_COMP_POOL[vehicleId].panel
			all_panels = bit.bor(bit.band(all_panels, bit.bnot(bit.lshift(0x0F, 4 * panel))), bit.lshift(state, 4 * panel))
            if state == module.COMPONENTS.PANELS.STATES.NORMAL then
				all_panels = bit.band(all_panels, bit.bnot(bit.lshift(0x0F, (4 * panel))))
            end
            module.VEH_COMP_POOL[vehicleId].panel = all_panels
            sendUpdateVehicleDamageStatus(vehicleId, module.VEH_COMP_POOL[vehicleId])
            return true
        end
    end
    return false
end

function module.getVehicleTireState(vehicleId, tire)
    if module.VEH_COMP_POOL[vehicleId] ~= nil then
        local all_tires = module.VEH_COMP_POOL[vehicleId].tire
        return bit.band(bit.rshift(all_tires, tire), 1) == module.COMPONENTS.TIRES.STATES.NORMAL
    end
    return false
end

function module.setVehicleTireState(tire, state)
    local vehicleId = getBotVehicle()
    if vehicleId ~= 0 then
        if module.VEH_COMP_POOL[vehicleId] ~= nil then
            local all_tires = module.VEH_COMP_POOL[vehicleId].tire
			all_tires = bit.bor(all_tires, bit.lshift(1, tire))
            if state == module.COMPONENTS.TIRES.STATES.NORMAL then
                all_tires = bit.band(all_tires, bit.bnot(bit.lshift(1, tire)))
            end
            module.VEH_COMP_POOL[vehicleId].tire = all_tires
            sendUpdateVehicleDamageStatus(vehicleId, module.VEH_COMP_POOL[vehicleId])
            return true
        end
    end
    return false
end

function module.getVehicleLightState(vehicleId, light)
    if module.VEH_COMP_POOL[vehicleId] ~= nil then
        local all_lights = module.VEH_COMP_POOL[vehicleId].light
		return bit.band(all_lights, bit.lshift(1, light)) == module.COMPONENTS.LIGHTS.STATES.NORMAL
    end
    return false
end

function module.setVehicleLightState(light, state)
    local vehicleId = getBotVehicle()
    if vehicleId ~= 0 then
        if module.VEH_COMP_POOL[vehicleId] ~= nil then
            local all_lights = module.VEH_COMP_POOL[vehicleId].light
			all_lights = bit.bor(all_lights, bit.lshift(1, light))
            if state == module.COMPONENTS.LIGHTS.STATES.NORMAL then
				all_lights = bit.band(all_lights, bit.bnot(bit.lshift(1, light)))
            end
            module.VEH_COMP_POOL[vehicleId].light = all_lights
            sendUpdateVehicleDamageStatus(vehicleId, module.VEH_COMP_POOL[vehicleId])
            return true
        end
    end
    return false
end

for k, v in pairs(module.COMPONENTS) do
    _G[k] = v
end

return module
end
package.preload["termuh-guards"] = function(...)
-- Bounds checks adapted from Ulong's uCrashProtector. Loaded before samp.events.
-- No Windows UI, ID substitution or InitGame reconnect is needed here.
local function requireBits(bs, count)
    assert(bs:getNumberOfUnreadBits() >= count, 'truncated RPC')
end
local function string8(bs)
    requireBits(bs, 8)
    local length = bs:readUInt8()
    requireBits(bs, length * 8)
    return bs:readString(length)
end
local function inspect(id, bs)
    if id == 61 then
        requireBits(bs, 16)
        local dialog = bs:readUInt16()
        assert(dialog == 65535 or dialog <= 32767, 'invalid dialog ID')
        requireBits(bs, 8)
        assert(bs:readUInt8() <= 5, 'invalid dialog style')
        string8(bs); string8(bs); string8(bs)
        requireBits(bs, 1) -- compressed dialog text is decoded by samp.events
    elseif id == 134 or id == 105 then
        local offset = id == 134 and 520 or 16
        requireBits(bs, offset + 16)
        bs:ignoreBits(offset)
        local length = bs:readUInt16()
        assert(length < 1024, 'textdraw too long')
        assert(bs:getNumberOfUnreadBits() == length * 8, 'textdraw length mismatch')
    elseif id == 73 then
        requireBits(bs, 96)
        bs:ignoreBits(64)
        local length = bs:readUInt32()
        assert(length < 400, 'gametext too long')
        assert(bs:getNumberOfUnreadBits() == length * 8, 'gametext length mismatch')
    end
end
local function guard(id, bs)
    if id ~= 61 and id ~= 134 and id ~= 105 and id ~= 73 then return end
    bs:setReadOffset(0)
    local ok = pcall(inspect, id, bs)
    bs:setReadOffset(0)
    if not ok then
        print('[Termuh] Malformed RPC blocked: ' .. id)
        return false
    end
end
registerHandler('onReceiveRPC', guard)
return {check = guard}

end
package.preload["arizona-cef-dialogs"] = function(...)
-- RakSAMP Lite backend for arizona-cef-dialogs (original API: XRLM).
-- No DOM/JavaScript engine exists in this host. RPC 61 is the dialog source.
local M = { PREFIX = 'arizona-cef-dialogs', generation = 0, active = false }
local function integer(value, lo, hi)
    return type(value) == 'number' and value == math.floor(value) and value >= lo and value <= hi
end
local function emptyDialog()
    return {id = -1, style = -1, title = '', button1 = '', button2 = '', text = ''}
end
function M.reset()
    M.generation = M.generation + 1
    M.active = false
    M.lastDialogInfo = emptyDialog()
    M.lastDialogRespond = {id = -1, button = -1, list = -1, input = ''}
    M.input, M.list = '', -1
end
M.reset()
function M.observe(id, style, title, button1, button2, text)
    M.reset()
    if id == 65535 or id == -1 then return end -- server closes the current dialog
    if not integer(id, 0, 32767) or not integer(style, 0, 5) then return end
    M.lastDialogInfo = {id = id, style = style, title = title, button1 = button1, button2 = button2, text = text}
    M.active = true
    M.list = style == 2 or style == 4 or style == 5
    M.list = M.list and 0 or -1
end
function M.observeResponse(id, button, list, input)
    M.lastDialogRespond = {id = id, button = button, list = list, input = input}
    if M.active and M.GetId() == id then
        M.active = false
        M.generation = M.generation + 1
        M.input = ''
    end
end
function M.attach(events)
    local show, respond = events.onShowDialog, events.onSendDialogResponse
    events.onShowDialog = function(id, style, title, b1, b2, text)
        M.observe(id, style, title, b1, b2, text)
        if show then return show(id, style, title, b1, b2, text) end
    end
    events.onSendDialogResponse = function(id, button, list, input)
        local result
        if respond then result = respond(id, button, list, input) end
        if result ~= false then
            if type(result) == 'table' then
                M.observeResponse(unpack(result))
            else
                M.observeResponse(id, button, list, input)
            end
        end
        return result
    end
end
function M.IsDialogActive() return M.active end
function M.GetId() return M.lastDialogInfo.id end
function M.GetDialogText() return M.lastDialogInfo.text end
function M.GetStyle() return M.lastDialogInfo.style end
function M.GetTitle() return M.lastDialogInfo.title end
function M.GetButton1() return M.lastDialogInfo.button1 end
function M.GetButton2() return M.lastDialogInfo.button2 end
function M.GetRespond()
    local r = M.lastDialogRespond
    return r.id, r.button, r.list, r.input
end
function M.SetInputText(text)
    if not M.active then return false, 'no active dialog' end
    if type(text) ~= 'string' or #text > 255 then return false, 'input exceeds 255 bytes or is not a string' end
    M.input = text
    return true
end
local function query(value, isAsync, callback)
    if isAsync then
        assert(type(callback) == 'function', 'callback must be a function')
        -- The model is local; there is no browser round trip to wait for.
        callback(value)
        return
    end
    return value
end
function M.GetInputText(isAsync, callback) return query(M.input, isAsync, callback) end
function M.GetListItem(isAsync, callback) return query(M.list, isAsync, callback) end
function M.SetListItem(index)
    if not M.active or not integer(index, 0, 32767) then return false, 'invalid list index' end
    local style, count = M.GetStyle(), 0
    if M.GetDialogText() == '' then return false, 'empty list' end
    if style ~= 2 and style ~= 4 and style ~= 5 then return false, 'dialog has no list' end
    for _ in (M.GetDialogText() .. '\n'):gmatch('(.-)\n') do count = count + 1 end
    if M.GetDialogText():sub(-1) == '\n' then count = count - 1 end
    if style == 5 then count = count - 1 end
    if index >= count then return false, 'list index out of range' end
    M.list = index
    return true
end
function M.CloseWithButton(button)
    button = button or 0
    if not M.active or not integer(button, 0, 1) then return false, 'no active dialog or invalid button' end
    if type(isBotConnected) == 'function' and not isBotConnected() then return false, 'disconnected' end
    local id, list, input = M.GetId(), M.list, M.input
    if M.GetStyle() ~= 1 and M.GetStyle() ~= 3 then input = '' end
    sendDialogResponse(id, button, list, input)
    M.observeResponse(id, button, list, input)
    return true
end
function M.Show(id, title, text, button1, button2, style)
    M.observe(id or 0, style or 0, title or '', button1 or '', button2 or '', text or '')
    return M.active
end
function M.cefQuery() return nil, 'JavaScript/DOM is unavailable in RakSAMP Lite' end
function M.cefQueryAsync(_, callback)
    assert(type(callback) == 'function', 'callback must be a function')
    callback(nil, 'JavaScript/DOM is unavailable in RakSAMP Lite')
end

-- Packet layout follows the supplied Termuh and XRLM sources. This recognizes
-- only an explicit setActiveView("Name") event, never arbitrary JavaScript.
function M.readView(bs)
    local ok, value = pcall(function()
        bs:setReadOffset(8)
        if bs:getNumberOfUnreadBits() < 8 then error('missing subtype') end
        if bs:readUInt8() ~= 17 then return nil end
        if bs:getNumberOfUnreadBits() < 56 then error('truncated CEF header') end
        bs:ignoreBits(32)
        local length, encoded = bs:readUInt16(), bs:readUInt8()
        if length > 16384 then error('CEF payload too large') end
        local code
        if encoded == 0 then
            if bs:getNumberOfUnreadBits() < length * 8 then error('truncated CEF payload') end
            code = bs:readString(length)
        elseif encoded == 1 then
            code = bs:readEncoded(length)
        else
            error('unknown CEF encoding')
        end
        if type(code) ~= 'string' or (#code ~= length and not (encoded == 1 and length > 0 and #code == length - 1)) then
            error('CEF length mismatch')
        end
        local view, tail = code:match('event%.setActiveView%s*%(%s*["\']([%w_]+)["\']%s*([,)])')
        if tail then return view end
        -- Current Arizona sends a JSON-array string via window.executeEvent.
        local quote, args = code:match('^%s*window%.executeEvent%s*%(%s*["\']event%.setActiveView["\']%s*,%s*(["\'`])(.-)%1%s*%)%s*;?%s*$')
        if quote then return args:match('^%s*%[%s*["\']([%w_]+)["\']%s*%]%s*$') end
        return nil
    end)
    bs:setReadOffset(0)
    if not ok then return nil, 'invalid CEF packet' end -- never log payloads/passwords
    return value
end
function M.sendMessage(message)
    if type(message) ~= 'string' or #message > 32767 then return false, 'invalid CEF message' end
    local bs = bitStream.new()
    bs:writeUInt8(220)
    bs:writeUInt8(18)
    bs:writeUInt16(#message)
    bs:writeString(message)
    bs:writeInt32(0)
    bs:sendPacketEx(1, 7, 1)
    return true
end
return M

end
require("termuh-guards")
local sampev = require("samp.events")
local utils = require("samp.events.utils")
local handler = require("samp.events.handlers")
local extra = require("samp.events.extra_types")
local runtime = require("termuh-runtime")
local effil_ok, effil = pcall(require, "effil")

local json_ok, json = pcall(require, "cjson")
pcall(require, "sampfuncs")
require("addon")
local dialogs = require("arizona-cef-dialogs")
local damage = require("damage_status")
local walltime = runtime.gettime
local catalog = require("termuh-servers")
local preconnect = require("termuh-preconnect")

local u8 = runtime.UTF8

math.randomseed(os.time() * os.clock() * math.random())
math.random(); math.random(); math.random()

-- ================= КОНФИГУРАЦИЯ =================

local cfg = runtime.loadIni("termuh\\settings.txt")
local refs_promo = cfg and cfg.referals_and_promo or {}
local settings = cfg and cfg.settings or {}
local cef_settings = cfg and cfg.cef or {}
local dialog_settings = cfg and cfg.dialogs or {}
local launcher_settings = cfg and cfg.launcher or {}
local stationary = settings.stationary == true
local session_tasks, session_id = {}, 0
local connection_attempts, connection_blocked = 0, false
local probe_target, probe_job, probe_complete = nil, nil, false
local function resetProbe(clear_target)
    if probe_job then preconnect.cancel(probe_job) end
    probe_job, probe_complete = nil, false
    if clear_target then probe_target = nil end
end
registerHandler("onUpdate", function()
    if not probe_job or probe_complete then return end
    local ok, result, detail = pcall(preconnect.update, probe_job)
    if not ok then
        preconnect.cancel(probe_job)
        probe_complete = true
        print("[HTTP] Check failed; connecting normally")
    elseif result ~= nil then
        probe_complete = true
        print("[HTTP] " .. tostring(detail) .. (result and " (check complete)" or " (check failed; connecting normally)"))
    end
end)

local cef_packets, last_cef_view = 0, "none"
local cef_view, cef_attempted, auth_blocked = nil, false, false
local cef_revision = 0
local drunk_level = 0
local function sessionTask(f, halted, ...)
    local task = newTask(f, halted, ...)
    for i = #session_tasks, 1, -1 do
        if not session_tasks[i]:isAlive() then table.remove(session_tasks, i) end
    end
    if task:isAlive() then session_tasks[#session_tasks + 1] = task end
    return task
end
local function resetSession()
    session_id = session_id + 1
    for _, task in ipairs(session_tasks) do task:kill() end
    session_tasks = {}
    dialogs.reset()
    cef_view, cef_attempted, auth_blocked = nil, false, false
    cef_revision = cef_revision + 1
    drunk_level = 0
    damage.VEH_COMP_POOL = {}
end
local function password()
    if type(settings.password) ~= "string" or settings.password == "" or #settings.password > 255 then
        print("[LOGIN] Set a nonempty password (up to 255 CP1251 bytes) in termuh/settings.txt")
        return nil
    end
    return settings.password
end

local token, chatid
if settings.token and settings.chatid then
    token, chatid = tostring(settings.token), tostring(settings.chatid)
end

local proxys = {}
local current_proxy_index = nil
local my_proxy_ip = "Direct"

local gen_nick = false
local updateid = nil

-- Состояния безопасности и аккаунта
local is_logged_in = false
local checking_mm = false
local spawn_time = 0
local last_health = 100
local fake_crash = false

-- Еда и инвентарь
local use_x3 = false
local has_chips = true
local eating_chips = false

-- Таймеры
local login_watchdog = nil
local hunger_task = nil

local ADMIN_LEAVE_TIME = 30 * 60 * 1000 -- 30 минут паузы после проверки админом

-- Список серверов Arizona RP (1 - 31 + Vice City)
local legacy_servers = {
    ["185.169.134.3:7777"] = "Phoenix",       ["185.169.134.4:7777"] = "Tucson",
    ["185.169.134.43:7777"] = "Scottdale",    ["185.169.134.44:7777"] = "Chandler",
    ["185.169.134.45:7777"] = "Brainburg",    ["185.169.134.5:7777"] = "Saint-Rose",
    ["185.169.134.59:7777"] = "Mesa",         ["185.169.134.61:7777"] = "Red-Rock",
    ["185.169.134.107:7777"] = "Yuma",        ["185.169.134.109:7777"] = "Surprise",
    ["185.169.134.166:7777"] = "Prescott",    ["185.169.134.171:7777"] = "Glendale",
    ["185.169.134.172:7777"] = "Kingman",     ["185.169.134.173:7777"] = "Winslow",
    ["185.169.134.174:7777"] = "Payson",      ["80.66.82.191:7777"] = "Gilbert",
    ["80.66.82.190:7777"] = "Show-Low",       ["80.66.82.188:7777"] = "Casa-Grande",
    ["80.66.82.168:7777"] = "Page",           ["80.66.82.159:7777"] = "Sun-City",
    ["80.66.82.200:7777"] = "Queen-Creek",    ["80.66.82.144:7777"] = "Sedona",
    ["80.66.82.132:7777"] = "Holiday",        ["80.66.82.128:7777"] = "Wednesday",
    ["80.66.82.113:7777"] = "Yava",           ["80.66.82.82:7777"] = "Faraway",
    ["80.66.82.87:7777"] = "Bumble-Bee",      ["80.66.82.54:7777"] = "Christmas",
    ["80.66.82.39:7777"] = "Mirage",          ["80.66.82.33:7777"] = "Love",
    ["80.66.82.22:7777"] = "Drake",           ["80.66.82.147:7777"] = "Vice-City",
    ["80.66.82.199:7777"] = "Space",          ["80.66.82.235:7777"] = "Home"
}

local current_server = "Unknown"
local ref, promo = "", ""

-- Константы пакетов
local PACKET_VEHICLE_SYNC   = 200
local PACKET_AIM_SYNC       = 203
local PACKET_PLAYER_SYNC    = 207
local PACKET_PASSENGER_SYNC = 211

-- ================= МОДУЛЬ 1: AIMSYNC FIX (УЛУЧШЕННЫЙ) =================

local AIM_SYNC_RATE = 8
local bot_move = true
local last_rate_time = os.time() + math.random(10, 45)
local last_pos = {x = 0.0, y = 0.0, z = 0.0}

local function random_float(lower, greater)
    return lower + math.random() * (greater - lower)
end

local cam_yaw = random_float(0, math.pi * 2)
local cam_pitch = random_float(-0.15, 0.15)

-- Генерация нормализованного 3D-вектора камеры с микро-движениями живого игрока
local function updateHumanCamera(aim_data)
    -- Небольшое смещение угла взгляда при каждом обновлении
    cam_yaw = cam_yaw + random_float(-0.08, 0.08)
    cam_pitch = math.max(-0.35, math.min(0.35, cam_pitch + random_float(-0.03, 0.03)))

    local cos_p = math.cos(cam_pitch)
    local fx = math.cos(cam_yaw) * cos_p
    local fy = math.sin(cam_yaw) * cos_p
    local fz = math.sin(cam_pitch)

    -- Нормализация вектора (длина всегда == 1.0)
    local len = math.sqrt(fx * fx + fy * fy + fz * fz)
    aim_data.camFront.x = fx / len
    aim_data.camFront.y = fy / len
    aim_data.camFront.z = fz / len

    -- Позиция камеры на уровне головы персонажа
    aim_data.camPos.x = last_pos.x - (aim_data.camFront.x * 1.5)
    aim_data.camPos.y = last_pos.y - (aim_data.camFront.y * 1.5)
    aim_data.camPos.z = last_pos.z + 0.65

    aim_data.camMode = getBotVehicle() ~= 0 and 18 or 4
    aim_data.camExtZoom = 63
    aim_data.aspectRatio = 85
end

-- ================= МОДУЛЬ 2: FOLLOW BY ULONG (ИСПРАВЛЕННЫЙ) =================

local state = {
    ONFOOT = 0,
    PASSENGER = 1,
    DRIVER = 2
}

local follow = {
    min_dist = 20.0,
    offset = -1.2,
    target_Id = -1,
    veh_health_pool = {},
    temp_task = nil,
    last_clone_time = 0,
    player_state = state.ONFOOT,
    bubble = false
}

local function fprint(msg)
    print("[Follow]: " .. tostring(msg))
end

local function getDistanceFromTwoPoints2D(a, b, a1, b1)
    return math.sqrt((a1 - a) ^ 2 + (b1 - b) ^ 2)
end

local function quat2deg(w, x, y, z)
    local pitch = math.deg(math.atan2(2 * (w * x + y * z), 1 - 2 * (x ^ 2 + y ^ 2)))
    local yaw   = math.deg(math.asin(math.max(-1.0, math.min(1.0, 2 * (w * y - z * x)))))
    local roll  = math.deg(math.atan2(2 * (w * z + x * y), 1 - 2 * (y ^ 2 + z ^ 2)))
    return pitch, yaw, roll
end

local function GetTaskStatus(task)
    return task ~= nil and task:isAlive() or false
end

local function isFollowHoldingPackets()
    return follow.target_Id ~= -1 and (walltime() - follow.last_clone_time < 0.6)
end

local function clonePacketData(packetId, data)
    if GetTaskStatus(follow.temp_task) then return end

    if packetId == PACKET_PLAYER_SYNC then
        local posX, posY, posZ = data.position.x, data.position.y, data.position.z
        if follow.offset ~= 0 then
            local pitch, yaw, roll = quat2deg(data.quaternion[1], data.quaternion[2], data.quaternion[3], data.quaternion[4])
            posX = posX + (follow.offset * math.sin(math.rad(yaw)))
            posY = posY + (follow.offset * math.cos(math.rad(yaw)))
        end

        setBotPosition(posX, posY, posZ)
        setBotQuaternion(data.quaternion[1], data.quaternion[2], data.quaternion[3], data.quaternion[4])
        last_pos = {x = posX, y = posY, z = posZ}
        follow.last_clone_time = walltime()

        local bs = bitStream.new()
        bs:writeUInt8(packetId)
        bs:writeUInt16(data.leftRightKeys or 0)
        bs:writeUInt16(data.upDownKeys or 0)
        bs:writeUInt16(data.keysData or 0)
        bs:writeFloat(posX)
        bs:writeFloat(posY)
        bs:writeFloat(posZ)
        bs:writeFloat(data.quaternion[1])
        bs:writeFloat(data.quaternion[2])
        bs:writeFloat(data.quaternion[3])
        bs:writeFloat(data.quaternion[4])
        bs:writeUInt8(getBotHealth())
        bs:writeUInt8(getBotArmor())
        bs:writeUInt8(0) -- оружие (0 - кулак, чтобы не кикнуло за Weapon Hack)
        bs:writeUInt8(data.specialAction or 0)
        bs:writeFloat(data.moveSpeed.x)
        bs:writeFloat(data.moveSpeed.y)
        bs:writeFloat(data.moveSpeed.z)
        bs:writeFloat((data.surfingOffsets and data.surfingOffsets.x) or 0.0)
        bs:writeFloat((data.surfingOffsets and data.surfingOffsets.y) or 0.0)
        bs:writeFloat((data.surfingOffsets and data.surfingOffsets.z) or 0.0)
        bs:writeUInt16(data.surfingVehicleId or 0)
        -- Передаем реальную анимацию бега/прыжка ведущего игрока (фикс скольжения в T-позе!)
        bs:writeUInt16(data.animationId or 1189)
        bs:writeUInt16(data.animationFlags or 4356)
        bs:sendPacket()
        bs:reset()

    elseif packetId == PACKET_AIM_SYNC then
        local bs = bitStream.new()
        bs:writeUInt8(packetId)
        extra.AimSyncData.write(bs, data)
        bs:sendPacket()
        bs:reset()

    elseif packetId == PACKET_VEHICLE_SYNC then
        if getBotVehicle() ~= 0 then
            local posX, posY, posZ = data.position.x, data.position.y, data.position.z
            if follow.offset ~= 0 then
                local pitch, yaw, roll = quat2deg(data.quaternion[1], data.quaternion[2], data.quaternion[3], data.quaternion[4])
                posX = posX + (follow.offset * math.sin(math.rad(yaw)))
                posY = posY + (follow.offset * math.cos(math.rad(yaw)))
            end

            setBotPosition(posX, posY, posZ)
            last_pos = {x = posX, y = posY, z = posZ}
            follow.last_clone_time = walltime()

            local bs = bitStream.new()
            bs:writeUInt8(packetId)
            bs:writeUInt16(getBotVehicle())
            bs:writeUInt16(data.leftRightKeys or 0)
            bs:writeUInt16(data.upDownKeys or 0)
            bs:writeUInt16(data.keysData or 0)
            bs:writeFloat(data.quaternion[1])
            bs:writeFloat(data.quaternion[2])
            bs:writeFloat(data.quaternion[3])
            bs:writeFloat(data.quaternion[4])
            bs:writeFloat(posX)
            bs:writeFloat(posY)
            bs:writeFloat(posZ)
            bs:writeFloat(data.moveSpeed.x)
            bs:writeFloat(data.moveSpeed.y)
            bs:writeFloat(data.moveSpeed.z)
            bs:writeFloat(follow.veh_health_pool[getBotVehicle()] or 1000.0)
            bs:writeUInt8(getBotHealth())
            bs:writeUInt8(getBotArmor())
            bs:writeUInt8(0)
            bs:writeUInt8(0)
            bs:writeUInt8(data.siren or 0)
            bs:writeUInt8(data.landingGear or 0)
            bs:writeUInt16(0)
            bs:writeFloat(0)
            bs:writeFloat(data.trainSpeed or 0)
            bs:writeUInt16(0)
            bs:sendPacket()
            bs:reset()
        end
    end
end

-- ================= ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ И ПРОКСИ =================

function split(inputstr, sep)
    sep = sep or "%s"
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function writeTxt(filename, text)
    local file = io.open(filename, "a+")
    if file then
        file:write(text .. "\n")
        file:close()
    end
end

function get_server_name(ip)
    local entry = catalog.find(ip)
    if entry then current_server = entry.name; return end
    if not legacy_servers[ip] then
        current_server = tostring(ip)
        return
    end
    current_server = legacy_servers[ip]
end

function get_refpromo(server_name)
    if not refs_promo[server_name] then return end
    local line = refs_promo[server_name]:gsub("%s", "")
    local str = split(line, ",")
    local referal, promocode = str[1], str[2]
    if referal == "Ref" or promocode == "Promo" then
        sendTG(current_server .. " не был найден реферал или промокод, выхожу.")
        sessionTask(exit, 500)
        return
    end
    ref, promo = referal or "", promocode or ""
end

function load_proxys(filename)
    local file = io.open(filename, "r")
    if not file then
        sendTG("Ошибка с загрузкой прокси")
        return
    end
    proxys = {}
    for line in file:lines() do
        line = line:gsub("%s", "")
        if line ~= "" then
            local info = split(line, ":")
            if #info >= 4 then
                proxys[#proxys + 1] = {ip = info[1] .. ":" .. info[2], user = info[3], pass = info[4]}
            end
        end
    end
    file:close()
end

function connect_random_proxy()
    if isProxyConnected() then
        proxyDisconnect()
    end
    if #proxys == 0 then
        load_proxys("termuh\\proxy.txt")
        if #proxys == 0 then return end
    end
    current_proxy_index = math.random(1, #proxys)
    local new_proxy = proxys[current_proxy_index]
    my_proxy_ip = new_proxy.ip
    proxyConnect(new_proxy.ip, new_proxy.user, new_proxy.pass)
end

function remove_bad_proxy()
    if current_proxy_index and proxys[current_proxy_index] then
        print("[PROXY] Отбракован прокси: " .. tostring(proxys[current_proxy_index].ip))
        table.remove(proxys, current_proxy_index)
        current_proxy_index = nil
    end
    connect_random_proxy()
end

function setRandomNick()
    local data = {names = {}, surnames = {}}
    local filenames = {"settings\\names.txt", "settings\\surnames.txt"}
    for i = 1, #filenames do
        local file = io.open(filenames[i], "r")
        if not file then
            sendTG("Ошибка с загрузкой имен/фамилий.")
            return
        end
        for line in file:lines() do
            line = line:gsub("%s", "")
            if line ~= "" then
                table.insert(i == 1 and data.names or data.surnames, line)
            end
        end
        file:close()
    end
    if #data.names > 0 and #data.surnames > 0 then
        local nick = ("%s_%s"):format(
            data.names[math.random(1, #data.names)],
            data.surnames[math.random(1, #data.surnames)]
        )
        setBotNick(nick)
        reconnect(1000)
    end
end

-- ================= АНТИ-БОТ ЗАЩИТА: ГРАВИТАЦИЯ, ТАЙМИНГИ И ФЕЙК-КРАШ =================

-- Очеловеченная отправка диалогов (защита от детекта 0-5ms ответов и диалогов-ловушек)
function humanDialogResponse(id, button, list, input, min_ms, max_ms)
    if not dialogs.IsDialogActive() or dialogs.GetId() ~= id or auth_blocked then return end
    local generation, connection = dialogs.generation, session_id
    sessionTask(function()
        wait(tonumber(dialog_settings.delay_ms) or 500)
        if connection ~= session_id or generation ~= dialogs.generation or not isBotConnected() then return end
        if not dialogs.SetInputText(input or "") then return end
        if list and list >= 0 and (dialogs.GetStyle() == 2 or dialogs.GetStyle() == 4 or dialogs.GetStyle() == 5) then
            if not dialogs.SetListItem(list) then return end
        end
        dialogs.CloseWithButton(button)
    end)
end

-- Эмуляция гравитации при спавн-тесте (плавное приземление, чтобы не висеть в воздухе)
function emulateGravityDrop(drop_height)
    if stationary then return end
    drop_height = drop_height or 0.45
    sessionTask(function()
        local x, y, z = getBotPosition()
        local steps = 4
        local dz = drop_height / steps
        for i = 1, steps do
            wait(60)
            z = z - dz
            setBotPosition(x, y, z)
            last_pos = {x = x, y = y, z = z}
            -- Some RakSAMP Lite builds send the updated position on their normal sync tick.
            if type(sendOnfootSync) == "function" then sendOnfootSync() end
        end
    end)
end

function adminPanic(reason)
    if fake_crash then return end
    fake_crash = true
    is_logged_in = false
    follow.target_Id = -1

    print("[PANIC] " .. reason .. " -> Имитирую краш и выхожу на 30 минут!")
    sendTG(("⚠️ [АДМИН / АНТИ-БОТ ПРОВЕРКА]\nПричина: %s\nИмитирую краш (таймаут) и выхожу на 30 минут.\nНик: %s | ID: %s | Сервер: %s"):format(
        reason, getBotNick(), getBotId(), current_server
    ))

    reconnect(ADMIN_LEAVE_TIME)
end

function isProtectedFromAdminCheck()
    if stationary then return false end
    return is_logged_in and (os.time() - spawn_time > 12)
end

-- 1. Проверка на SetPlayerPos (Слап / ТП) + обновление AimSync
function sampev.onSetPlayerPos(position)
    if stationary then return end
    last_pos = {x = position.x, y = position.y, z = position.z}
    last_rate_time = os.time() - 1

    if isProtectedFromAdminCheck() then
        adminPanic("Смена позиции сервером (Слап / ТП)")
    else
        -- Если сервер подбросил чуть выше земли при спавне (Slap-тест гравитации)
        emulateGravityDrop(0.35)
    end
end

-- 2. Проверка ускорением (SetPlayerVelocity - Slap-тест античита или админа)
function sampev.onSetPlayerVelocity(velocity)
    if stationary then return end
    if isProtectedFromAdminCheck() then
        if math.abs(velocity.x) > 0.01 or math.abs(velocity.y) > 0.01 or math.abs(velocity.z) > 0.01 then
            adminPanic("Применение ускорения сервером (SetPlayerVelocity)")
        end
    else
        -- Если античит проверяет гравитацию при спавне
        if velocity.z > 0 then
            emulateGravityDrop(0.5)
        end
    end
end

-- 3. Заморозка от админа
function sampev.onTogglePlayerControllable(controllable)
    if not controllable and isProtectedFromAdminCheck() then
        adminPanic("Заморозка персонажа (Freeze)")
    end
end

-- 4. Смена интерьера / виртуального мира (невидимая телепортация админом на проверку)
function sampev.onSetPlayerInterior(interior)
    if isProtectedFromAdminCheck() then
        adminPanic("Принудительная смена интерьера админом (ID: " .. tostring(interior) .. ")")
    end
end

-- 5. Резкая смена ХП админом
function sampev.onSetPlayerHealth(health)
    if isProtectedFromAdminCheck() then
        local diff = math.abs(health - last_health)
        if diff >= 5 and not eating_chips then
            adminPanic(("Резкая смена ХП сервером (%d -> %d)"):format(last_health, health))
            return
        end
    end
    last_health = health
end

-- ================= АВТО-ЕДА И ТАЙМЕРЫ ВХОДА =================

function eatChips()
    if not is_logged_in or not has_chips then return end
    eating_chips = true
    sendInput("/eat")
    sessionTask(function()
        wait(5000)
        eating_chips = false
    end)
end

function startHungerTimer()
    if hunger_task then hunger_task:kill() end
    hunger_task = sessionTask(function()
        while true do
            wait(25 * 60 * 1000)
            if is_logged_in and has_chips then
                eatChips()
            end
        end
    end)
end

function startLoginWatchdog()
    if login_watchdog then login_watchdog:kill() end
    login_watchdog = sessionTask(function()
        wait(60000)
        if not is_logged_in then
            print("[WATCHDOG] Не удалось подтвердить вход через /mm за 60 сек. Смена прокси и реконнект...")
            if settings.proxy then
                remove_bad_proxy()
            end
            reconnect(3000)
        end
    end)
end

-- ================= РАБОТА С CEF (ПАКЕТ 220) =================

function sendCEF(str)
    if isBotConnected() then return dialogs.sendMessage(str) end
    return false
end

local function handleCEFView(view)
    if view == cef_view then return end
    cef_view = view
    cef_revision = cef_revision + 1
    if not view then return end
    -- A changed CEF view invalidates pending native replies too.
    dialogs.reset()
    local connection, expected_revision = session_id, cef_revision
    if view == "Auth" and not cef_attempted and not auth_blocked and cef_settings.enabled == true then
        local pass = password()
        local event = cef_settings.auth_event or "auth"
        if not pass or pass:find("|", 1, true) or (event ~= "auth" and event ~= "authorization") then
            print("[CEF] Invalid auth configuration; request not sent")
            return
        end
        cef_attempted = true
        sessionTask(function()
            wait(tonumber(dialog_settings.delay_ms) or 500)
            if connection == session_id and cef_revision == expected_revision and not auth_blocked then
                sendCEF(event .. "|" .. pass)
            end
        end)
    elseif view == "SpawnSelector" and cef_settings.enabled == true and cef_settings.auto_spawn == true then
        sessionTask(function()
            wait(tonumber(dialog_settings.delay_ms) or 500)
            if connection == session_id and cef_revision == expected_revision and not auth_blocked then
                sendCEF("spawnSelector|" .. tostring(math.max(0, math.floor(tonumber(cef_settings.spawn_index) or 0))))
            end
        end)
    end
end

-- ================= ЕДИНЫЙ ОБРАБОТЧИК ПАКЕТОВ (SEND / RECEIVE) =================

local attemp_connect_count = 0

-- Carry the server's drunk state into stats without synthesizing FPS values.
function sampev.onSetPlayerDrunk(level) drunk_level = level end
function sampev.onSendStatsUpdate(money) return {money, drunk_level} end

function onConnect()
    resetProbe(false)
    connection_attempts, connection_blocked = 0, false
    resetSession()
    follow.target_Id, follow.player_state = -1, state.ONFOOT
    follow.veh_health_pool = {}
    follow.temp_task = nil
    if not stationary then startHungerTimer() end
    attemp_connect_count = 0
    is_logged_in = false
    checking_mm = false
    fake_crash = false
    has_chips = true
    eating_chips, use_x3 = false, false
    if not stationary then startLoginWatchdog() end
end

function onDisconnect()
    resetProbe(false)
    resetSession()
    if login_watchdog then login_watchdog:kill() end
    if hunger_task then hunger_task:kill() end
    follow.target_Id, follow.temp_task = -1, nil
    eating_chips, use_x3 = false, false
    is_logged_in = false
    checking_mm = false
end

function onSendPacket(id, bs)
    if stationary then return end
    -- 1. Имитация краша: блокируем пакет чистого выхода (ID 32)
    if id == 32 and fake_crash then
        return false
    end

    -- 2. Отслеживание состояния для Follow
    if id == PACKET_VEHICLE_SYNC then
        follow.player_state = state.DRIVER
    elseif id == PACKET_PLAYER_SYNC then
        if follow.player_state == state.DRIVER and not GetTaskStatus(follow.temp_task) then
            follow.temp_task = sessionTask(function()
                sendVehicleExit(getBotVehicle())
                wait(500)
                setBotVehicle(0, 0)
                follow.player_state = state.ONFOOT
            end)
        else
            follow.player_state = state.ONFOOT
        end
    elseif id == PACKET_PASSENGER_SYNC then
        follow.player_state = state.PASSENGER
    end

    -- Если активно повторяем маршрут за игроком — подавляем стандартные пакеты RakSAMP
    if isFollowHoldingPackets() and (id == PACKET_PLAYER_SYNC or id == PACKET_VEHICLE_SYNC or id == PACKET_AIM_SYNC) then
        return false
    end

    -- 3. Модуль AimSync Fix (очеловеченная камера)
    if id == PACKET_AIM_SYNC then
        if not bot_move then
            if isBotSpawned() then
                if last_rate_time < os.time() then
                    last_rate_time = os.time() + math.random(12, 45)
                    local aim_data = (utils.process_outcoming_sync_data(bs, "AimSyncData"))[1]
                    updateHumanCamera(aim_data)
                else
                    return false
                end
            else
                return false
            end
        else
            bot_move = false
            return false
        end
    end

    if id == PACKET_PLAYER_SYNC or id == PACKET_VEHICLE_SYNC then
        local sync_name = (id == PACKET_PLAYER_SYNC) and "PlayerSyncData" or "VehicleSyncData"
        local data = (utils.process_outcoming_sync_data(bs, sync_name))[1]
        if data.position.x ~= last_pos.x or data.position.y ~= last_pos.y or data.position.z ~= last_pos.z then
            bot_move = true
        end
        last_pos = {x = data.position.x, y = data.position.y, z = data.position.z}
    end
end

function onReceivePacket(id, bs)
    -- 1. Ошибки сети и бан IP -> отбраковка прокси
    if id == 36 or id == 31 then
        if settings.proxy then remove_bad_proxy() end
        return
    elseif id == 29 then
        resetProbe(false)
        attemp_connect_count = attemp_connect_count + 1
        if attemp_connect_count >= 3 then
            if settings.proxy then remove_bad_proxy() end
            attemp_connect_count = 0
        end
        return
    end

    if id == 220 then
        cef_packets = cef_packets + 1
        local view, err = dialogs.readView(bs)
        if err then print("[CEF] Invalid packet ignored") end
        if view then last_cef_view = view; handleCEFView(view) end
        return
    end

    -- 3. Модуль Follow (клонирование пакетов движения за ведущим игроком)
    if follow.target_Id ~= -1 then
        if id == PACKET_PLAYER_SYNC then
            bs:setReadOffset(8)
            local cdata = handler.packet_player_sync_reader(bs)
            if cdata and cdata[1] == follow.target_Id then
                local bX, bY, _ = getBotPosition()
                if getDistanceFromTwoPoints2D(bX, bY, cdata[2].position.x, cdata[2].position.y) <= follow.min_dist then
                    if follow.player_state == state.ONFOOT and getBotVehicle() == 0 then
                        clonePacketData(id, cdata[2])
                    elseif follow.player_state == state.PASSENGER and not GetTaskStatus(follow.temp_task) then
                        follow.temp_task = sessionTask(function()
                            sendVehicleExit(getBotVehicle())
                            wait(500)
                            setBotVehicle(0, 0)
                            follow.player_state = state.ONFOOT
                        end)
                    end
                end
            end

        elseif id == PACKET_AIM_SYNC then
            bs:setReadOffset(8)
            local playerId = bs:readUInt16()
            if playerId == follow.target_Id then
                local cdata = extra.AimSyncData.read(bs)
                clonePacketData(id, cdata)
            end

        elseif id == PACKET_VEHICLE_SYNC then
            bs:setReadOffset(8)
            local cdata = handler.packet_vehicle_sync_reader(bs)
            if cdata then
                follow.veh_health_pool[cdata[2]] = cdata[3].vehicleHealth
                if cdata[1] == follow.target_Id then
                    local bX, bY, _ = getBotPosition()
                    if follow.player_state == state.ONFOOT and getBotVehicle() == 0 then
                        if getDistanceFromTwoPoints2D(bX, bY, cdata[3].position.x, cdata[3].position.y) <= follow.min_dist and not GetTaskStatus(follow.temp_task) then
                            follow.temp_task = sessionTask(function()
                                follow.player_state = state.PASSENGER
                                sendVehicleEnter(cdata[2], 1)
                                wait(500)
                                setBotVehicle(cdata[2], 1)
                                fprint("Сел пассажиром в авто ID: " .. tostring(cdata[2]))
                                wait(2500)
                            end)
                        end
                    elseif follow.player_state == state.DRIVER then
                        if getDistanceFromTwoPoints2D(bX, bY, cdata[3].position.x, cdata[3].position.y) <= follow.min_dist * 5 then
                            clonePacketData(id, cdata[3])
                        end
                    end
                end
            end
        end
    end
end

-- ================= СОБЫТИЯ FOLLOW ЧЕРЕЗ SAMPEV (БЕЗ КОНФЛИКТА RPC) =================

function sampev.onPlayerQuit(playerId, reason)
    if playerId == follow.target_Id then
        follow.target_Id = -1
        fprint("Остановлено: ведущий игрок вышел с сервера.")
    end
end

function sampev.onPlayerChatBubble(playerId, color, distance, duration, message)
    if playerId == follow.target_Id and follow.bubble and message then
        sessionTask(function()
            wait(math.random(600, 1400))
            sendInput(message)
        end)
    end
end

function sampev.onVehicleStreamIn(vehicleId, data)
    if data and data.health then
        follow.veh_health_pool[vehicleId] = data.health
    end
end

function sampev.onPlayerEnterVehicle(playerId, vehicleId, passenger)
    if playerId == follow.target_Id and not passenger and follow.player_state == state.ONFOOT then
        local ok, vehiclePos = pcall(function() return getAllVehicles()[vehicleId].position end)
        if ok and vehiclePos then
            local bX, bY, _ = getBotPosition()
            if getDistanceFromTwoPoints2D(bX, bY, vehiclePos.x, vehiclePos.y) <= follow.min_dist and not GetTaskStatus(follow.temp_task) then
                follow.temp_task = sessionTask(function()
                    follow.player_state = state.PASSENGER
                    sendVehicleEnter(vehicleId, 1)
                    wait(500)
                    setBotVehicle(vehicleId, 1)
                    fprint("Сел пассажиром в авто ID: " .. tostring(vehicleId))
                    wait(2500)
                end)
            end
        end
    end
end

function sampev.onPlayerExitVehicle(playerId, vehicleId)
    if playerId == follow.target_Id and follow.player_state == state.PASSENGER and not GetTaskStatus(follow.temp_task) then
        follow.temp_task = sessionTask(function()
            sendVehicleExit(getBotVehicle())
            wait(500)
            setBotVehicle(0, 0)
            follow.player_state = state.ONFOOT
            fprint("Вышел из авто.")
        end)
    end
end

function sampev.onPlayerStreamOut(playerId)
    if playerId == follow.target_Id then
        if follow.player_state == state.PASSENGER and not GetTaskStatus(follow.temp_task) then
            follow.temp_task = sessionTask(function()
                sendVehicleExit(getBotVehicle())
                wait(500)
                setBotVehicle(0, 0)
                follow.player_state = state.ONFOOT
                fprint("Ведущий пропал из стрима, выхожу из авто.")
            end)
        end
    end
end

-- ================= ОБРАБОТКА SAMP ДИАЛОГОВ =================

function sampev.onShowDialog(id, style, title, button1, button2, text)
    cef_revision = cef_revision + 1
    cef_view = nil
    -- Network strings are CP1251; this source uses UTF-8 for matching.
    title, text = u8:encode(title), u8:encode(text)
    -- Очищаем текст и заголовок от цветовых HEX-тегов {FFFFFF} для надежной проверки
    local clean_title = title:gsub("%{......%}", "")
    local clean_text  = text:gsub("%{......%}", "")

    -- 1. Детект диалогов-проверок от администратора (/pm)
    local lower_text = clean_text:lower()
    if lower_text:find("вы тут") or lower_text:find("тут%?") or lower_text:find("ответьте")
       or clean_title:find("Администратор") or lower_text:find("напишите в") or lower_text:find("вы бот") then
        if stationary then print("[NOTICE] Manual attention required"); return end
        adminPanic("Диалог проверки от админа: " .. clean_text)
        return false
    end

    -- Stop password retries when the server rejects the credentials.
    if clean_text:find("Неверный пароль", 1, true) or clean_title:find("Этот аккаунт заблокирован", 1, true)
        or clean_text:find("аккаунт заблокирован", 1, true) then
        auth_blocked = true
        dialogs.reset()
        if login_watchdog then login_watchdog:kill() end
        print("[LOGIN] Authentication rejected; automatic replies stopped")
        return false
    end

    if (style == 1 or style == 3) and (clean_title:find("Авторизация", 1, true)
        or clean_text:find("Введите свой пароль", 1, true)) then
        -- Verification prompts may share the authorization title; never submit the password to them.
        local prompt = clean_title .. " " .. clean_text
        for _, marker in ipairs({"код", "Код", "КАПЧ", "капч", "Капч", "CAPTCHA", "Captcha", "captcha", "2FA"}) do
            if prompt:find(marker, 1, true) then
                print("[LOGIN] Verification requires manual input")
                return
            end
        end
        local pass = password()
        if pass then humanDialogResponse(id, 1, -1, pass) end
        return false
    end
    local registration_password = (style == 1 or style == 3) and (clean_title == "Пароль"
        or (clean_title:match("^%(%d+/%d+%)%s*Пароль$") and clean_text:find("Для регистрации введите пароль", 1, true))
        or (clean_title:find("Регистрация", 1, true) and clean_text:find("пароль", 1, true)))
    if registration_password then
        if dialog_settings.registration ~= true then
            print("[LOGIN] Registration paused: set [dialogs] registration=true and [settings] password in termuh/settings.txt, then restart")
        else
            local pass = password()
            if pass then humanDialogResponse(id, 1, -1, pass) end
        end
        return false
    end
    if dialog_settings.registration == true then
        if (style == 2 or style == 4 or style == 5) and (clean_title == "Выберите ваш пол"
            or clean_title == "Выберите цвет кожи" or clean_title == "Выбор пола"
            or clean_title:match("^%[%d+/%d+%]%s*Выберите ваш пол$")
            or clean_title:match("^%[%d+/%d+%]%s*Выберите цвет кожи$")) then
            humanDialogResponse(id, 1, 0, "")
            return false
        end
        if (style == 2 or style == 4 or style == 5) and clean_title:match("^%[%d+/%d+%]%s*Откуда вы о нас узнали%?$") then
            local index = 0
            for line in clean_text:gmatch("[^\r\n]+") do
                if line:find("На порталах/форумах", 1, true) then
                    humanDialogResponse(id, 1, index, "")
                    return false
                end
                index = index + 1
            end
        elseif clean_title == "Откуда вы о нас узнали" then
            humanDialogResponse(id, 1, 1, "")
            return false
        end
        if clean_title == "Введите ник пригласившего" then
            humanDialogResponse(id, 1, -1, ref)
            return false
        end
    end

    if stationary then return end

    -- 4. Диалог еды (/eat -> Чипсы)
    if eating_chips or clean_title:find("Еда") or clean_title:find("пищи") or clean_text:find("Чипсы") then
        if clean_text:find("Чипсы") then
            local i = 0
            for line in clean_text:gmatch("[^\r\n]+") do
                if not (style == 5 and i == 0) then
                    if line:find("Чипсы") then
                        local idx = (style == 5) and (i - 1) or i
                        eating_chips = false
                        humanDialogResponse(id, 1, idx, "", 500, 950)
                        return false
                    end
                end
                i = i + 1
            end
        elseif eating_chips then
            has_chips = false
            eating_chips = false
            humanDialogResponse(id, 0, 0, "", 400, 800)
            return false
        end
    end

    -- 5. Игровое меню (/mm) — подтверждение входа и ввод промокода
    if clean_title:find("Игровое меню") or clean_title:find("Главное меню") then
        if stationary then return end
        if not is_logged_in then
            is_logged_in = true
            checking_mm = false
            spawn_time = os.time()
            print("[LOGIN] Вход успешно подтвержден через /mm!")
        end

        if getBotScore() >= (tonumber(settings.promo_lvl) or 5) then
            local i = 0
            for line in clean_text:gmatch("[^\r\n]+") do
                if line:find("Промо%-код") then
                    if line:find("Не активирован") or not line:find("#") then
                        humanDialogResponse(id, 1, i, "", 600, 1100)
                        return false
                    end
                end
                i = i + 1
            end
        end

        humanDialogResponse(id, 0, 0, "", 450, 900)
        return false
    end

    if clean_text:find("Введите промо%-код") then
        humanDialogResponse(id, 1, 0, promo, 650, 1200)
        return false
    end

    if clean_text:find("Вы действительно хотите активировать") or clean_text:find("Вы активировали данный промо%-код") then
        humanDialogResponse(id, 1, 0, "", 500, 950)
        sendTG(("Промокод был введён. Ник: %s | АЙДИ: %s | Уровень: %s | Сервер: %s"):format(getBotNick(), getBotId(), getBotScore(), current_server))
        return false
    end

    -- Observed Arizona notice: the server only permits closing it after 10 seconds.
    if id == 15330 and style == 0 and clean_title == "Уведомление"
        and clean_text:find("поддержка клиента SAMP завершается", 1, true) then
        local generation = dialogs.generation
        sessionTask(function()
            wait(10500)
            if generation == dialogs.generation then humanDialogResponse(id, 1, -1, "") end
        end)
        return false
    end

    -- Only explicitly configured informational titles are dismissed.
    for skip_title in tostring(dialog_settings.skip_titles or ""):gmatch("[^|]+") do
        if style == 0 and clean_title == u8:encode(skip_title) then
            humanDialogResponse(id, button2 ~= "" and 0 or 1, -1, "")
            return false
        end
    end
    if clean_title == "Выбор места спавна" and dialog_settings.auto_spawn == true then
        humanDialogResponse(id, 1, tonumber(dialog_settings.spawn_index) or 0, "")
        return false
    end
end

-- ================= СПАВН И ТЕКСТДРАВЫ =================

function sampev.onRequestClassResponse(canSpawn, team, skin, unk, positon, rotation, weapons1, weapons2, weapons3)
    if canSpawn then
        sessionTask(function()
            wait(math.random(500, 900))
            sendSpawn()
        end)
    end
end

function sampev.onSendSpawn()
    if stationary then return end
    spawn_time = os.time()
    sessionTask(function()
        -- Плавное приземление при спавне для прохождения проверки гравитации
        wait(1200)
        emulateGravityDrop(0.3)

        wait(5000)
        checking_mm = true
        sendInput("/mm")

        wait(4500)
        if settings.present_code and tostring(settings.present_code) ~= "" then
            sendInput("/present " .. tostring(settings.present_code))
        end

        if getBotScore() >= (tonumber(settings.up_lvl) or 5) then
            writeTxt("termuh\\accounts\\good.txt", ("%s | %s | %s | %s | %s"):format(
                getBotNick(), tostring(settings.password), getBotScore(), current_server, my_proxy_ip
            ))
            sendTG(("Аккаунт успешно прокачен. Ник: %s | Уровень: %s | Сервер: %s"):format(
                getBotNick(), getBotScore(), current_server
            ))
            wait(300)
            if gen_nick then
                setRandomNick()
            else
                exit()
            end
        end
    end)
end

function sampev.onShowTextDraw(id, data)
    if stationary then return end
    if data.selectable and data.text == "selecticon3" and data.position.x == 233.0 and data.position.y == 337.0 then
        sessionTask(sendClickTextdraw, math.random(2500, 3500), id)
    end
    if data.modelId == 19196 and use_x3 then
        sessionTask(sendClickTextdraw, math.random(1800, 2600), id)
        use_x3 = false
    end
    if data.text == "USE" or data.text == "ИСПОЛЬЗОВАТЬ" or data.text == "ИCПOЛЬЗOВAТЬ" then
        sessionTask(sendClickTextdraw, math.random(1800, 2500), id + 1)
    end
end

-- ================= СООБЩЕНИЯ СЕРВЕРА И ЭВРИСТИКА ЧАТА =================

function sampev.onServerMessage(color, text)
    if stationary then return end
    text = u8:encode(text)
    local clean_text = text:gsub("%{......%}", "")
    local lower_text = clean_text:lower()

    -- 1. Эвристический детект проверок от Админа в чате (с обходом цветных тегов)
    if clean_text:find("телепортировал вас на координаты") or clean_text:find("Вы были телепортированы администратором") then
        adminPanic("Админ телепортировал по координатам")
        return
    end
    if clean_text:find("Администратор .+ написал вам:") or clean_text:find("%(%( Администратор")
       or ((lower_text:find("вы тут") or lower_text:find("тут%?") or lower_text:find("вы бот")) and not clean_text:find("%[Семья%]") and not clean_text:find("%[VIP")) then
        adminPanic("Проверка от админа в чате: " .. clean_text)
        return
    end

    -- 2. Голод и чипсы
    if clean_text:find("У вас нет с собой еды") or clean_text:find("У вас нет чипсов") then
        has_chips = false
        eating_chips = false
    end
    if (clean_text:find("Вы проголодались") or clean_text:find("Вы очень голодны")) and has_chips then
        eatChips()
    end

    -- 3. Выпадение X3 ускоренной прокачки
    if clean_text:find("Ускоренная прокачка %(X3%)") and clean_text:find("%/invent") then
        use_x3 = true
        sessionTask(function()
            wait(math.random(1200, 2500))
            sendInput("/invent")
        end)
    end

    -- 4. Наказания (Варн, Мут, Бан, Деморган)
    if clean_text:find("A%: (.+)%[(%d+)%] выдал предупреждение игроку (.+)%[(%d+)%] %[(%d+)%/(%d+)%] Причина%: (.+)") then
        local admnick, admid, playernick, playerid, warn1, warn2, reason = clean_text:match("A%: (.+)%[(%d+)%] выдал предупреждение игроку (.+)%[(%d+)%] %[(%d+)%/(%d+)%] Причина%: (.+)")
        if playernick == getBotNick() and tonumber(playerid) == getBotId() then
            sendTG(("Выдали варн.\nПричина: %s\nНик: %s\nСервер: %s"):format(reason, getBotNick(), current_server))
        end
    end

    if clean_text:find("A%: (.+)%[(%d+)%] заглушил игрока (.+)%[(%d+)%] на (%d+) минут%. Причина%: (.+)") then
        local admnick, admid, playernick, playerid, time, reason = clean_text:match("A%: (.+)%[(%d+)%] заглушил игрока (.+)%[(%d+)%] на (%d+) минут%. Причина%: (.+)")
        if playernick == getBotNick() and tonumber(playerid) == getBotId() then
            sendTG(("Выдали мут.\nПричина: %s\nНик: %s\nАЙДИ: %s\nСервер: %s"):format(reason, getBotNick(), getBotId(), current_server))
        end
    end

    if clean_text:find("A%: (.+)%[(%d+)%] забанил игрока (.+)%[(%d+)%] на (%d+) дней%. Причина%: (.+)") then
        local admnick, admid, playernick, playerid, time, reason = clean_text:match("A%: (.+)%[(%d+)%] забанил игрока (.+)%[(%d+)%] на (%d+) дней%. Причина%: (.+)")
        if playernick == getBotNick() and tonumber(playerid) == getBotId() then
            writeTxt("termuh\\accounts\\banned.txt", ("%s | %s | %s | %s | %s"):format(
                getBotNick(), tostring(settings.password), getBotScore(), current_server, my_proxy_ip
            ))
            sendTG(("Забанили.\nПричина: %s\nДлительность(дни): %s\nНик: %s\nСервер: %s"):format(reason, time, getBotNick(), current_server))
            if gen_nick then setRandomNick() end
        end
    end

    if clean_text:find("A%: (.+)%[(%d+)%] посадил игрока (.+)%[(%d+)%] в деморган на (%d+) минут%. Причина%: (.+)") then
        local adminnick, adminid, playernick, playerid, time, reason = clean_text:match("A%: (.+)%[(%d+)%] посадил игрока (.+)%[(%d+)%] в деморган на (%d+) минут%. Причина%: (.+)")
        if playernick == getBotNick() and tonumber(playerid) == getBotId() then
            sendTG(("Посадили в дмг.\nПричина: %s\nДлительность(минут): %s\nНик: %s\nАЙДИ: %s\nСервер: %s"):format(reason, time, getBotNick(), getBotId(), current_server))
        end
    end

    if clean_text:find("A%: (.+)%[(%d+)%] забанил игрока (.+)%[(%d+)%]%. Причина%: (.+)") then
        local adminnick, adminid, playernick, playerid, reason = clean_text:match("A%: (.+)%[(%d+)%] забанил игрока (.+)%[(%d+)%]%. Причина%: (.+)")
        if playernick == getBotNick() and tonumber(playerid) == getBotId() then
            writeTxt("termuh\\accounts\\banned.txt", ("%s | %s | %s | %s | %s"):format(
                getBotNick(), tostring(settings.password), getBotScore(), current_server, my_proxy_ip
            ))
            sendTG(("Забанили по ипу.\nПричина: %s\nНик: %s\nСервер: %s"):format(reason, getBotNick(), current_server))
            if settings.proxy then remove_bad_proxy() end
            if gen_nick then setRandomNick() end
        end
    end

    -- 5. PayDay и Повышение уровня
    if clean_text:find("Банковский чек") or clean_text:find("Для получения PayDay вы должны отыграть минимум (%d+) минут") then
        if settings.present_code and tostring(settings.present_code) ~= "" then
            sessionTask(function()
                wait(math.random(1500, 3500))
                sendInput("/present " .. tostring(settings.present_code))
            end)
        end
    end

    if clean_text:find("Поздравляем%! Вы достигли (%d+)%-го уровня%!") then
        local lvl = clean_text:match("Поздравляем%! Вы достигли (%d+)%-го уровня%!")
        sendTG(("Апнул %s лвл. Ник: %s | Сервер: %s"):format(lvl, getBotNick(), current_server))
        if tonumber(lvl) >= (tonumber(settings.promo_lvl) or 5) then
            sessionTask(function()
                wait(math.random(1500, 3000))
                sendInput("/mm")
            end)
        end
        if tonumber(lvl) >= (tonumber(settings.up_lvl) or 5) then
            writeTxt("termuh\\accounts\\good.txt", ("%s | %s | %s | %s | %s"):format(
                getBotNick(), tostring(settings.password), lvl, current_server, my_proxy_ip
            ))
            sendTG(("Аккаунт успешно прокачен. Ник: %s | Уровень: %s | Сервер: %s"):format(getBotNick(), lvl, current_server))
            if gen_nick then
                setRandomNick()
            else
                exit()
            end
        end
    end
end

-- ================= СИСТЕМНЫЕ СОБЫТИЯ И КОМАНДЫ КОНСОЛИ =================

function onRequestConnect()
    local max_attempts = math.max(1, math.floor(tonumber(settings.max_connect_attempts) or 5))
    if connection_attempts >= max_attempts then
        if not connection_blocked then
            print("[NETWORK] No session after " .. max_attempts .. " attempts; stopped. Check server/network; use !server NAME to retry")
            connection_blocked = true
        end
        return false
    end
    if gen_nick and getBotNick() == "nick" then return false end
    if not isProxyConnected() and settings.proxy then return false end
    if settings.http_preconnect ~= false and not settings.proxy and probe_target
        and getServerAddress() == probe_target and not probe_complete then
        if not probe_job then
            local ip = probe_target:match("^(%d+%.%d+%.%d+%.%d+):%d+$")
            local ok, job, err = pcall(preconnect.start, ip, walltime, 5000)
            if not ok or not job then
                probe_complete = true
                print("[HTTP] Could not start check; connecting normally")
            else
                probe_job = job
                print("[HTTP] Checking server on port 80 before connecting")
            end
        end
        if not probe_complete then return false end
    end
    connection_attempts = connection_attempts + 1
end

function onProxyError()
    if my_proxy_ip then
        sendTG("Не работает прокси (удаляю из пула). IP: " .. my_proxy_ip)
    end
    remove_bad_proxy()
end

local function selectServer(choice, reconnect_now)
    local server = catalog.find(choice)
    if not server then print("[SERVER] Unknown choice. Use !servers"); return false end
    if server.mobile then
        print("[SERVER] Mobile server requires a mobile client; this is a PC RakSAMP client")
        return false
    end
    local ip, err = runtime.resolveHost(server.host)
    if not ip then print("[SERVER] " .. err .. ": " .. server.host); return false end
    resetSession()
    resetProbe(true)
    probe_target = ip .. ":" .. server.port
    connection_attempts, connection_blocked = 0, false
    cef_packets, last_cef_view = 0, "none"
    setServerAddress(ip .. ":" .. server.port)
    current_server = server.name
    ref, promo = "", ""
    get_refpromo(current_server)
    print(("[SERVER] Selected %s (%s -> %s:%d)"):format(server.name, server.host, ip, server.port))
    if reconnect_now then reconnect(1500) end
    return true
end

function onLoad()
    if not cfg then
        print("[LOGIN] Cannot read termuh/settings.txt; start the EXE from the client folder")
    end
    if type(settings.password) ~= "string" or settings.password == "" then password() end
    print("[LOGIN] Native registration=" .. tostring(dialog_settings.registration == true))
    local selected_server = false
    if settings.server and settings.server ~= "" then
        selected_server = selectServer(settings.server, false)
    else
        local address = getServerAddress()
        -- Older hosts can expose a domain from the INI with port 0 until it is resolved.
        local host = address:match("^([^:]+):0$")
        local entry = catalog.find(address) or catalog.find(legacy_servers[address])
            or (host and (catalog.find(host) or catalog.find(legacy_servers[host .. ":7777"])))
        if entry then selected_server = selectServer(entry.id, false) end
    end
    -- 1. Инициализация AimSync Fix
    setRate(AIM_SYNC_RATE, 1000)
    print("[AimSync FIX] Загружен и объединен.")

    -- 2. Инициализация Follow
    setAutoPick(not stationary)
    print("[Follow] Загружен и объединен.")

    -- 3. Инициализация основного бота
    if getBotNick() == "nick" then
        gen_nick = true
        setRandomNick()
    end

    if not selected_server then
        get_server_name(getServerAddress())
        get_refpromo(current_server)
    end
    if token and chatid and effil_ok and json_ok then
        getLastUpdate()
        get_telegram_updates()
    end

    if settings.proxy then
        load_proxys("termuh\\proxy.txt")
        connect_random_proxy()
    end
end

function onRunCommand(cmd)
    if cmd == "!status" then
        print(("[STATUS] server=%s connected=%s attempts=%d HTTP=%s CEF-packets=%d view=%s"):format(
            current_server, tostring(isBotConnected()), connection_attempts, probe_complete and "done" or (probe_job and "pending" or "idle"), cef_packets, last_cef_view))
        return false
    elseif cmd == "!servers" then
        for _, server in ipairs(catalog.list) do
            print(("[SERVER] %d: %s%s"):format(server.id, server.name, server.mobile and " [mobile, incompatible]" or ""))
        end
        return false
    elseif cmd:match("^!server%s+(.+)$") then
        selectServer(cmd:match("^!server%s+(.+)$"), true)
        return false
    end
    if cmd == "!dialog" then
        print(("[DIALOG] active=%s id=%d style=%d"):format(tostring(dialogs.IsDialogActive()), dialogs.GetId(), dialogs.GetStyle()))
        return false
    elseif cmd:match("^!dialogreply [01] %-?%d+") then
        local button, index, input = cmd:match("^!dialogreply ([01]) (%-?%d+)%s?(.*)$")
        if button then humanDialogResponse(dialogs.GetId(), tonumber(button), tonumber(index), input) end
        return false
    end
    if cmd == "!newproxy" then
        remove_bad_proxy()
        return false
    elseif cmd == "!gennick" then
        setRandomNick()
        return false
    elseif cmd == "!eat" then
        if stationary then print("[STATIONARY] Disabled"); return false end
        eatChips()
        return false
    end

    if stationary and (cmd:match("^!follow") or cmd:match("^!enterveh") or cmd:match("^!exitveh") or cmd == "!eat") then
        print("[STATIONARY] This command is disabled in stationary mode")
        return false
    end

    -- Команды модуля Follow
    if cmd:match("^!follow .+") then
        local param = cmd:match("^!follow (.+)")
        if param:match("^%d+") then
            follow.target_Id = tonumber(param:match("^(%d+)"))
            fprint(string.format("Следование запущено за ID %d.", follow.target_Id))
        elseif param:match("^stop") then
            follow.target_Id = -1
            fprint("Следование остановлено.")
        elseif param:match("^bubble") then
            follow.bubble = not follow.bubble
            fprint(string.format("Повтор чата (bubble): %s.", follow.bubble and "ВКЛ" or "ВЫКЛ"))
        elseif param:match("^offset %-?%d+") then
            follow.offset = tonumber(param:match("^offset (%-?%d+)"))
            fprint(string.format("Новое смещение (offset): %d.", follow.offset))
        elseif param:match("^dist %-?%d+") then
            follow.min_dist = tonumber(param:match("^dist (%-?%d+)"))
            fprint(string.format("Новая дистанция (dist): %d.", follow.min_dist))
        end
        return false
    end

    if cmd:match("^!enterveh %d+") then
        local vehId = tonumber(cmd:match("^!enterveh (%d+)"))
        follow.temp_task = sessionTask(function()
            follow.target_Id = -1
            follow.player_state = state.DRIVER
            sendVehicleEnter(vehId, 0)
            wait(500)
            setBotVehicle(vehId, 0)
            fprint(string.format("Бот сел за руль авто ID %d", vehId))
        end)
        return false
    end

    if cmd:match("^!exitveh") then
        follow.temp_task = sessionTask(function()
            follow.target_Id = -1
            fprint(string.format("Бот вышел из авто ID %d.", getBotVehicle()))
            sendVehicleExit(getBotVehicle())
            wait(500)
            setBotVehicle(0, 0)
            follow.player_state = state.ONFOOT
        end)
        return false
    end
end

-- ================= TELEGRAM BOT API =================

function threadHandle(runner, url, args, resolve, reject)
    local t = runner(url, args)
    local r = t:get(0)
    while not r do
        r = t:get(0)
        wait(0)
    end
    local status = t:status()
    if status == "completed" then
        local ok, result = r[1], r[2]
        if ok then
            resolve(result)
        else
            reject(result)
        end
    elseif status == "canceled" then
        reject(status)
    end
    t:cancel(0)
end

function requestRunner()
    return effil.thread(function(u, a)
        local https = require("ssl.https")
        local ok, result = pcall(https.request, u, a)
        if ok then
            return {true, result}
        else
            return {false, result}
        end
    end)
end

function async_http_request(url, args, resolve, reject)
    local runner = requestRunner()
    reject = reject or function() end
    newTask(function()
        threadHandle(runner, url, args, resolve, reject)
    end)
end

function encodeUrl(str)
    str = str:gsub("([^%w%-%.%_%~%/])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

function sendTG(msg)
    if not token or not chatid or not effil_ok or not json_ok then return end
    msg = msg:gsub("{......}", "")
    msg = encodeUrl(msg)
    async_http_request("https://api.telegram.org/bot" .. token .. "/sendMessage?chat_id=" .. chatid .. "&text=" .. msg, "", function(result) end)
end

function get_telegram_updates()
    newTask(function()
        while not updateid do
            wait(100)
        end
        local runner = requestRunner()
        local reject = function() end
        local args = ""
        while true do
            local url = "https://api.telegram.org/bot" .. token .. "/getUpdates?chat_id=" .. chatid .. "&offset=-1"
            threadHandle(runner, url, args, processing_telegram_messages, reject)
            wait(3000 + math.random(500, 2500))
        end
    end)
end

local cmds = {
    "/bots - список всех ботов онлайн",
    "/recon (all/id) - перезайти на сервер",
    "/newproxy (all/id) - сменить прокси",
    "/eat (all/id) - съесть чипсы (/eat)",
    "/follow (bot_id) (target_id/stop) - бежать за игроком",
    "/send (id) (текст) - отправить команду/текст в чат",
    "/exit (all/id) - выйти с аккаунта(ов)",
    "/help - список команд",
}

function processing_telegram_messages(result)
    if not result or not json_ok then return end
    local ok, proc_table = pcall(json.decode, result)
    if not ok or not proc_table or not proc_table.ok then return end

    if #proc_table.result > 0 then
        local res_table = proc_table.result[1]
        if res_table and type(res_table.update_id) == "number" and res_table.update_id > (updateid or -1) then
            updateid = res_table.update_id
            local message_from_user = res_table.message and res_table.message.chat
                and tostring(res_table.message.chat.id) == chatid and res_table.message.text
            if message_from_user then
                local text = u8:decode(message_from_user)

                if text:find("^%/exit") then
                    local mode = text:match("^%/exit%s+(.+)")
                    if mode then
                        mode = mode:gsub("%s", "")
                        if mode == "all" or tonumber(mode) == getBotId() then
                            sendTG(("Вышел с аккаунта.\nНик: %s\nСервер: %s"):format(getBotNick(), current_server))
                            newTask(exit, 100)
                        end
                    else
                        sendTG("Используй: /exit (all/id)")
                    end

                elseif text:find("^%/recon") then
                    local mode = text:match("^%/recon%s+(.+)")
                    if mode then
                        mode = mode:gsub("%s", "")
                        if mode == "all" or tonumber(mode) == getBotId() then
                            sendTG(("Реконнект бота: %s | Сервер: %s"):format(getBotNick(), current_server))
                            reconnect(2000)
                        end
                    else
                        sendTG("Используй: /recon (all/id)")
                    end

                elseif text:find("^%/newproxy") then
                    local mode = text:match("^%/newproxy%s+(.+)")
                    if mode then
                        mode = mode:gsub("%s", "")
                        if mode == "all" or tonumber(mode) == getBotId() then
                            remove_bad_proxy()
                            sendTG(("Сменил прокси на %s | Бот: %s"):format(tostring(my_proxy_ip), getBotNick()))
                        end
                    else
                        sendTG("Используй: /newproxy (all/id)")
                    end

                elseif text:find("^%/eat") then
                    local mode = text:match("^%/eat%s+(.+)")
                    if mode then
                        mode = mode:gsub("%s", "")
                        if mode == "all" or tonumber(mode) == getBotId() then
                            eatChips()
                            sendTG(("Отправил /eat на боте: %s"):format(getBotNick()))
                        end
                    else
                        sendTG("Используй: /eat (all/id)")
                    end

                elseif text:find("^%/follow") then
                    local bot_id, target = text:match("^%/follow%s+(%d+)%s+(.+)")
                    if bot_id and target and tonumber(bot_id) == getBotId() then
                        target = target:gsub("%s", "")
                        if target == "stop" then
                            follow.target_Id = -1
                            sendTG(("Follow остановлен на боте %s"):format(getBotNick()))
                        elseif tonumber(target) then
                            follow.target_Id = tonumber(target)
                            sendTG(("Бот %s начал движение за игроком ID %d"):format(getBotNick(), follow.target_Id))
                        end
                    end

                elseif text:find("^%/send") then
                    local target_id, cmd_text = text:match("^%/send%s+(%d+)%s+(.+)")
                    if target_id and cmd_text then
                        if tonumber(target_id) == getBotId() then
                            sendInput(cmd_text)
                            sendTG(("Отправлено [%s]: %s"):format(getBotNick(), cmd_text))
                        end
                    else
                        sendTG("Используй: /send (id) (текст или команда)")
                    end

                elseif text:find("^%/bots") then
                    sendTG(("Ник: %s | ID: %s | ЛВЛ: %s | Сервер: %s | Прокси: %s"):format(
                        getBotNick(), getBotId(), getBotScore(), current_server, tostring(my_proxy_ip)
                    ))

                elseif text:find("^%/help") then
                    local str_cmds = table.concat(cmds, "\n")
                    sendTG("Команды бота:\n" .. str_cmds)
                end
            end
        end
    end
end

function getLastUpdate()
    local offset = -1
    async_http_request("https://api.telegram.org/bot" .. token .. "/getUpdates?chat_id=" .. chatid .. "&offset=" .. offset, "", function(result)
        if result then
            local ok, proc_table = pcall(json.decode, result)
            if ok and proc_table and proc_table.ok then
                if #proc_table.result > 0 and proc_table.result[1] then
                    updateid = proc_table.result[1].update_id
                else
                    updateid = offset + 1
                end
            end
        end
    end)
end
-- Attach once to the shared event dispatcher. Only selected Arizona PC servers qualify.
require('termuh-launcher').attach(sampev,
    function() return launcher_settings.enabled == true end,
    function()
        local address = getServerAddress()
        local server = catalog.find(address) or catalog.find(legacy_servers[address])
        if not server and address == probe_target then server = catalog.find(current_server) end
        return server ~= nil and server.id >= 1 and server.id <= 33 and not server.mobile
    end,
    function(callback) return newTask(callback) end,
    function() return require('termuh-launcher').ensureId('termuh\\launcher-id.txt') end)
-- Attach after Termuh callbacks have been declared; preserve their return values.
dialogs.attach(sampev)
if settings.panel == true then require("termuh-panel").start(runtime, sessionTask) end
