# mg_splinting

Fracture splinting minigame. A needle sweeps back and forth across a gauge; press **SPACE** while
it is inside the centre (green) window to cinch a bandage wrap. There is no penalty for waiting -
if you miss the window, just press on the next pass. The game ends once `count` wraps have been
judged (or time runs out) and is won when the hit ratio is **above `passPercent`**.

This is deliberately simple (same shape as `mg_arrows`): one thing to time, no combo/attempt system,
no instant-fail mistakes. `speed` (needle speed) is the only difficulty knob.

## Server exports

```lua
local id = exports.mg_splinting:startSplintGame(player, ped, count, options) -- session id or false
exports.mg_splinting:stopSplintGame(player)      -- fires onSplintGameFinish with reason "cancelled"
exports.mg_splinting:isSplintGameActive(player)
```

- `ped` - optional ped/player being treated (`nil` = no positioning, no animation)
- `count` - wraps needed, default `8` (clamped to 1-20)
- `options` - optional `{ speed = 1.0, passPercent = 70, time = 40 }`

Result:

```lua
addEventHandler("onSplintGameFinish", root, function(success, hits, total, percent, reason, sessionId)
    -- source = player
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
end)
```

The server plays the animation (synced to everyone), stops it when the game ends, and sanity
checks the client result (session id, reason, hit/total counts, play time).

## Client exports

Local-only game, the server is not involved (the animation is only visible to this client):

```lua
exports.mg_splinting:startSplintGame(ped, count, options)
exports.mg_splinting:stopSplintGame()
exports.mg_splinting:isSplintGameActive()

addEventHandler("onClientSplintGameFinish", localPlayer, function(success, hits, total, percent, reason, sessionId) end)
```

`onClientSplintGameFinish` also fires for server-started games (with `sessionId` set).

## Config

`shared.lua` -> `SPLINT` (needle speed/window, pass percent, timings, animation, placement offsets).
`/splinttest [count] [speed] [0]` spawns a lying test ped in front of you and starts the game (pass
`0` as the third argument to play without a ped). Enabled while `SPLINT.TEST_COMMAND = true` - turn
it off in production.
