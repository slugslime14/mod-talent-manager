# mod-talent-manager

Saved talent specs per character for AzerothCore (WotLK 3.3.5a), with their glyphs and action bars, loaded out of
combat. Comes with the **TalentManager** client addon (`addon/TalentManager`), which shows a talent tree that looks
like the game's own talent frame for planning and editing specs.

What it does:
- the addon's `/tm` window shows a whole talent tree in a copy of the game's talent frame and lets you plan a build
  with the game's rules (points per row, prerequisites, your point total);
- builds are saved on the server as named specs per character, with glyphs, and can be renamed, copied, deleted,
  imported and exported;
- a saved spec loads onto the character out of combat: talents, glyphs and the spec's action bars;
- your online altbots (playerbots) get their own specs and glyphs, managed from the same window.

## Install

1. Server: the module sits in `modules/`; re-run CMake, build and `make install`. Copy
   `etc/modules/mod_talent_manager.conf.dist` to `mod_talent_manager.conf` if you want to change the defaults.
   The characters-DB tables (`data/sql/characters/talent_manager*.sql`) are created at the next worldserver start.
   playerbots is optional: without it there are no altbots in the picker.
   The glyph list is read from the item templates at startup; the glyph art ids from the server's
   `dbc/GlyphProperties.dbc`.
2. Client: copy `addon/TalentManager` to `Interface/AddOns/` of the 3.3.5 client. The addon and the server must
   speak the same protocol version (the addon warns otherwise). After copying new addon files, restart the game: a
   `/reload` doesn't load files that weren't there at startup.

## Addon

- `/tm` opens or closes the window. It shows a whole tree without scrolling; on a short screen it is scaled down to
  fit.
- Left click adds a point, right click takes one out, shift-click links the talent at the planned rank in chat.
- Under the tree: **Save** (the shown spec, or a new spec when you're showing your live talents or a new build),
  **Reset** (drop the changes), **Clear** (take all points out).
- The **Talent Specs** list on the right: your live talents first, then your saved specs. Click one to show it.
  Under it: **New** (empty tree), **Copy** (save what's shown as a new spec), **Rename**, **Delete**, **Import**
  (paste a talent calculator link), **Export** (the shown build as a link, to copy).
- Switching to another spec with unsaved changes asks first.
- **Load** puts the shown saved spec on your character, in the active talent group (dual spec stays as it is). A
  build that only adds points loads at once. Anything else takes a short swap cast (5 s by default) with a cast
  bar; moving, combat, death or casting stops it, and so does right-clicking the bar or pressing Stop. Talent
  changes are free. Not while dead, in combat, in an arena, in a battleground that has started, on a taxi or a
  vehicle.
- The list marks the spec loaded in your active talent group **Active**, or **Active, changed** once your live
  talents or glyphs differ from it (you changed them in the game's own frames). Then **Load** puts them back and
  **Use live** copies your live talents and glyphs into the spec as unsaved changes.
- The **Glyphs** tab (after the three trees) shows the build's six glyph sockets like the game's glyph frame, and
  under them the class's glyphs for the selected socket. Click a socket to select it, click a glyph in the list to
  put it in, right-click a socket to empty it. Sockets your level hasn't opened are locked.
  - A glyph is **known** once it has been in one of the character's sockets (either talent group; inscribing one by
    hand counts). Loading a spec puts known glyphs in for free.
  - A glyph that isn't known but is **in your bags** goes in by using up one of those items, and is known from then
    on.
  - Anything else (not known, none in the bags, or a socket not open yet) is left out of the load, and chat says
    which.
  - An **empty socket** in a spec keeps the glyph you have there when it loads.
  - Glyph changes alone load at once, with no swap cast.
- **Action bars** go with each spec. When you load a spec, your bars as they are now are saved into the spec that
  was loaded before (in this talent group), and the new spec's saved bars are put on.
  - A spec that has never been left has no bars saved: loading it keeps the bars you have. The spec list tooltip says
    which specs have bars.
  - A spec that is loaded in your other talent group too takes that group's bars, which are newer.
  - A button whose spell the character doesn't know after the load stays empty, and stays in the spec's saved bars,
    so loading back to a spec that has the spell puts it back.
  - Bars of a talent group with no saved spec loaded aren't kept anywhere: loading a spec with bars there replaces
    them.
  - Dual-spec switches are untouched; the game keeps bars per talent group as always.
- **Altbots**: the picker at the top of the spec list shows you and the online altbots you lead (playerbots on your
  own account; random bots don't use the talent manager). Pick one to show and edit its specs, glyphs and live
  talents, in its own class's trees. Each character keeps its own specs, known glyphs and unsaved changes.
  - Loading a spec on an altbot works as for you, with these differences: moving and the bot's own casting don't
    stop the swap cast (it follows you and buffs on its own), combat, death and changing maps do. The bot's glyph
    items come from its own bags.
  - After the load the bot sets up its combat strategies again (as playerbots' own `talents spec` command does), so
    strategies you set by hand (`co +...`) are reset. Glyphs from the spec are marked as chosen by hand, so the bot's
    `maintenance` command leaves them alone.
  - Bots have no action bars, so nothing is saved for them.
  - `maintenance` still re-picks an altbot's talents while `Playerbots.AltMaintenanceTalentTree = 1` (the
    playerbots default); set it to 0 to keep loaded specs. MultiBot can also change bot talents; the list then marks
    the loaded spec **Active, changed**.
- `/tm load <name>` loads one of your own specs by name, also from a macro.
- `/tm link` prints the shown build as a talent calculator link (Wowhead / playerbots `PremadeSpecLink` format).
- `/tm import <link>` shows such a link in the window (a whole Wowhead URL works too).

## Config

| Option | Default | |
|---|---|---|
| `TalentManager.Enable` | 1 | |
| `TalentManager.SwapCastTime` | 5000 | ms to load a spec that removes or moves points (0 = instant) |
| `TalentManager.MaxSpecs` | 20 | saved specs per character |

## Protocol

Addon whispers to yourself with prefix `TMGR`, `CMD:payload`, fields `,` separated. Protocol version 5.

A request about one of your altbots is `@<guid>|CMD:payload`; the server answers everything about that bot to its
master, tagged the same way. `CHARS` and its answer are always about you.

| Direction | Message | |
|---|---|---|
| client → server | `HELLO:` | asks for `INFO` |
| server → client | `INFO:version,maxSpecs,swapCastMs,talentPoints,activeGroup,groupCount,level,class` | `activeGroup` 1-based |
| client → server | `CHARS:` | asks for the character picker's list |
| server → client | `CHARBEGIN:`, `CHAR:entry;...`, `CHAREND:` | entry = `guid,name,class,level`; you first, then your online altbots |
| client → server | `TREES:` | asks for the character's talent trees (for an altbot of another class) |
| server → client | `TREEBEGIN:class`, `TREE:entry;...`, `TREEEND:class` | entry = `tree,talentId,row,column,maxRank,rank1Spell,dependsOn,dependsOnRank`, link order |
| client → server | `LIVE:` | asks for the live build (for an altbot) |
| server → client | `LIVE:talents,glyph1..glyph6` | the active talent group's talents and glyphs |
| client → server | `LIST:` | asks for the spec list |
| client → server | `SAVE:id,name,talents,glyph1..glyph6` | id 0 = new spec; answered `SAVED:id` and the list |
| client → server | `RENAME:id,name`, `DELETE:id` | answered with the list |
| client → server | `LOAD:id` | answered `CAST:ms,id` (swap cast started) or straight `LOADED` |
| client → server | `STOP:` | stops a swap cast |
| client → server | `GLYPHS:` | asks for the class's glyphs |
| server → client | `GLYPHBEGIN:count`, `GLYPH:entry;...`, `GLYPHEND:` | entry = `id,spellId,type,itemId,iconId,known,bags`; type 0 major, 1 minor; bags = items carried |
| client → server | `GSYNC:` | a glyph was inscribed by hand: the server adds socketed glyphs to the known ones (and resends the list if one was new) |
| server → client | `CASTSTOP:reason` | moved, combat, dead, cast, stopped, deleted, failed |
| server → client | `LOADED:id,missing,skipped,used,bars` | the spec is on the character; `missing` talents didn't take; `skipped` / `used` are glyph ids joined by `/` (left out / inscribed from the bags); `bars` 1 when the spec's action bars were put on; the list follows |
| server → client | `SPECBEGIN:count,max,loaded1,loaded2`, `SPEC:entry;...`, `SPECEND:` | entry = `id,sort,name,talents,glyph1..glyph6,bars`; `bars` 1 when action bars are saved; `loadedN` = spec in talent group N, 0 = none |
| server → client | `ERR:text`, `MSG:text` | shown in chat |

`talents` is a talent calculator link: one digit per talent (its rank) in row, then column order, trees in tab
order joined by `-`, trailing zeros left out. Names can't hold `,` `;` `:` or `|`. The server checks every save
against the talent rules and the character's point total.

## Limits

- No hunter pet talents.
- No link to gear sets; talents and gear stay separate.
- Altbots only while online and led by you; offline characters can't be edited.
- Altbots are managed from the addon only. There are no whisper commands: mod-ollama-chat and playerbots see a
  whisper to a bot before this module does, so the bot would also chat back and try to read it as a command.
- A deleted spec's id can be used again by the next new spec; its saved bars are deleted with it.

## License

AGPL-3.0, see `LICENSE`. The addon draws branches and arrows with the game client's own FrameXML helpers
(`TalentFrameBase.lua`) and uses the client's own talent and glyph frame textures; the layout numbers and texture
coordinates follow the 3.3.5 frames, no Blizzard code is copied.
