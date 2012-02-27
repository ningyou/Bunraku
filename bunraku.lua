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

local bunraku = {
	db = db,
	loop = loop,
}

local trim = function(s)
	return s:match('^()%s*$') and '' or s:match('^%s*(.*%S)')
end

function bunraku:HandleMsg(data)
	local parse = csv(data)
	if parse then
		local type = parse[1]
		for i = 2, #parse do
			print(type, trim(parse[i]))
		end
	end
end

function bunraku:EnableModule(mName, mTable)
end

function bunraku:LoadModule(mName)
	local mFile, mError = loadfile('modules/' .. mName.. '.lua')
	if not mFile then
		return
	end

	local env = {
		bunraku = self,
		package = package,
	}

	local proxy = setmetatable(env, { __index = _G })
	setfenv(mFile, proxy)

	local success, message = pcall(mFile, self)
	if not success then
	else
		self:EnableModule(mName, message)
	end
end

function bunraku:Reload()
	local coreFunc, coreError = loadfile'bunraku.lua'
	if not coreFunc then
		print(coreError)
		return
	end

	local success, message = pcall(coreFunc)
	if not success then
		print("Could not reload")
		return
	else
		self.control:stop(self.loop)
		self.s_io_idle:stop(self.loop)

		message.ctx = self.ctx
		message.socket = self.socket
		message.loop = self.loop
		message.db = self.db

		self = message

		self.control = assert(loadfile('core/control.lua'))(self)
		self.control:start(loop)

		self:Init()

		self.s_io_idle:start(loop)
		print("Successfully reloaded")
	end
end

function bunraku:Init()
	if not self.init then
		self.ctx = zmq.init(1)
		self.socket = self.ctx:socket(zmq.SUB)
		self.socket:setopt(zmq.SUBSCRIBE, "")
		self.socket:bind"ipc:///tmp/bunraku.sock"
	end

	if not self.control then
		self.control = assert(loadfile('core/control.lua'))(bunraku)
		self.control:start(loop)
	end

	self.init = true

	self.s_io_idle = ev.Idle.new(function()
		local msg, err = self.socket:recv(zmq.NOBLOCK)
		if err == "timeout" then
			self.s_io_idle:stop(loop)
			self.s_io_read:start(loop)
			return
		end
		self:HandleMsg(msg)
	end)

	self.s_io_read = ev.IO.new(function()
		self.s_io_idle:start(loop)
		self.s_io_read:stop(loop)
	end, 
	self.socket:getopt(zmq.FD), ev.READ)
end

return bunraku
