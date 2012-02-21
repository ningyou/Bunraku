package.path = table.concat({
	'libs/?/init.lua',
	'libs/?.lua',

	'',
}, ';') .. package.path

local zmq = require"zmq"
local lpeg = require"lpeg"
local mongo = require"mongo"
local xpath = require"xpath"

local db = mongo.Connection.New()
db:connect"localhost"


local field =
	lpeg.P(' ')^0
	* '"' * lpeg.Cs(((lpeg.P(1) - '"') + lpeg.P'""' / '"')^0) * '"'
	* lpeg.P(' ')^0
	+ lpeg.C((1 - lpeg.S',\t\n"')^0)

local record =
	lpeg.Ct(field * ((lpeg.P(',') + lpeg.P('\t')) * field)^0)
	* (lpeg.P'\n' + -1)

local csv = function(s)
	 return lpeg.match(record, s)
end

local fetch = function(type, title)
	-- Placeholder stub
	return
end

local trim = function(s)
	return s:match('^()%s*$') and '' or s:match('^%s*(.*%S)')
end

local ctx = zmq.init(1)
local s = ctx:socket(zmq.SUB)
s:setopt(zmq.SUBSCRIBE, "")
s:bind"ipc:///tmp/bunraku.sock"

while true do
	local recv_csv = s:recv()
	local parse = csv(recv_csv)
	if parse then
		local type = parse[1]
		for i = 2, #parse do
			fetch(type, parse[i])
		end
	end
end
