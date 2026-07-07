--[[
	LanguageData.lua
	Shared ModuleScript — ReplicatedStorage

	Single source of truth for every grantable language.
	To add a new language, append one entry to LANGUAGES; everything else
	(fast lookups, command validation, fictionalisation) derives from it.

	Fields per entry:
	  name — display name; used as the DataStore key and player-facing label
	  tag  — short prefix shown in chat, e.g. [K]
--]]

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

-- Fast lookup by lowercase name: LanguageData.BY_NAME["korean"] → { name, tag }
LanguageData.BY_NAME = {}
for _, lang in ipairs(LanguageData.LANGUAGES) do
	LanguageData.BY_NAME[lang.name:lower()] = lang
end

return LanguageData
