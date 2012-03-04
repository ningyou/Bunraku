local simplehttp = require'simplehttp'
local ev = require'ev'
local loop = ev.Loop.default
local json = require'json'
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
		local key = "moviedb:"..id
		if cache:exists(key) and (cache:ttl(key) > 86400 or cache:ttl(key) == -1) and not force then
			bunraku:Log('info', 'Cache already exists for: %s.', cache:hget(key, 'name'))
		elseif tableHasValue(_M.queue, id) then
			bunraku:Log('info', 'Request for TheMovieDB id %s is already queued', id)
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
	local key = "moviedb:"..id
	simplehttp(
		('http://api.themoviedb.org/2.1/Movie.getInfo/en/json/%s/%d'):format(bunraku.apikey.moviedb,id),
		function(data)
			data = json.decode(data)[1]
			if not data then
				return bunraku:Log('error', 'Unable to parse JSON')
			end

			local input = {
				name = data.name,
				released = data.released,
				runtime = data.runtime,
				overview = data.overview,
				status = data.status,
				type = data.movie_type,
			}

			for k,v in next, input do
				cache:hset(key, k, v)
			end

			if not input.status == "Released" then
				cache:expire(key, 604800)
			else
				cache:persist(key)
			end

			cache:quit()
			bunraku:Log('info', 'Successfully added movie: %s.', input.name)
		end
	)
end

return _M

