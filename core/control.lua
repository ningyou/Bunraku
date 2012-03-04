local bunraku = ...

local nixio = require'nixio'
local ev = require'ev'
local pipe = '/tmp/bunraku.pipe'

local commands = {
	reload = function()
		bunraku:Reload()
	end,
	load = function(name)
		print("Loading: " .. name)
		bunraku:LoadModule(name)
	end,
	cachemem = function()
		local cache = Redis.connect('127.0.0.1', 6379)
		bunraku:Log('info', 'Cache memory in use/peak: %s/%s', cache:info()["used_memory_human"], cache:info()["used_memory_peak_human"])
		cache:quit()
	end,
}

nixio.fs.unlink(pipe)

local command = ev.Stat.new(function(loop, stat, revents)
	for line in io.lines() do
		local command, argument = line:match('^(%S+) ?(.*)$')
		if commands[command] then
			pcall(commands[command], argument)
		end
	end
end, pipe)

nixio.fs.mkfifo(pipe, 600)

os.execute(string.format('sleep .1 && touch %q &', pipe))
io.input(pipe)

return command
