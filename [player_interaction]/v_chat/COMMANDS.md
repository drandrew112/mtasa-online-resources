# v_chat command database

Typing `/` in the chat input runs a command and shows a list under the input box:

```
/command <arg> [arg] [admin 3]
Description of the command.
```

Tab completes the name (press again to cycle). Enter runs it: client commands locally, server commands on the server
(if a name exists on both sides, both run).

## Where the entries come from

1. **Automatic** – every running resource is scanned with `getCommandHandlers` (server and client). These entries
   have only a name (no parameters / description, admin level 0).
2. **Registered** – a resource registers a command with details. This replaces the automatic entry.
   Registrations are removed when the resource stops.

MTA can't read parameters or descriptions from a command handler, so (2) is how you give them.

## Registering (helper)

Add to the resource script (server and/or client; the same lines work on both sides):

```lua
loadstring(exports.v_chat:importCommands())()   -- creates CMD (once per resource)

-- CMD.register(name, params, adminLevel, description)
CMD.register("kill",  "<player>",        3, "Kills the player.")
CMD.register("heal",  "[player]",        0, "Heals you, or the given player.")
CMD.register("where", "",                0, "Shows your coordinates.")
```

* `name` – command name without `/` (letters, digits, `_ - .`)
* `params` – free text, convention: `<required> [optional]`
* `adminLevel` – minimum `admin_level` element data to see and run it (0 = everyone)
* `description` – one or two sentences

The helper registers again by itself when v_chat restarts. No `<include>` is needed;
a missing v_chat is ignored.

Direct exports (no restart handling): `exports.v_chat:registerCommand(name, params, level, description)`,
`exports.v_chat:unregisterCommand(name)`, `exports.v_chat:getCommandInfo(name)` (server).

The registration only affects the chat list and the chat's admin check. The command itself still needs its own
`addCommandHandler` (and its own permission check, since it can also be run from the F8 console).
