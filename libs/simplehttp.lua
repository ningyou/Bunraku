local httpclient = require"handler.http.client"
local uri = require"handler.uri"
local ev = require"ev"

local client = httpclient.new(ev.Loop.default)
local uri_parse = uri.parse

local function simplehttp(url, callback, visited)
	local visited = visited or {}
	local sink = {}

	client:request{
		url = url,

		on_data = function(request, response, data)
			if data then
				sink[#sink+1] = data
			end
		end,

		on_finished = function(req, res)
			if res.status_code == 301 or res.status_code == 302 then
				local location = res.headers.Location
				if location:sub(1,4) ~= "http" then
					local info = uri_parse(url)
					location = string.format("%s://%s/", info.scheme, info.host, location)
				end
				return simplehttp(location, callback, visited)
			end
			callback(table.concat(sink), url, response)
		end,
	}
end

return simplehttp
