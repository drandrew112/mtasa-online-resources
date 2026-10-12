-- v_locals configuration (shared). See DESIGN.md.

LOC = {
    -- language used when nothing else is known, and the last fallback
    DEFAULT_LANG = "en",

    -- accData key holding the account's language code
    ACCDATA_KEY = "locale.language",

    -- private client file remembering the language before login
    CLIENT_FILE = "@language.txt",

    -- admin_level (accData) needed for /locdebug /locreload /locbench /locmissing
    ADMIN_LEVEL = 3,

    -- entry cap of every lib cache (text width, fit, wrap, upper); a full cache
    -- is simply dropped and refilled
    CACHE_MAX = 4000,

    -- valid language codes: "en", "hu", "pt_BR"
    LANG_PATTERN = "^%l%l$",
    LANG_PATTERN_REGION = "^%l%l_%u%u$",

    -- debug modes accepted by /locdebug (client side only)
    DEBUG_MODES = { off = true, keys = true, pseudo = true, overflow = true },

    -- synthetic strings of /locbench, injected into memory for the run only
    -- (never part of a catalog)
    BENCH_STRINGS = {
        ["__bench.static"]      = "Open the Graphics settings.",
        ["__bench.params"]      = "{name} paid you {amount|money}.",
        ["__bench.items.one"]   = "{count} patient",
        ["__bench.items.other"] = "{count} patients",
    },
}

function locIsLangCode(code)
    return type(code) == "string" and (code:match(LOC.LANG_PATTERN) ~= nil or code:match(LOC.LANG_PATTERN_REGION) ~= nil)
end
