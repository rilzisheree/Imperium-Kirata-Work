local MarkdownParser = {}

-- Characters that must be escaped inside a Roblox RichText string.
local XML_ESC = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

function MarkdownParser.stripMarkers(raw: string): string
	if raw == "" then return "" end
	local s = raw
	s = s:gsub("%*%*%*(.-)%*%*%*", "%1")
	s = s:gsub("%*%*(.-)%*%*",     "%1")
	s = s:gsub("%*(.-)%*",         "%1")
	s = s:gsub("__(.-)__",         "%1")
	s = s:gsub("~~(.-)~~",         "%1")
	return s
end

function MarkdownParser.toRichText(raw: string): string
	if raw == "" then return "" end

	local s = raw:gsub('[&<>"]', XML_ESC)

	s = s:gsub("%*%*%*(.-)%*%*%*", "<b><i>%1</i></b>")  -- bold italic  ***…***
	s = s:gsub("%*%*(.-)%*%*",     "<b>%1</b>")          -- bold         **…**
	s = s:gsub("%*(.-)%*",         "<i>%1</i>")           -- italic       *…*
	s = s:gsub("__(.-)__",         "<u>%1</u>")           -- underline    __…__
	s = s:gsub("~~(.-)~~",         "<s>%1</s>")           -- strikethrough ~~…~~

	return s
end

return MarkdownParser
