local simplehttp = require'simplehttp'
local xpath = require'xpath'
local lom = require'lxp.lom'
local zlib = require'zlib'
require'redis'

local _M = {}

function _M:Fetch(aid)
	local cache = Redis.connect('127.0.0.1', 6379)
	local aid = tonumber(aid)
	if cache:exists("anidb:"..aid) then
		print("Cache already exists for id: " ..aid)
		return
	else
		print("Fetching anime with id: ".. aid)
		simplehttp(
			('http://api.anidb.net:9001/httpapi?request=anime&aid=%d&client=ivarto&clientver=0&protover=1'):format(aid),
			function(data)
				local xml = zlib.inflate() (data)
				local xml_tree = lom.parse(xml)
				if xml_tree then
					local input = {
						episodecount = (xpath.selectNodes(xml_tree, '/anime/episodecount/text()')[1] or nil),
						description = (xpath.selectNodes(xml_tree, '/anime/description/text()')[1] or nil),
						startdate = (xpath.selectNodes(xml_tree, '/anime/startdate/text()')[1] or nil),
						enddate = (xpath.selectNodes(xml_tree, '/anime/enddate/text()')[1] or nil),
						type = (xpath.selectNodes(xml_tree, '/anime/type/text()')[1] or nil),
					}
					
					for k,v in next, input do
						cache:hset("anidb:"..aid, k, v)
					end

					cache:expire("anidb:"..aid, 604800)
					print("Successfully added anime with id: " .. aid)
				else
					print("Could not parse xml")
					return
				end
			end
		)
	end
end

return _M
