# mg_arrows

Arrow-key timing minigame. Arrows slide left → right along the bottom of the screen; the player
presses the matching arrow key while the arrow is inside the centre ring. Each arrow turns green
(hit) or red (wrong key / missed). The game is won when the hit ratio is **above 70%**.

## Server exports

```lua
local id = exports.mg_arrows:startArrowsGame(player, count, options) -- session id or false
exports.mg_arrows:stopArrowsGame(player)      -- fires onArrowsGameFinish with reason "cancelled"
exports.mg_arrows:isArrowsGameActive(player)
```

- `count` – number of arrows, default `15` (clamped to 1–100)
- `options` – optional `{ speed = 1.0, passPercent = 70 }`

Result:

```lua
addEventHandler("onArrowsGameFinish", root, function(success, hits, total, percent, reason, sessionId)
    -- source = player
    -- reason: "completed" | "cancelled" | "quit" | "timeout" | "invalid"
end)
```

The server validates the client result (session id, arrow count, minimum play time).

## Client exports

Local-only game, the server is not involved:

```lua
exports.mg_arrows:startArrowsGame(count, options)
exports.mg_arrows:stopArrowsGame()
exports.mg_arrows:isArrowsGameActive()

addEventHandler("onClientArrowsGameFinish", localPlayer, function(success, hits, total, percent, reason, sessionId) end)
```

`onClientArrowsGameFinish` also fires for server-started games (with `sessionId` set).

## Config

`shared.lua` → `ARROWS` (speed, spacing, pass percent, result display time).
`/arrowstest [count] [speed]` is enabled while `ARROWS.TEST_COMMAND = true` – turn it off in production.
