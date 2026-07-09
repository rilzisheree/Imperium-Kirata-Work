-- All languages players can be granted.
-- Add a new entry here and everything else derives from it automatically.
local LanguageData = {}

LanguageData.LANGUAGES = {
	{ name = "Korean",     tag = "K"  },
	{ name = "Japanese",   tag = "JP" },
	{ name = "Chinese",    tag = "CH" },
	{ name = "French",     tag = "FR" },
	{ name = "German",     tag = "DE" },
	{ name = "Spanish",    tag = "ES" },
	{ name = "Russian",    tag = "RU" },
	{ name = "Turkish",    tag = "TR" },
	{ name = "Portuguese", tag = "PT" },
	{ name = "Italian",    tag = "IT" },
}

LanguageData.BY_NAME = {}
for _, lang in ipairs(LanguageData.LANGUAGES) do
	LanguageData.BY_NAME[lang.name:lower()] = lang
end

return LanguageData
