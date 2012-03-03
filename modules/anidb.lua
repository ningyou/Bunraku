local simplehttp = require'simplehttp'
local xpath = require'xpath'
local lom = require'lxp.lom'
local zlib = require'zlib'
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

function _M:Queue(aid)
	local cache = Redis.connect('127.0.0.1', 6379)
	if not cache then
		return bunraku:Log('error', 'Unable to connect to cache database')
	end

	local aid = tonumber(aid)
	local key = "anidb:"..aid
	if cache:exists(key) and (cache:ttl(key) > 3600) then
		bunraku:Log('info', 'Cache already exists for: %s.', cache:hget(key, 'title'))
	elseif tableHasValue(_M.queue, id) then
		bunraku:Log('info', 'Request for AniDB id %s is already queued', aid)
	else
		table.insert(_M.queue, aid)
	end
	cache:quit()
end

function _M:Fetch(aid, forceupdate)
	local cache = Redis.connect('127.0.0.1', 6379)
	local aid = tonumber(aid)
	local anidbkey = "anidb:"..aid
	-- Create the hashkey
	cache:hset(anidbkey, "fetching", "true")
	simplehttp(
		('http://api.anidb.net:9001/httpapi?request=anime&aid=%d&client=bunraku&clientver=1&protover=1'):format(aid),
		function(data)
			local xml = zlib.inflate() (data)
			local xml_tree = lom.parse(xml)
			if xml_tree then
				local err = (xpath.selectNodes(xml_tree, '/error/text()')[1] or nil)
					if err then
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
					cache:hset(anidbkey, k, v)
				end

				cache:expire(anidbkey, 604800)
				cache:quit()
				bunraku:Log('info', 'Successfully added anime: %s.', input.title)
			else
				return bunraku:Log('error', 'Unable to parse XML')
			end
		end
	)
	cache:hdel(anidbkey, "fetching")
end

return _M
