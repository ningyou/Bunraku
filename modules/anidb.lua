local simplehttp = require'simplehttp'
local xpath = require'xpath'
local lom = require'lxp.lom'
local zlib = require'zlib'
local ev = require'ev'
local loop = ev.Loop.default
require'redis'

local _M = {}
_M.queue = {}

local tableHasValue = function(table, value)
	if type(table) ~= 'table' then return end

	for _,v in next, table do
		if v == value then return true end
	end
end

_M.timer = ev.Timer.new(function(loop, timer, revents)
	if _M.queue[1] then
		_M:Fetch(table.remove(_M.queue, 1))
	else
		timer:stop(loop)
	end
end, 2, 2)

function _M:Queue(data, force)
	local cache = Redis.connect('127.0.0.1', 6379)
	if not cache:ping() then
		return bunraku:Log('error', 'Unable to connect to cache database')
	end
	
	for i = 2, #data do
		local id = tonumber(data[i])
		local key = "anidb:"..id
		if cache:exists(key) and (cache:ttl(key) > 86400 or cache:ttl(key) == -1) and not force then
			bunraku:Log('info', 'Cache already exists for: %s.', cache:hget(key, 'title'))
		elseif tableHasValue(_M.queue, id) then
			bunraku:Log('info', 'Request for AniDB id %s is already queued', id)
		else
			table.insert(_M.queue, id)
		end
	end
	if _M.queue[1] and not _M.timer:is_active() then
		_M.timer:start(loop)
	end
	cache:quit()
end

function _M:Fetch(id)
	local cache = Redis.connect('127.0.0.1', 6379)
	local id = tonumber(id)
	local key = "anidb:"..id
	
	if cache:exists(key) and (cache:ttl(key) > 86400 or cache:ttl(key) == -1) and not force then
		return bunraku:Log('info', 'Cache already exists for: %s.', cache:hget(key, 'title'))
	end

	simplehttp(
		('http://api.anidb.net:9001/httpapi?request=anime&aid=%d&client=bunraku&clientver=1&protover=1'):format(id),
		function(data)
			local xml = zlib.inflate() (data)
			local xml_tree = lom.parse(xml)

			if not xml_tree then
				return bunraku:Log('error', 'Unable to parse XML')
			end
			
			local err = xpath.selectNodes(xml_tree, '/error/text()')[1]
			if err then
				if err == "Anime not found" then
					cache:hset(key, "error", "Not Found")
					cache:expire(key, 172800)
				elseif err == "Banned" then
					_M.queue = nil
					_M.queue = {}
					_M.timer:stop(loop)
				end
				return bunraku:Log('error', err)
			end

			local input = {
				title = xpath.selectNodes(xml_tree, '/anime/titles/title[@type="main"]/text()')[1],
				episodecount = xpath.selectNodes(xml_tree, '/anime/episodecount/text()')[1],
				description = xpath.selectNodes(xml_tree, '/anime/description/text()')[1],
				startdate = xpath.selectNodes(xml_tree, '/anime/startdate/text()')[1],
				enddate = xpath.selectNodes(xml_tree, '/anime/enddate/text()')[1],
				type = xpath.selectNodes(xml_tree, '/anime/type/text()')[1],
			}

			for k,v in next, input do
				cache:hset(key, k, v)
			end

			if not input.enddate then
				cache:expire(key, 604800)
			else
				cache:persist(key)
			end

			cache:quit()
			bunraku:Log('info', 'Successfully added anime: %s.', input.title)
		end
	)
end

return _M
