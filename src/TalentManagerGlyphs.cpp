#include "TalentManagerGlyphs.h"
#include "DBCFileLoader.h"
#include "DBCStores.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "World.h"
#include <array>
#include <map>
#include <unordered_map>

namespace TalentManager::Glyphs
{
    namespace
    {
        std::map<uint32, Glyph> glyphs;                            // by glyph id
        std::array<std::vector<Glyph const*>, MAX_CLASSES> byClass;

        // The core leaves GlyphProperties' icon column out (GlyphPropertiesfmt "niix"), so read it from the file.
        std::unordered_map<uint32, uint32> LoadIcons()
        {
            std::unordered_map<uint32, uint32> icons;
            std::string const path = sWorld->GetDataPath() + "dbc/GlyphProperties.dbc";
            DBCFileLoader file;
            if (!file.Load(path.c_str(), "nnnn"))
            {
                LOG_WARN("module", "mod-talent-manager: can't read {}, glyph sockets will show a plain rune", path);
                return icons;
            }
            for (uint32 i = 0; i < file.GetNumRows(); ++i)
            {
                DBCFileLoader::Record const record = file.getRecord(i);
                icons[record.getUInt(0)] = record.getUInt(3);
            }
            return icons;
        }
    }

    void Load()
    {
        glyphs.clear();
        for (auto& list : byClass)
            list.clear();

        std::unordered_map<uint32, uint32> const icons = LoadIcons();
        for (auto const& [itemId, proto] : *sObjectMgr->GetItemTemplateStore())
        {
            if (proto.Class != ITEM_CLASS_GLYPH)
                continue;
            // Glyph items are each for one class; the few for every class are unused NPC and test items.
            uint32 const classMask = proto.AllowableClass;
            if (!classMask || (classMask & CLASSMASK_ALL_PLAYABLE) == CLASSMASK_ALL_PLAYABLE)
                continue;

            for (auto const& itemSpell : proto.Spells)
            {
                SpellInfo const* spellInfo = itemSpell.SpellId ? sSpellMgr->GetSpellInfo(itemSpell.SpellId) : nullptr;
                if (!spellInfo)
                    continue;
                for (SpellEffectInfo const& effect : spellInfo->Effects)
                {
                    if (effect.Effect != SPELL_EFFECT_APPLY_GLYPH || effect.MiscValue <= 0)
                        continue;
                    GlyphPropertiesEntry const* entry = sGlyphPropertiesStore.LookupEntry(uint32(effect.MiscValue));
                    if (!entry || !entry->SpellId)
                        continue;

                    // One item per glyph: keep the lowest item id if there are more.
                    auto [itr, inserted] = glyphs.try_emplace(entry->Id);
                    if (!inserted && itr->second.itemId < itemId)
                        continue;
                    Glyph& glyph = itr->second;
                    glyph.id = entry->Id;
                    glyph.spellId = entry->SpellId;
                    glyph.type = uint8(entry->TypeFlags);
                    glyph.itemId = itemId;
                    glyph.classMask = classMask;
                    auto icon = icons.find(entry->Id);
                    glyph.iconId = icon != icons.end() ? icon->second : 0;
                }
            }
        }

        for (auto const& [id, glyph] : glyphs)
            for (uint8 classId = 1; classId < MAX_CLASSES; ++classId)
                if (glyph.classMask & (1 << (classId - 1)))
                    byClass[classId].push_back(&glyph);

        LOG_INFO("module", "mod-talent-manager: {} glyphs", glyphs.size());
    }

    Glyph const* Find(uint32 glyphId)
    {
        auto itr = glyphs.find(glyphId);
        return itr != glyphs.end() ? &itr->second : nullptr;
    }

    std::vector<Glyph const*> const& ForClass(uint8 classId)
    {
        return byClass[classId < MAX_CLASSES ? classId : 0];
    }

    bool SocketOpen(Player* player, uint8 slot)
    {
        return slot < MAX_GLYPH_SLOT_INDEX && (player->GetUInt32Value(PLAYER_GLYPHS_ENABLED) & (1 << slot));
    }

    bool Fits(Player* player, uint8 slot, Glyph const& glyph)
    {
        if (slot >= MAX_GLYPH_SLOT_INDEX || !(glyph.classMask & player->getClassMask()))
            return false;
        GlyphSlotEntry const* socket = sGlyphSlotStore.LookupEntry(player->GetGlyphSlot(slot));
        return socket && socket->TypeFlags == glyph.type;
    }
}
