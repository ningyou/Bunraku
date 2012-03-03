local simplehttp = require'simplehttp'
local xpath = require'xpath'
local lom = require'lxp.lom'
local zlib = require'zlib'
require'redis'

local _M = {}
_M.queue = {}

_M.timer = ev.Timer.new(function(loop, timer, revents)
	if _M.queue[1] then
		_M:Fetch(_M.queue[1])
		table.remove(_M.queue, 1)
	else
		timer:stop(loop)
	end
end, 2, 2)

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
					title = (xpath.selectNodes(xml_tree, '/anime/titles/title[@type="main"]/text()')[1] or nil),
					episodecount = (xpath.selectNodes(xml_tree, '/anime/episodecount/text()')[1] or nil),
					description = (xpath.selectNodes(xml_tree, '/anime/description/text()')[1] or nil),
					startdate = (xpath.selectNodes(xml_tree, '/anime/startdate/text()')[1] or nil),
					enddate = (xpath.selectNodes(xml_tree, '/anime/enddate/text()')[1] or nil),
					type = (xpath.selectNodes(xml_tree, '/anime/type/text()')[1] or nil),
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
