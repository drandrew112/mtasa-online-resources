-- Help content index (client). The text format is described in README.md.
--
-- categories: { id, order, title }
--     title = plain string, { en = "...", hu = "..." } or a v_locals message
-- topics:     { id, category, order, file, title, keywords, related, hidden }
--     file     = path under content/<lang>/ (falls back to content/en/);
--                every file must also be listed in meta.xml
--     title    = optional, default: the first "# " line of the file
--     keywords = optional extra search words ("a, b" or { "a", "b" })
--     related  = optional list of topic ids shown under the page
--     hidden   = true: not listed on the left, only reachable by search / links
--
-- home = optional landing page file (content/<lang>/home.txt). Without it the
-- panel shows a table of contents.
--
-- Example:
--   categories = {
--       { id = "basics", order = 10, title = { en = "Getting started", hu = "Kezdő lépések" } },
--   },
--   topics = {
--       { id = "first_steps", category = "basics", order = 10, file = "basics/first_steps.txt" },
--   },

HELP_INDEX = {
    home = nil,
    categories = {
    },
    topics = {
    },
}
