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
