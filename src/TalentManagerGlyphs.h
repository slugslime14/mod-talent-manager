#ifndef MOD_TALENT_MANAGER_GLYPHS_H
#define MOD_TALENT_MANAGER_GLYPHS_H

#include "Define.h"
#include <vector>

class Player;

// The glyphs each class can use, found as playerbots finds them: glyph items (ITEM_CLASS_GLYPH) whose spell has an
// SPELL_EFFECT_APPLY_GLYPH effect. Built once at startup.
namespace TalentManager::Glyphs
{
    struct Glyph
    {
        uint32 id = 0;          // GlyphProperties.dbc
        uint32 spellId = 0;     // the glyph's aura
        uint8 type = 0;         // GlyphProperties TypeFlags: 0 major, 1 minor
        uint32 itemId = 0;      // the glyph item that inscribes it
        uint32 classMask = 0;   // the item's AllowableClass
        uint32 iconId = 0;      // SpellIcon.dbc, for the addon's socket art; 0 when unknown
    };

    void Load();

    Glyph const* Find(uint32 glyphId);

    // The class's glyphs, sorted by id.
    std::vector<Glyph const*> const& ForClass(uint8 classId);

    // The socket is open at the player's level (PLAYER_GLYPHS_ENABLED).
    bool SocketOpen(Player* player, uint8 slot);

    // The glyph is the player's class and the socket's type (major or minor).
    bool Fits(Player* player, uint8 slot, Glyph const& glyph);
}

#endif
