# v_achievements

Config-registered achievements, stored per account, with XP rewards.

## Registration

Every achievement is defined in `config.lua` (`ACH.LIST`). The field reference
is in that file's header. The registry is validated at start (`server/registry.lua`):
duplicate ids, unknown types and progress entries without a `goal` are skipped
with a debug warning. Ids are stable keys in the stored data, so never rename one.

- `once`: unlocked by `unlockAchievement`.
- `progress`: has a `goal`, and unlocks when its counter reaches it.
  - Without `stat`, it keeps its own counter (`addAchievementProgress`).
  - With `stat`, it shares a counter with every achievement that has the same
    `stat`. `addStat(who, "drive_km", 1.3)` advances all of them, which is how
    tiered sets like Drive 50/100/250/500 km work. A tier added later starts
    from the existing counter value.

Requests for something already completed are ignored and return `false`. Once
every tier of a stat is done, the stat counter stops counting.

## Storage

One accData key, `achievements` (v_mysql), holding a JSON string:

```
{ v=1, done={[id]=unlockTs}, prog={[id]=n}, stats={[stat]=n}, pendingXp=n }
```

- Online accounts are cached. Progress is flushed every `ACH.FLUSH_INTERVAL`,
  and also on quit and on resource stop. Unlocks are written immediately.
- Offline accounts (passed as an account-name string) are read and written
  straight through.

## XP

On unlock, `def.xp` goes to `exports.v_levelsys:giveXp`. That only works for a
loaded online player, so anything it refuses (an offline account, or a login
before v_levelsys is ready) is parked in `pendingXp`. The parked XP is paid
2 s after `onPlayerLoaded` and retried on the flush timer.

## Notifications

On unlock, the client gets `ach:unlocked`, which shows
`ui_core:addNotification("Achievement unlocked", "<name> - <desc>  (+N XP)")`.

## Exports (server; `who` = player element or account name)

| Export | Returns |
|---|---|
| `getAchievements()` | definition list (config order) |
| `getAchievement(id)` | definition or `false` |
| `getAchievementCategories()` | `{ {id,name}, ... }` |
| `getPlayerAchievements(who)` | `{ [id] = {done, unlockedAt, progress, goal} }` |
| `getPlayerAchievement(who, id)` | one record |
| `isAchievementUnlocked(who, id)` | bool |
| `getPlayerAchievementSummary(who)` | `{done, total, xp, maxXp}` |
| `getStat(who, stat)` | number |
| `unlockAchievement(who, id)` | `true` = unlocked now (works on both types) |
| `addAchievementProgress(who, id, n)` / `setAchievementProgress(who, id, v)` | bool |
| `addStat(who, stat, n)` / `setStat(who, stat, v)` | bool |
| `resetPlayerAchievement(who[, id])` | admin/test; a stat-bound id resets its whole stat group; XP is not revoked |

The `set*` exports take an absolute value and never lower a counter, which is
meant for v_stats pushing its own authoritative values.

## Events (server)

- `onPlayerAchievementUnlocked (accountName, id, xp)`: `source` is the player,
  or `resourceRoot` when the account is offline.
- `onPlayerAchievementProgress (id, progress, goal)`: online only, fired when
  the whole-number progress changes.

## Admin

`/ach list|give|prog|stat|reset <player|account> ...` (admin_level > `ACH.ADMIN_LEVEL`).
Feedback comes as a ui_core notification, and `list` prints to F8.

## Later

- **Social panel:** push `getAchievements()` and `getPlayerAchievements(name)`
  into the `sp:push` snapshot; group tiers by `series`/`tier` and mask `hidden`
  achievements until they are unlocked.
- **v_stats:** use stat keys (`addStat`/`setStat`), not achievement ids.
- **Rarity (% of players):** this would need a separate unlocks table, because
  scanning account_data JSON is too expensive.
