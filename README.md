# mod-talent-manager

Saved talent specs per character for AzerothCore (WotLK 3.3.5a), with their glyphs and action bars, loaded out of
combat. Comes with the **TalentManager** client addon (`addon/TalentManager`), which shows a talent tree that looks
like the game's own talent frame for planning and editing specs.

Status: work in progress. Phases 0 to 4 of the plan are written:
- the addon's `/tm` window shows a whole talent tree in a copy of the game's talent frame and lets you plan a build
  with the game's rules (points per row, prerequisites, your point total);
- builds can be saved on the server as named specs per character, renamed, copied, deleted, imported and exported.
- a saved spec can be loaded onto your character out of combat, talents and glyphs (action bars come in phase 5).

## Install

1. Server: the module sits in `modules/`; re-run CMake, build and `make install`. Copy
   `etc/modules/mod_talent_manager.conf.dist` to `mod_talent_manager.conf` if you want to change the defaults.
   The characters-DB tables (`data/sql/characters/talent_manager*.sql`) are created at the next worldserver start.
   The glyph list is read from the item templates at startup; the glyph art ids from the server's
   `dbc/GlyphProperties.dbc`.
2. Client: copy `addon/TalentManager` to `Interface/AddOns/` of the 3.3.5 client.

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
- `/tm load <name>` loads a spec by name, also from a macro.
- `/tm link` prints the shown build as a talent calculator link (Wowhead / playerbots `PremadeSpecLink` format).
- `/tm import <link>` shows such a link in the window (a whole Wowhead URL works too).

## Config

| Option | Default | |
|---|---|---|
| `TalentManager.Enable` | 1 | |
| `TalentManager.SwapCastTime` | 5000 | ms to load a spec that removes or moves points (0 = instant) |
| `TalentManager.MaxSpecs` | 20 | saved specs per character |

## Protocol

Addon whispers to yourself with prefix `TMGR`, `CMD:payload`, fields `,` separated.

| Direction | Message | |
|---|---|---|
| client → server | `HELLO:` | asks for `INFO` |
| server → client | `INFO:version,maxSpecs,swapCastMs,talentPoints,activeGroup,groupCount` | `activeGroup` 1-based |
| client → server | `LIST:` | asks for the spec list |
| client → server | `SAVE:id,name,talents,glyph1..glyph6` | id 0 = new spec; answered `SAVED:id` and the list |
| client → server | `RENAME:id,name`, `DELETE:id` | answered with the list |
| client → server | `LOAD:id` | answered `CAST:ms,id` (swap cast started) or straight `LOADED` |
| client → server | `STOP:` | stops a swap cast |
| client → server | `GLYPHS:` | asks for the class's glyphs |
| server → client | `GLYPHBEGIN:count`, `GLYPH:entry;...`, `GLYPHEND:` | entry = `id,spellId,type,itemId,iconId,known`; type 0 major, 1 minor |
| client → server | `GSYNC:` | a glyph was inscribed by hand: the server adds socketed glyphs to the known ones (and resends the list if one was new) |
| server → client | `CASTSTOP:reason` | moved, combat, dead, cast, stopped, deleted, failed |
| server → client | `LOADED:id,missing,skipped,used` | the spec is on the character; `missing` talents didn't take; `skipped` / `used` are glyph ids joined by `/` (left out / inscribed from the bags); the list follows |
| server → client | `SPECBEGIN:count,max,loaded1,loaded2`, `SPEC:entry;...`, `SPECEND:` | entry = `id,sort,name,talents,glyph1..glyph6`; `loadedN` = spec in talent group N, 0 = none |
| server → client | `ERR:text`, `MSG:text` | shown in chat |

`talents` is a talent calculator link: one digit per talent (its rank) in row, then column order, trees in tab
order joined by `-`, trailing zeros left out. Names can't hold `,` `;` `:` or `|`. The server checks every save
against the talent rules and the character's point total.

## License

AGPL-3.0, see `LICENSE`. The addon draws branches and arrows with the game client's own FrameXML helpers
(`TalentFrameBase.lua`) and uses the client's own talent and glyph frame textures; the layout numbers and texture
coordinates follow the 3.3.5 frames, no Blizzard code is copied.
