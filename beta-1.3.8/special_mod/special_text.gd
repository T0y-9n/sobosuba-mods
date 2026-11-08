extends RefCounted

const WORDS: Dictionary = {
	"magnet pull": {
		"en": "magnet pull x (0-20)",
		"ja": "磁石の引力（0〜20倍）",
	},
	"magnet pull description": {
		"en": "Type a multiplier and press Enter, or leave the field, to save and apply it now. Decimals are allowed. Magnet repulsion stays the same.",
		"ja": "倍率を入力し、Enterか欄を離れる操作で保存して今の盤面に反映。小数も使えます。磁石同士の反発は変わりません。",
	},
	"magnet pull invalid": {
		"en": "Enter a number from 0 to 20. The previous value is unchanged.",
		"ja": "0〜20の数値を入力してください。前の値を維持しています。",
	},
	"magnet pull save failed": {
		"en": "Could not save the setting. The previous value is unchanged.",
		"ja": "設定を保存できませんでした。前の値を維持しています。",
	},
	"special sobos": {
		"en": "special sobos",
		"ja": "特別なソボ",
		"de": "besondere Sobos",
		"es": "sobos especiales",
		"it": "sobo speciali",
		"cs": "speciální sobové",
		"pl": "specjalne sobo",
		"ru": "особые собо",
		"sr": "posebni soboi",
		"zh_CN": "特殊索波",
		"zh_TW": "特殊索波",
	},
	"special sobos description": {
		"en": "Occasional small, puffy, magnet or throwing sobos. Special runs do not send scores or achievements to Steam or the world ranking. Changes apply next run.",
		"ja": "ときどき小さい・ふわふわ・磁石・投げ飛ばすのソボが混ざる。特別な試合の点数と実績は Steam と世界ランキングに送らない。切り替えは次の試合から",
		"de": "Gelegentlich kleine, luftige, Magnet- oder werfende Sobos. Besondere Runden senden keine Punkte oder Erfolge an Steam oder die Weltrangliste. Gilt ab der nächsten Runde.",
		"es": "Aparecen sobos pequeños, esponjosos, imán o lanzadores. Las partidas especiales no envían puntos ni logros a Steam ni a la clasificación mundial. Se aplica en la próxima partida.",
		"it": "Ogni tanto compaiono sobo piccoli, soffici, magnete o lanciatori. Le partite speciali non inviano punti o obiettivi a Steam o alla classifica mondiale. Vale dalla prossima partita.",
		"cs": "Občas se objeví malí, nadýchaní, magnetičtí nebo vrhající sobové. Speciální hry neposílají skóre ani úspěchy na Steam ani do světového žebříčku. Platí od další hry.",
		"pl": "Czasem pojawiają się małe, puszyste, magnetyczne lub rzucające sobo. Specjalne gry nie wysyłają wyników ani osiągnięć do Steam ani rankingu światowego. Zmiana działa od następnej gry.",
		"ru": "Иногда появляются маленькие, воздушные, магнитные или бросающие собо. Особые игры не отправляют очки и достижения в Steam или мировой рейтинг. Изменение действует со следующей игры.",
		"sr": "Povremeno se pojavljuju mali, paperjasti, magnetni ili bacajući soboi. Posebne partije ne šalju rezultate ni dostignuća na Steam ili svetsku rang listu. Važi od sledeće partije.",
		"zh_CN": "偶尔出现小型、轻飘飘、磁铁或抛掷的索波。特殊对局的分数和成就不会发送到 Steam 或全球排行榜。更改从下一局生效。",
		"zh_TW": "偶爾出現小型、輕飄飄、磁鐵或拋擲的索波。特殊對局的分數和成就不會傳送到 Steam 或全球排行榜。變更從下一局生效。",
	},
	"trait small": {
		"en": "small sobos",
		"ja": "小さいソボ",
		"de": "kleine Sobos",
		"es": "sobos pequeños",
		"it": "sobo piccoli",
		"cs": "malí sobové",
		"pl": "małe sobo",
		"ru": "маленькие собо",
		"sr": "mali soboi",
		"zh_CN": "小型索波",
		"zh_TW": "小型索波",
	},
	"trait puffy": {
		"en": "puffy sobos",
		"ja": "ふわふわのソボ",
		"de": "luftige Sobos",
		"es": "sobos esponjosos",
		"it": "sobo soffici",
		"cs": "nadýchaní sobové",
		"pl": "puszyste sobo",
		"ru": "воздушные собо",
		"sr": "paperjasti soboi",
		"zh_CN": "轻飘飘的索波",
		"zh_TW": "輕飄飄的索波",
	},
	"trait magnet": {
		"en": "magnet sobos",
		"ja": "磁石のソボ",
		"de": "Magnet-Sobos",
		"es": "sobos imán",
		"it": "sobo magnete",
		"cs": "magnetičtí sobové",
		"pl": "magnetyczne sobo",
		"ru": "собо-магниты",
		"sr": "magnetni soboi",
		"zh_CN": "磁铁索波",
		"zh_TW": "磁鐵索波",
	},
	"trait sticky": {
		"en": "Throwing Sobo",
		"ja": "投げ飛ばすソボ",
		"de": "werfende Sobos",
		"es": "sobos lanzadores",
		"it": "sobo lanciatori",
		"cs": "vrhající sobové",
		"pl": "rzucające sobo",
		"ru": "бросающие собо",
		"sr": "bacajući soboi",
		"zh_CN": "抛掷索波",
		"zh_TW": "拋擲索波",
	},

	"trait description": {
		"en": "Whether this kind appears among special sobos. Applies to new special sobos.",
		"ja": "特別なソボにこの種類を出すかどうか。新しく出る特別なソボから効く",
		"de": "Ob diese Art unter den besonderen Sobos erscheint. Gilt für neue besondere Sobos.",
		"es": "Si este tipo aparece entre los sobos especiales. Se aplica a los nuevos sobos especiales.",
		"it": "Se questo tipo compare tra i sobo speciali. Vale per i nuovi sobo speciali.",
		"cs": "Zda se tento druh objevuje mezi speciálními soby. Platí pro nové speciální soby.",
		"pl": "Czy ten rodzaj pojawia się wśród specjalnych sobo. Dotyczy nowych specjalnych sobo.",
		"ru": "Появляется ли этот вид среди особых собо. Действует для новых особых собо.",
		"sr": "Da li se ova vrsta pojavljuje među posebnim soboima. Važi za nove posebne soboe.",
		"zh_CN": "特殊索波中是否出现此类。对新出现的特殊索波生效。",
		"zh_TW": "特殊索波中是否出現此類。對新出現的特殊索波生效。",
	},
}


static func get_text(key: String) -> String:
	var words: Dictionary = WORDS.get(key, {})
	var locale: String = TranslationServer.get_locale()
	if words.has(locale):
		return words[locale]
	var language: String = locale.get_slice("_", 0)
	if language == "zh":
		var traditional: bool = locale.contains("TW") or locale.contains("HK") or locale.contains("MO") or locale.contains("Hant")
		return words.get("zh_TW" if traditional else "zh_CN", words.get("en", key))
	return words.get(language, words.get("en", key))
