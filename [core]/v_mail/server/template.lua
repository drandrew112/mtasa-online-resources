-- The house mail layout (dark card with the accent bar), plain text + html.
--
-- renderTemplate(t) -> text, html
--   t = {
--       title      = "...",          -- optional, big bold first line
--       greeting   = "Hi Name,",     -- optional
--       paragraphs = { "...", ... }, -- "\n" inside a paragraph is a line break; an entry can also be
--                                    -- { heading = "..." } (section line) or { title = "...", text = "..." }
--       code       = "AB12CD",       -- optional, large spaced-out code
--       note       = "...",          -- optional, small grey text under it
--       signature  = "...",          -- optional, default MAILER.SIGNATURE
--   }
-- Every text is escaped: callers pass plain text, never html.

local function htmlEscape(text)
    return (tostring(text):gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }))
end

local function htmlLines(text)
    return (htmlEscape(text):gsub("\r?\n", "<br>"))
end

local function str(v)
    return type(v) == "string" and v ~= "" and v or nil
end

function renderTemplate(t)
    if type(t) ~= "table" then return nil end
    local paragraphs = {}
    for _, p in ipairs(type(t.paragraphs) == "table" and t.paragraphs or {}) do
        if str(p) or (type(p) == "table" and (str(p.heading) or str(p.title) or str(p.text))) then
            paragraphs[#paragraphs + 1] = p
        end
    end
    local title, greeting, code, note = str(t.title), str(t.greeting), str(t.code), str(t.note)
    local signature = str(t.signature) or MAILER.SIGNATURE

    local text, html = {}, {}
    local function add(plain, markup)
        text[#text + 1] = plain
        html[#html + 1] = markup
    end
    if title then
        add(title, '<p style="margin:0 0 18px;font-size:20px;font-weight:bold;line-height:1.3;color:#ffffff">' .. htmlLines(title) .. '</p>')
    end
    if greeting then
        add(greeting, '<p style="margin:0 0 14px;font-size:16px">' .. htmlLines(greeting) .. '</p>')
    end
    for _, p in ipairs(paragraphs) do
        if type(p) ~= "table" then
            add(p, '<p style="margin:0 0 18px;font-size:15px;line-height:1.5">' .. htmlLines(p) .. '</p>')
        elseif str(p.heading) then
            add("== " .. p.heading .. " ==", '<p style="margin:26px 0 12px;padding-bottom:6px;border-bottom:1px solid #2a323c;'
                .. 'font-size:14px;font-weight:bold;letter-spacing:1px;color:#409cb4">' .. htmlLines(p.heading) .. '</p>')
        else
            local plain, markup = {}, {}
            if str(p.title) then
                plain[#plain + 1] = p.title
                markup[#markup + 1] = '<span style="font-size:16px;font-weight:bold;color:#ffffff">' .. htmlLines(p.title) .. '</span>'
            end
            if str(p.text) then
                plain[#plain + 1] = p.text
                markup[#markup + 1] = htmlLines(p.text)
            end
            add(table.concat(plain, "\n"), '<p style="margin:0 0 18px;font-size:15px;line-height:1.5">' .. table.concat(markup, "<br>") .. '</p>')
        end
    end
    if code then
        add("    " .. code, '<p style="margin:0 0 18px;font-size:32px;font-weight:bold;letter-spacing:8px;color:#ffffff">' .. htmlEscape(code) .. '</p>')
    end
    if note then
        add(note, '<p style="margin:0 0 18px;font-size:13px;line-height:1.5;color:#929eaa">' .. htmlLines(note) .. '</p>')
    end
    if signature then
        add(signature, '<p style="margin:0;font-size:13px;color:#929eaa">' .. htmlLines(signature) .. '</p>')
    end

    return table.concat(text, "\n\n") .. "\n",
        '<!doctype html><html><body style="margin:0;padding:24px;background:#101318;font-family:Arial,sans-serif;color:#e4e9ee">'
        .. '<div style="max-width:520px;margin:0 auto;background:#181d24;padding:28px;border-left:4px solid #409cb4">'
        .. table.concat(html) .. '</div></body></html>'
end
