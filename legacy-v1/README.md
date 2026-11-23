# Original v1 scripts

My first versions of these scripts, kept as they were written so you can compare them with v2.
They're single pasted files (server.cfg lines, the manifest, config, server and client code together),
so they aren't meant to be dropped into a server as they are. Use the v2 scripts instead.

| v1 file | Replaced by |
| --- | --- |
| [admin-menu-v1.lua](admin-menu-v1.lua), [admin-menu-v1-client.lua](admin-menu-v1-client.lua), [admin-menu-v1-server.lua](admin-menu-v1-server.lua) | [Admin Menu v2](../preston-adminmenu/) |
| [els-lighting-v1.lua](els-lighting-v1.lua) | [ELS v2](../preston-els/) |
| [vehicle-spawn-v1.lua](vehicle-spawn-v1.lua) | [Vehicle Spawn v2](../preston-vehiclespawn/) |
| [vehicle-skins-v1.lua](vehicle-skins-v1.lua) | [Vehicle Skins v2](../preston-vehicleskins/) |
| [iowa-police-skin-v1.lua](iowa-police-skin-v1.lua) | [Iowa Police v2](../preston-iowapolice/) |

Each v2 script's README lists what it fixes from v1. The biggest change: in v1, admin status was a
variable in the player's own game, so a cheat could switch on god mode, noclip, teleporting and car
spawning, and `/ban` only kicked the player. In v2 the server checks every action, and bans are saved.

Admin Menu v1 had these commands: `/adminhelp`, `/kick ID reason`, `/ban ID reason`, `/tp ID`,
`/bring ID`, `/god`, `/noclip`, `/car model`, `/fix`, `/del` and `/plist`.
