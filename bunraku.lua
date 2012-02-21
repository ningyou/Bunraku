package.path = table.concat({
	'libs/?/init.lua',
	'libs/?.lua',

	'',
}, ';') .. package.path

local zmq = require"zmq"
local lpeg = require"lpeg"
local mongo = require"mongo"
local xpath = require"xpath"
local ev = require"ev"
local loop = ev.Loop.default
local csv = require"csv"
local db = mongo.Connection.New()
db:connect"localhost"

local trim = function(s)
	return s:match('^()%s*$') and '' or s:match('^%s*(.*%S)')
end

local handle_msg = function(data)
	local parse = csv(data)
	if parse then
		local type = parse[1]
		for i = 2, #parse do
			print(type, trim(parse[i]))
		end
	end
end

local ctx = zmq.init(1)
local s = ctx:socket(zmq.SUB)
s:setopt(zmq.SUBSCRIBE, "")
s:bind"ipc:///tmp/bunraku.sock"

local s_io_idle
local s_io_read

s_io_idle = ev.Idle.new(function()
	local msg, err = s:recv(zmq.NOBLOCK)
	if err == "timeout" then
		s_io_idle:stop(loop)
		s_io_read:start(loop)
		return
	end
	handle_msg(msg)
end)

s_io_idle:start(loop)

s_io_read = ev.IO.new(function()
	s_io_idle:start(loop)
	s_io_read:stop(loop)
end, s:getopt(zmq.FD), ev.READ)

loop:loop()
