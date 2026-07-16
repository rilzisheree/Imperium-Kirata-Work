-- Second-pass filter on top of Roblox's TextService (which is tuned for
-- legal compliance, not for blocking every known slur). Runs even if the
-- Roblox filter call fails. Matching is whole-word only so substrings like
-- "assassin", "class", or the name "Dick" are never touched.
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

-- build a set so lookup is O(1) rather than scanning the list per word
local BAD_WORD_SET = {}
for _, word in BAD_WORDS do
	BAD_WORD_SET[word] = true
end

function BadWordFilter.containsBadWord(text: string): boolean
	if text == "" then return false end
	for word in text:gmatch("%f[%a][%a']+%f[%A]") do
		if BAD_WORD_SET[word:lower()] then
			return true
		end
	end
	return false
end

-- replaces matches with asterisks of the same length, for callers that want
-- per-word masking instead of blocking the whole message
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
