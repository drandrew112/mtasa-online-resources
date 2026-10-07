-- web_api :: server/demo.lua
-- API of the demo / documentation page (demo/index.html): a tiny live example of an
-- http="true" export that works over HTTP and through the in-game bridge.

function osaDemoState()
    return {
        ok      = true,
        time    = getRealTime().timestamp,
        players = getPlayerCount(),
        apps    = getApps(),
        caller  = getCallerId(hostname),
    }
end

function osaDemoEcho(text)
    return { ok = true, text = tostring(text or ""):sub(1, 200), caller = getCallerId(hostname) }
end
