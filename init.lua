local coreFunc, coreError = loadfile("bunraku.lua")
if not coreFunc then
	return
end

local success, message = pcall(coreFunc)
if not success then
	return
else
	bunraku = message
	bunraku:Init()

	bunraku.s_io_idle:start(bunraku.loop)
	bunraku.loop:loop()
end
