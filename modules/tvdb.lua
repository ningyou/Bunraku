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
			bunraku:Log('info', 'Request for TV Series id %s is already queued', id)
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
	local key = "tvdb:"..id
	
	if cache:exists(key) and (cache:ttl(key) > 86400 or cache:ttl(key) == -1) and not force then
		return bunraku:Log('info', 'Cache already exists for: %s.', cache:hget(key, 'title'))
	end

	simplehttp(
		('http://www.thetvdb.com/api/%s/series/%d/all/en.xml'):format(bunraku.apikey.tvdb, id),
		function(data)
			local xml_tree = lom.parse(data)

			if not xml_tree then
				return bunraku:Log('error', 'Unable to parse XML')
			end
			
			local err = xpath.selectNodes(xml_tree, '/error/text()')[1]
			if err then
				return bunraku:Log('error', err)
			end

			local ids = xpath.selectNodes(xml_tree, '/Data/Episode/id/text()')
			local seasons = xpath.selectNodes(xml_tree, '/Data/Episode[id='..ids[#ids]..']/SeasonNumber/text()')[1]
			local season = {}

			for i = 1, tonumber(seasons) do
				local st = xpath.selectNodes(xml_tree, '/Data/Episode[SeasonNumber='..i..']/')
				season[i] = #st
			end

			local input = {
				title = xpath.selectNodes(xml_tree, '/Data/Series/SeriesName/text()')[1],
				episodecount = xpath.selectNodes(xml_tree, '/Data/Episode[id='..ids[#ids]..']/absolute_number/text()')[1],
				description = xpath.selectNodes(xml_tree, '/Data/Series/Overview/text()')[1],
				status = xpath.selectNodes(xml_tree, '/Data/Series/Status/text()')[1],
				seasons = tonumber(seasons),
			}

			for k,v in next, season do
				cache:hset(key, "episodecount_season" .. k, v)
			end

			for k,v in next, input do
				cache:hset(key, k, v)
			end

			if input.status == "Continuing" then
				cache:expire(key, 604800)
			else
				cache:persist(key)
			end

			cache:quit()
			bunraku:Log('info', 'Successfully added TV series: %s.', input.title)
		end
	)
end

return _M
