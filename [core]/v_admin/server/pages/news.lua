if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/pages/news.lua
--  News page (was the /news editor of v_news).
--
--  list   {}                                          -> { list, nowDate, nowTime, languages }
--  save   { id, dateText, timeText, texts }           -> { list, nowDate, nowTime, languages, selected }
--         texts = { [lang] = { title, body } }, one per v_locals language (empty = left out)
--  delete { id }                                      -> { list, nowDate, nowTime, languages }
-- ============================================================

local function list()
    if not resourceRunning("v_news") then return nil end
    local ok, data = pcall(function() return exports.v_news:newsAdminList() end)
    return ok and type(data) == "table" and data or nil
end

PAGES.register("news", {
    perm = "news",
    actions = {
        list = function(actor, args, reply)
            local data = list()
            if not data then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_news" })) end
            reply(data)
        end,

        save = function(actor, args, reply)
            if not resourceRunning("v_news") then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_news" })) end
            local texts = {}
            for code, t in pairs(type(args.texts) == "table" and args.texts or {}) do
                if type(code) == "string" and type(t) == "table" then
                    texts[code] = { title = tostring(t.title or ""), body = tostring(t.body or "") }
                end
            end
            local r = exports.v_news:newsAdminSave(actorAccount(actor) or actorName(actor), tonumber(args.id),
                argText(args.dateText), argText(args.timeText), texts)
            if type(r) ~= "table" then return reply(false, L.msg("v_admin.page.request_failed")) end
            if r.ok then
                local main = texts.en or select(2, next(texts)) or {}
                adminLog(actor, ("news: %s article #%s '%s'"):format(args.id and "edited" or "added", tostring(r.id), tostring(main.title)):sub(1, 250))
            end
            local data = list() or {}
            data.selected = r.ok and r.id or nil
            data.saved = r.ok
            reply(data, r.message)
        end,

        delete = function(actor, args, reply)
            if not resourceRunning("v_news") then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_news" })) end
            local r = exports.v_news:newsAdminDelete(actorAccount(actor) or actorName(actor), tonumber(args.id))
            if type(r) ~= "table" then return reply(false, L.msg("v_admin.page.request_failed")) end
            if r.ok then adminLog(actor, "news: deleted article #" .. tostring(args.id)) end
            reply(list() or false, r.message)
        end,
    },
})
