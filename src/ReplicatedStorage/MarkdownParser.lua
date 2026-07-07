local MarkdownParser = {}

-- Characters that must be escaped inside a Roblox RichText string.
local XML_ESC = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

function MarkdownParser.stripMarkers(raw: string): string
	if raw == "" then return "" end
	local s = raw
	s = s:gsub("%*%*%*(.-)%*%*%*", "%1")  -- ***…*** → content only
	s = s:gsub("%*%*(.-)%*%*",     "%1")  -- **…**   → content only
	s = s:gsub("%*(.-)%*",         "%1")  -- *…*     → content only
	s = s:gsub("__(.-)__",         "%1")  -- __…__   → content only
	s = s:gsub("~~(.-)~~",         "%1")  -- ~~…~~   → content only
	return s
end

function MarkdownParser.toRichText(raw: string): string
	if raw == "" then return "" end

	-- 1. XML-escape: user text must not be able to inject RichText tags.
	local s = raw:gsub('[&<>"]', XML_ESC)

	-- 2. Markdown substitutions, most-specific first so longer delimiters are
	--    consumed before shorter ones that share a prefix (*** before ** before *).
	--    `.-` is Lua's lazy (non-greedy) quantifier, so each pair of delimiters
	--    matches the shortest possible span, giving correct multi-instance behaviour.
	--    Unmatched delimiters produce no match and are left unchanged.

	s = s:gsub("%*%*%*(.-)%*%*%*", "<b><i>%1</i></b>")  -- bold italic  ***…***
	s = s:gsub("%*%*(.-)%*%*",     "<b>%1</b>")          -- bold         **…**
	s = s:gsub("%*(.-)%*",         "<i>%1</i>")           -- italic       *…*
	s = s:gsub("__(.-)__",         "<u>%1</u>")           -- underline    __…__
	s = s:gsub("~~(.-)~~",         "<s>%1</s>")           -- strikethrough ~~…~~

	return s
end

return MarkdownParser
