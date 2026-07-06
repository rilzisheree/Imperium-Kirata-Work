--[[
	MarkdownParser
	Shared module — ReplicatedStorage

	Converts a subset of Markdown to Roblox RichText tags for use with
	TextLabel/TextBox instances that have RichText = true.

	Supported syntax:
	  ***text***  →  bold + italic   <b><i>text</i></b>
	  **text**    →  bold            <b>text</b>
	  *text*      →  italic          <i>text</i>
	  __text__    →  underline       <u>text</u>
	  ~~text~~    →  strikethrough   <s>text</s>

	Rules:
	  • Multiple formats may appear in the same message.
	  • Nesting works (e.g. **outer *inner* text**) because rules run in
	    sequence on the full string — inner markers are processed in a later pass.
	  • Unmatched / incomplete markers are left as-is so nothing breaks.
	  • The raw string is XML-escaped before any substitution so user input
	    cannot inject arbitrary RichText tags.
--]]

local MarkdownParser = {}

-- Characters that must be escaped inside a Roblox RichText string.
local XML_ESC = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

---Convert a raw user string to a Roblox-safe RichText string with Markdown
---formatting applied.  If the input contains no recognised Markdown the
---return value is simply the XML-escaped plain text.
---@param raw string
---@return string
---Return the visible text that would result from parsing `raw`, with all
---markdown markers removed but no RichText tags added.  Use this when you
---need to measure the rendered width/height of a string without a live label
---(e.g. pre-calculating a bubble pill width).
---@param raw string
---@return string
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

---Convert a raw user string to a Roblox-safe RichText string with Markdown
---formatting applied.  If the input contains no recognised Markdown the
---return value is simply the XML-escaped plain text.
---@param raw string
---@return string
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
