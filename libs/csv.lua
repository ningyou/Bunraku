local lpeg = require'lpeg'

local field =
	lpeg.P(' ')^0
	* '"' * lpeg.Cs(((lpeg.P(1) - '"') + lpeg.P'""' / '"')^0) * '"'
	* lpeg.P(' ')^0
	+ lpeg.C((1 - lpeg.S',\t\n"')^0)

local record =
	lpeg.Ct(field * ((lpeg.P(',') + lpeg.P('\t')) * field)^0)
	* (lpeg.P'\n' + -1)

local csv = function(s)
	 return lpeg.match(record, s)
end

return csv
