-- Custom supplementary profanity filter.
--
-- Roblox's built-in TextService filter intentionally lets a lot of language
-- through (it's tuned for legal/age-rating compliance, not for blocking every
-- swear word), and it can occasionally fail to return a result at all. This
-- module is a second layer that runs AFTER Roblox's official filter (and even
-- if that filter call fails) so known bad words never reach chat.
--
-- Matching is whole-word only (via Lua frontier patterns), so this never
-- touches unrelated words or substrings, e.g. "assassin", "class", "grass",
-- or the name "Dick" are left alone.
local BadWordFilter = {}

local BAD_WORDS = {
	"fuck", "fucking", "fucker", "fuckers", "fucked", "fuckin", "fuckboy",
	"shit", "shitty", "shithead", "bullshit", "shits",
	"bitch", "bitches", "bitchy",
	"cunt", "cunts",
	"pussy", "pussies",
	"whore", "whores",
	"slut", "sluts",
	"bastard", "bastards",
	"asshole", "assholes",
	"dickhead", "dickheads",
	"cock", "cocks",
	"piss", "pissed", "pissing",
	"nigger", "niggers", "nigga", "niggas",
	"faggot", "faggots", "fag", "fags",
	"retard", "retarded", "retards",
}

-- Build a lookup set once so censoring is O(1) per word instead of scanning
-- the whole list for every word in a message.
local BAD_WORD_SET = {}
for _, word in BAD_WORDS do
	BAD_WORD_SET[word] = true
end

-- Replaces every whole-word match (case-insensitive) with asterisks of the
-- same length, preserving message length/spacing.
function BadWordFilter.censor(text: string): string
	if text == "" then return text end
	local censored = text:gsub("%f[%a][%a']+%f[%A]", function(word: string)
		if BAD_WORD_SET[word:lower()] then
			return string.rep("*", #word)
		end
		return word
	end)
	return censored
end

return BadWordFilter
