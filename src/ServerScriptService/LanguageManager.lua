local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LanguageData = require(ReplicatedStorage:WaitForChild("LanguageData"))

local LanguageManager = {}

local DS_KEY_PREFIX = "player_"
local ds = DataStoreService:GetDataStore("PlayerLanguages_v1")

-- In-memory tables keyed by userId (number)
local playerGrants   = {}   -- [userId] = { "Korean", "Japanese", ... }
local playerSelected = {}   -- [userId] = "Korean" | nil  (nil = English / none)

local function loadGrants(userId: number): { string }
	local ok, result = pcall(function()
		return ds:GetAsync(DS_KEY_PREFIX .. userId)
	end)
	if ok and type(result) == "string" then
		local decOk, decoded = pcall(HttpService.JSONDecode, HttpService, result)
		if decOk and type(decoded) == "table" then
			local clean = {}
			for _, v in ipairs(decoded) do
				if type(v) == "string" and LanguageData.BY_NAME[v:lower()] then
					table.insert(clean, LanguageData.BY_NAME[v:lower()].name)
				end
			end
			return clean
		end
	end
	return {}
end

local function saveGrants(userId: number, grants: { string })
	pcall(function()
		ds:SetAsync(DS_KEY_PREFIX .. userId, HttpService:JSONEncode(grants))
	end)
end

function LanguageManager.onPlayerAdded(player: Player)
	local grants = loadGrants(player.UserId)
	playerGrants[player.UserId]   = grants
	playerSelected[player.UserId] = nil
end

function LanguageManager.onPlayerRemoving(player: Player)
	playerGrants[player.UserId]   = nil
	playerSelected[player.UserId] = nil
end

function LanguageManager.getGrants(userId: number): { string }
	return playerGrants[userId] or {}
end

-- Whether the player has been granted the given language, regardless of
-- whether they currently have it selected as their active speaking language.
function LanguageManager.hasGrant(userId: number, langName: string): boolean
	local lower = langName:lower()
	local grants = playerGrants[userId]
	if not grants then return false end
	for _, g in ipairs(grants) do
		if g:lower() == lower then
			return true
		end
	end
	return false
end

function LanguageManager.getSelected(userId: number): string?
	return playerSelected[userId]
end

function LanguageManager.setSelected(userId: number, langName: string?)
	playerSelected[userId] = langName
end

function LanguageManager.grantLanguage(userId: number, langName: string): (boolean, string)
	local lower = langName:lower()
	if lower == "english" then
		return false, "English is available to all players by default."
	end
	local lang = LanguageData.BY_NAME[lower]
	if not lang then
		return false, 'Unknown language "' .. langName .. '".'
	end

	local grants = playerGrants[userId] or {}
	for _, g in ipairs(grants) do
		if g:lower() == lower then
			return false, "already_granted"
		end
	end

	local newGrants = table.clone(grants)
	table.insert(newGrants, lang.name)
	playerGrants[userId] = newGrants
	task.spawn(saveGrants, userId, newGrants)
	return true, lang.name
end

-- chars = source glyph pool, ratio = output chars per input letter
local SCRIPT_DEFS = {

	Korean = {
		chars = {
			"가","나","다","라","마","바","사","아","자","차","카","타","파","하",
			"갸","냐","댜","랴","먀","뱌","샤","야","쟈","챠","캬","탸","퍄","햐",
			"봐","봬","뫄","뭐",
			"기","니","디","리","미","비","시","이","지","치","키","티","피","히",
			"고","노","도","로","모","보","소","오","조","초","코","토","포","호",
			"교","뇨","됴","료","묘","뵤","쇼","요","죠","쵸","쿄","툐","표","효",
			"구","누","두","루","무","부","수","우","주","추","쿠","투","푸","후",
			"규","뉴","듀","류","뮤","뷰","슈","튜","퓨","휴",
			"게","네","데","레","메","베","세","에","제","체","케","테","페","헤",
			"겨","녀","려","며","벼","셔","여","져","쳐","켜","텨","펴","혀",
			"셰","녜","례","몌","볘","예","졔","쳬","켸","혜",
			"강","당","랑","망","방","상","앙","장","창","캉","탕","팡","항",
			"건","던","런","먼","번","선","언","전","천","켄","텐","펜","헨",
			"길","닐","딜","릴","밀","빌","실","일","질","칠","킬","틸","필","힐",
			"칸","탄","판","한","간","난","단","란","만","반","산","안","잔","찬",
			"곰","놈","돔","롬","몸","봄","솜","욤","줌","춤","쿰","툼","품","홈",
			"린","민","빈","신","인","진","친","킨","틴","핀","힌","긴","닌","딘",
			"락","막","박","삭","악","작","착","탁","팍","학","각","낙","닥","랙",
		},
		ratio = 0.5,
	},

	Japanese = {
		chars = {
			"あ","い","う","え","お",
			"か","き","く","け","こ",
			"さ","し","す","せ","そ",
			"た","ち","つ","て","と",
			"な","に","ぬ","ね","の",
			"は","ひ","ふ","へ","ほ",
			"ま","み","む","め","も",
			"や","ゆ","よ",
			"ら","り","る","れ","ろ",
			"わ","を","ん",
			"が","ぎ","ぐ","げ","ご",
			"ざ","じ","ず","ぜ","ぞ",
			"だ","ぢ","づ","で","ど",
			"ば","び","ぶ","べ","ぼ",
			"ぱ","ぴ","ぷ","ぺ","ぽ",
			"きゃ","きゅ","きょ",
			"しゃ","しゅ","しょ",
			"ちゃ","ちゅ","ちょ",
			"にゃ","にゅ","にょ",
			"ひゃ","ひゅ","ひょ",
			"みゃ","みゅ","みょ",
			"りゃ","りゅ","りょ",
			"ぎゃ","ぎゅ","ぎょ",
			"じゃ","じゅ","じょ",
			"びゃ","びゅ","びょ",
			"ぴゃ","ぴゅ","ぴょ",
			"あ","い","う","え","お","あ","い","う","え","お",
		},
		ratio = 0.6,
	},

	Chinese = {
		chars = {
			"勃","仵","呖","咣","哔","嗖","啰","唻","呔","吒",
			"幺","夯","廾","弋","仨","佤","侏","倥","偌","儡",
			"刖","剌","剽","劬","勠","勹","匦","卮","厝","叽",
			"吣","吡","呙","哙","哝","嗤","嘌","噶","嚯","嗯",
			"圩","圬","圮","坂","坞","垠","堰","塬","墟","壑",
			"夭","奁","妁","妞","姝","娌","婀","媪","嫣","嬷",
			"孑","孓","孢","孳","宥","宸","寤","寥","寰","尬",
			"岵","峁","峻","崆","嵯","嵘","巅","巍","巉","巫",
			"怦","恁","恙","悃","悒","惘","愀","愆","慝","懋",
			"拗","挲","揆","搠","摭","撙","擀","攒","攫","攮",
			"泫","洌","浃","涔","淠","渫","溽","澹","濡","瀣",
			"犷","猱","猢","獒","玎","珑","琅","瑷","璀","瓒",
			"穑","窦","竦","笺","筮","篑","簸","籁","糌","缱",
			"羁","翊","翎","聒","肫","胨","腠","膂","臧","舻",
			"芾","苒","茌","荸","莩","菝","葚","蒡","蓼","蔺",
			"觇","觋","觚","觜","觞","觥","觳","訇","诹","谮",
		},
		ratio = 0.4,
	},

	Russian = {
		chars = {
			"а","е","и","о","у","э","ю","я","ё",
			"а","е","и","о","у","э","ю","я",
			"а","е","и","о","у",
			"б","в","г","д","ж","з","й","к","л","м",
			"н","п","р","с","т","ф","х","ц","ч","ш","щ",
		},
		ratio = 1.0,
	},

	French = {
		chars = {
			"a","e","i","o","u","n","r","s","t","l","c","d","m","p",
			"é","è","ê","ë","à","â","î","ï","ô","ù","û","ü","ç","œ","æ",
			"é","è","ê","à","â","î","ô","ù","ç","œ",
			"b","f","g","h","j","q","v","x","y","z",
		},
		ratio = 1.0,
	},

	German = {
		chars = {
			"a","e","i","o","u","n","r","s","t","l","c","d","m","p",
			"ä","ö","ü","ß",
			"ä","ö","ü","ß",
			"b","f","g","h","k","q","v","w","x","y","z",
		},
		ratio = 1.0,
	},

	Spanish = {
		chars = {
			"a","e","i","o","u","n","r","s","t","l","c","d","m","p",
			"á","é","í","ó","ú","ñ","ü",
			"á","é","í","ó","ú","ñ",
			"b","f","g","h","j","k","q","v","w","x","y","z",
		},
		ratio = 1.0,
	},

	Portuguese = {
		chars = {
			"a","e","i","o","u","n","r","s","t","l","c","d","m","p",
			"ã","õ","â","ê","ô","à","á","é","í","ó","ú","ç",
			"ã","õ","â","ô","á","é","ó","ç",
			"b","f","g","h","j","k","q","v","w","x","y","z",
		},
		ratio = 1.0,
	},

	Italian = {
		chars = {
			"a","e","i","o","u","n","r","s","t","l","c","d","m","p",
			"à","è","é","ì","í","ò","ó","ù",
			"à","è","é","ì","ò","ù",
			"b","f","g","h","k","q","v","w","x","y","z",
		},
		ratio = 1.0,
	},

	Turkish = {
		chars = {
			"a","e","i","o","u","n","r","s","t","l","c","d","m","p",
			"ğ","ş","ı","ü","ö","ç",
			"ğ","ş","ı","ü","ö","ç",
			"b","f","g","h","k","q","v","w","x","y","z",
		},
		ratio = 1.0,
	},
}

local function utf8CharLen(firstByte: number): number
	if firstByte < 0x80 then return 1 end
	if firstByte < 0xE0 then return 2 end
	if firstByte < 0xF0 then return 3 end
	return 4
end

local function generateFakeWord(letterCount: number, def: { chars: { string }, ratio: number }): string
	local outputCount = math.max(1, math.round(letterCount * def.ratio))
	local pool = def.chars
	local poolSize = #pool
	local parts = table.create(outputCount)
	for i = 1, outputCount do
		parts[i] = pool[math.random(1, poolSize)]
	end
	return table.concat(parts)
end

-- replaces ascii letters with glyphs from the target script, leaves everything else alone
function LanguageManager.fictionalise(text: string, langName: string): string
	local def = SCRIPT_DEFS[langName]
	if not def then return text end

	local result = {}
	local pos    = 1
	local len    = #text

	while pos <= len do
		local byte = text:byte(pos)

		-- ASCII letter — collect the full contiguous run, then fictionalise it.
		if (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) then
			local runStart = pos
			pos = pos + 1
			while pos <= len do
				local b = text:byte(pos)
				if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
					pos = pos + 1
				else
					break
				end
			end
			local letterCount = pos - runStart
			table.insert(result, generateFakeWord(letterCount, def))

		else
			-- Non-letter byte — step over the full UTF-8 character and copy it.
			local charLen = utf8CharLen(byte)
			table.insert(result, text:sub(pos, pos + charLen - 1))
			pos = pos + charLen
		end
	end

	return table.concat(result)
end

return LanguageManager
