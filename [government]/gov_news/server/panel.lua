-- gov_news / server/panel.lua
-- The News page of /gov and the registration with gov_core.

local A = GOV.A

function A.news(p, args, reply)
    GOV.newsList(function(list) reply({ list = list, langs = GOV.newsLanguages() }) end)
end

--- { texts = { [lang] = { title, body } } }
function A.postNews(p, args, reply, actor)
    GOV.postNews(args, actor, function(ok, err) reply(ok or false, err) end)
end

function A.deleteNews(p, args, reply, actor)
    GOV.deleteNews(args.id, actor, function(ok, err) reply(ok or false, err) end)
end

GOV.module({
    actions = { news = "viewer", postNews = "minister", deleteNews = "minister" },
    pages = {
        { id = "news", category = "public", order = 20, script = "web/js/pages.js" },
    },
})
