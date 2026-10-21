package com.veylo.player

/** Channel names and countries, the same rules as the iPhone and Samsung TV apps. */
object Names {
    private val SPLIT = Regex("[|•┃│]")
    private val PREFIX = Regex("^[A-Z]{2,3}\\s*[:\\-]\\s+")
    private val MARKS = Regex("[(\\[]?\\b(4K|8K|UHD|FHD|HD|SD|HEVC|H\\.?26[45]|2160P|1080P|720P|50 ?FPS|60 ?FPS)\\b[)\\]]?", RegexOption.IGNORE_CASE)
    private val SPACES = Regex("\\s{2,}")
    private val SHOUT = Regex("[A-Z]{4,}")

    /** Readable title: drops short tag prefixes ("UK: ", "CRIC ||") and quality marks. */
    fun title(name: String): String {
        val parts = name.split(SPLIT).map { it.trim() }.filter { it.isNotEmpty() }.toMutableList()
        while (parts.size > 1 && parts[0].length <= 6) parts.removeAt(0)
        var text = parts.joinToString(" ")
        text = text.replace(PREFIX, "")
        text = text.replace(MARKS, " ")
        text = text.replace(SPACES, " ").trim()
        if (text.length < 2) text = name.trim()
        if (text == text.uppercase() && SHOUT.containsMatchIn(text)) {
            text = text.split(" ").joinToString(" ") { w ->
                if (w.length <= 3 || w.any { it.isDigit() }) w else w.substring(0, 1) + w.substring(1).lowercase()
            }
        }
        return text
    }

    fun quality(name: String): String {
        val upper = " " + name.uppercase().replace(Regex("[^A-Z0-9]+"), " ") + " "
        return when {
            Regex(" (4K|8K|UHD|2160P) ").containsMatchIn(upper) -> "4K"
            Regex(" (FHD|1080P) ").containsMatchIn(upper) -> "FHD"
            Regex(" (HD|720P) ").containsMatchIn(upper) -> "HD"
            else -> ""
        }
    }

    fun hash(text: String): String {
        var h = 5381
        for (c in text) h = (h shl 5) + h + c.code
        return Integer.toUnsignedString(h, 36)
    }

    // ---------- Countries (from the provider's own category names) ----------
    val COUNTRY_NAMES = mapOf(
        "IN" to "India", "PK" to "Pakistan", "BD" to "Bangladesh", "LK" to "Sri Lanka", "NP" to "Nepal", "AF" to "Afghanistan",
        "UK" to "United Kingdom", "IE" to "Ireland", "US" to "USA", "CA" to "Canada", "AU" to "Australia", "NZ" to "New Zealand",
        "DE" to "Germany", "AT" to "Austria", "CH" to "Switzerland", "FR" to "France", "BE" to "Belgium", "NL" to "Netherlands",
        "ES" to "Spain", "PT" to "Portugal", "IT" to "Italy", "PL" to "Poland", "TR" to "Turkey", "GR" to "Greece", "RO" to "Romania",
        "BG" to "Bulgaria", "HU" to "Hungary", "CZ" to "Czechia", "SK" to "Slovakia", "SE" to "Sweden", "NO" to "Norway", "DK" to "Denmark",
        "FI" to "Finland", "RU" to "Russia", "UA" to "Ukraine", "AL" to "Albania", "EXYU" to "Ex-Yu", "AR" to "Arabic", "AE" to "UAE",
        "SA" to "Saudi Arabia", "QA" to "Qatar", "KW" to "Kuwait", "EG" to "Egypt", "MA" to "Morocco", "DZ" to "Algeria", "TN" to "Tunisia",
        "IL" to "Israel", "IR" to "Iran", "IQ" to "Iraq", "KU" to "Kurdish", "NG" to "Nigeria", "ZA" to "South Africa", "KE" to "Kenya",
        "AFR" to "Africa", "BR" to "Brazil", "MX" to "Mexico", "LAT" to "Latino", "CO" to "Colombia", "CL" to "Chile", "PH" to "Philippines",
        "ID" to "Indonesia", "MY" to "Malaysia", "SG" to "Singapore", "TH" to "Thailand", "VN" to "Vietnam", "CN" to "China",
        "HK" to "Hong Kong", "TW" to "Taiwan", "JP" to "Japan", "KR" to "Korea", "CAR" to "Caribbean"
    )
    private val ALIASES = mapOf(
        "GB" to "UK", "USA" to "US", "UAE" to "AE", "KSA" to "SA", "ARB" to "AR", "ARA" to "AR", "YU" to "EXYU", "IND" to "IN",
        "PAK" to "PK", "CAN" to "CA", "GER" to "DE", "DEU" to "DE", "FRA" to "FR", "ESP" to "ES", "ITA" to "IT", "TUR" to "TR",
        "POR" to "PT", "NED" to "NL", "AUS" to "AU", "BAN" to "BD"
    )
    private val WORDS = listOf(
        Regex("\\b(INDIA|INDIAN|HINDI|PUNJABI|TAMIL|TELUGU|MALAYALAM|MARATHI|BENGALI|BANGLA INDIA|GUJARATI|KANNADA|BHOJPURI)\\b") to "IN",
        Regex("\\b(PAKISTAN|PAKISTANI|URDU)\\b") to "PK", Regex("\\bBANGLADESH\\b") to "BD", Regex("\\bNEPAL\\b") to "NP",
        Regex("\\bSRI ?LANKA\\b") to "LK", Regex("\\b(UNITED KINGDOM|BRITISH|ENGLAND)\\b") to "UK",
        Regex("\\b(USA|AMERICA|AMERICAN)\\b") to "US", Regex("\\bCANADA\\b") to "CA", Regex("\\bAUSTRALIA\\b") to "AU",
        Regex("\\b(ARAB|ARABIC)\\b") to "AR", Regex("\\b(GERMANY|DEUTSCH)\\b") to "DE", Regex("\\bFRANCE\\b") to "FR",
        Regex("\\b(SPAIN|ESPANA)\\b") to "ES", Regex("\\bITALY\\b") to "IT", Regex("\\bTURK(EY|ISH)\\b") to "TR",
        Regex("\\bAFRICA\\b") to "AFR", Regex("\\b(LATINO|LATIN)\\b") to "LAT", Regex("\\bCARIBBEAN\\b") to "CAR",
        Regex("\\bAFGHAN") to "AF"
    )
    private val CODE = Regex("^[\\s|\\[(]*([A-Z]{2,4})\\s*[|\\]):\\-•]")

    /** "IN| SPORTS", "|UK| News", "USA: Movies", "Hindi Movies" → country code ("" if none). */
    fun countryOf(name: String): String {
        val upper = name.uppercase()
        val m = CODE.find(upper)
        if (m != null) {
            val raw = m.groupValues[1]
            val code = ALIASES[raw] ?: raw
            if (COUNTRY_NAMES.containsKey(code)) return code
        }
        for ((re, code) in WORDS) if (re.containsMatchIn(upper)) return code
        return ""
    }

    /** Countries in the provider's category order; null when the names don't say. */
    fun buildCountries(categories: List<Category>): List<Country>? {
        val cats = LinkedHashMap<String, MutableList<Category>>()
        var covered = 0
        for (c in categories) {
            var code = countryOf(c.name)
            if (code.isEmpty()) {
                val votes = HashMap<String, Int>()
                var best = ""
                var bestCount = 0
                for (ch in c.channels.take(60)) {
                    val v = countryOf(ch.name)
                    if (v.isEmpty()) continue
                    val n = (votes[v] ?: 0) + 1
                    votes[v] = n
                    if (n > bestCount) { bestCount = n; best = v }
                }
                if (best.isNotEmpty() && bestCount >= minOf(c.channels.size, 60) * 0.6) code = best
            }
            if (code.isNotEmpty()) covered += 1
            cats.getOrPut(code.ifEmpty { "OTHER" }) { mutableListOf() }.add(c)
        }
        val real = cats.keys.filter { it != "OTHER" }
        if (real.size < 2 || covered < categories.size * 0.3) return null
        val order = real + (if (cats.containsKey("OTHER")) listOf("OTHER") else emptyList())
        return order.map { code ->
            val list = cats.getValue(code)
            Country(code, COUNTRY_NAMES[code] ?: "Other", list, list.flatMap { it.channels })
        }
    }
}
