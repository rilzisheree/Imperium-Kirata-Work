--[[
	LanguageData.lua
	Shared ModuleScript — ReplicatedStorage

	Single source of truth for every grantable language.
	To add a new language, append one entry to LANGUAGES; everything else
	(fast lookups, command validation, translation calls) derives from it.

	Fields per entry:
	  name    — display name; used as the DataStore key and player-facing label
	  tag     — short prefix shown in chat, e.g. [K]
	  isoCode — ISO 639-1 code passed to the translation API
--]]

local LanguageData = {}

LanguageData.LANGUAGES = {
	{ name = "Korean",     tag = "K",  isoCode = "ko" },
	{ name = "Japanese",   tag = "JP", isoCode = "ja" },
	{ name = "Chinese",    tag = "CH", isoCode = "zh" },
	{ name = "French",     tag = "FR", isoCode = "fr" },
	{ name = "German",     tag = "DE", isoCode = "de" },
	{ name = "Spanish",    tag = "ES", isoCode = "es" },
	{ name = "Russian",    tag = "RU", isoCode = "ru" },
	{ name = "Turkish",    tag = "TR", isoCode = "tr" },
	{ name = "Portuguese", tag = "PT", isoCode = "pt" },
	{ name = "Italian",    tag = "IT", isoCode = "it" },
}

-- Fast lookup by lowercase name: LanguageData.BY_NAME["korean"] → { name, tag, isoCode }
LanguageData.BY_NAME = {}
for _, lang in ipairs(LanguageData.LANGUAGES) do
	LanguageData.BY_NAME[lang.name:lower()] = lang
end

return LanguageData
