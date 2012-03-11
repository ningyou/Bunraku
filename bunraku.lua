package.path = table.concat({
	'libs/?/init.lua',
	'libs/?.lua',

	'',
}, ';') .. package.path

local zmq = require"zmq"
local mongo = require"mongo"
local ev = require"ev"
local csv = require"csv"
local loop = ev.Loop.default
local db = mongo.Connection.New()
local socket = require"socket"
require'logging.console'

local log = logging.console()
db:connect"localhost"

local bunraku = {
	db = db,
	loop = loop,
}

local safeFormat = function(format, ...)
	if select('#', ...) > 0 then
		local success, message = pcall(string.format, format, ...)
		if success then
			return message
		end
	else
		return format
	end
end

function bunraku:Log(level, ...)
	local message = safeFormat(...)

	if message then
		log[level](log, message)
	end
end

function bunraku:HandleMsg(data)
	local data = csv(data)
	if not data then
		return self:Log('error', 'Unable to parse CSV')
	end
	
	local mName = data[1]
	if not self[mName] then
		return self:Log('error', 'Trying to use module that is not loaded: %s', mName)
	end

	self[mName]:Queue(data)
end

function bunraku:LoadModule(mName)
	local mFile, mError = loadfile('modules/' .. mName.. '.lua')
	if not mFile then
		return self:Log('error', 'Unable to load module %s: %s.', mFile, mError)
	end

	local env = {
		bunraku = self,
		package = package,
	}

	local proxy = setmetatable(env, { __index = _G })
	setfenv(mFile, proxy)

	local success, message = pcall(mFile, self)
	if not success then
		self:Log('error', 'Unable to execute module %s: %s', mFile, message)
	else
		self[mName] = message
	end
end

function bunraku:LoadModules()
	if self.modules then
		for _, m in next, self.modules do
			self:LoadModule(m)
		end
	end
end

function bunraku:Reload()
	local coreFunc, coreError = loadfile'bunraku.lua'
	if not coreFunc then
		return self:Log('error', 'Unable to reload core: %s.', coreError)
	end

	local success, message = pcall(coreFunc)
	if not success then
		return self:Log('error', 'Unable to execute new core: %s.', message)
	else
		self.control:stop(self.loop)
		self.s_io_idle:stop(self.loop)

		message.ctx = self.ctx
		message.socket = self.socket
		message.loop = self.loop
		message.db = self.dbi
		message.modules = self.modules

		self = message

		self.control = assert(loadfile('core/control.lua'))(self)
		self.control:start(loop)

		self:Init()

		self.s_io_idle:start(loop)
		self:Log('info', 'Successfully reloaded core.')
	end
end

function bunraku:Init()
	if not self.init then
		self.modules = {
			"anidb",
			"moviedb",
		}
		
		self.ctx = zmq.init(1)
		self.socket = self.ctx:socket(zmq.SUB)
		self.socket:setopt(zmq.SUBSCRIBE, "")
		self.socket:bind"ipc:///tmp/bunraku.sock"
	end

	if not self.control then
		self.control = assert(loadfile('core/control.lua'))(bunraku)
		self.control:start(loop)
	end

	self.apikey = assert(loadfile('config/apikey.lua'))(bunraku)

	self.init = true

	self.s_io_idle = ev.Idle.new(function()
		local msg, err = self.socket:recv(zmq.NOBLOCK)
		if err then
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

	self:LoadModules()
end

return bunraku
