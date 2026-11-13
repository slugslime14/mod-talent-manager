// Action bars saved with each spec: stored when another spec is loaded over it, put back when it loads again.

#include "DatabaseEnv.h"
#include "Player.h"
#include "StringFormat.h"
#include "TalentManagerMgr.h"

namespace TalentManager
{
    namespace
    {
        // talent_manager_action row that only says "this spec has bars", for a spec whose bars were all empty.
        constexpr uint8 MARKER_BUTTON = 255;

        bool Usable(Player* player, uint8 button, uint32 packed)
        {
            return player->IsActionButtonDataValid(button, ACTION_BUTTON_ACTION(packed), ACTION_BUTTON_TYPE(packed));
        }
    }

    void Mgr::StoreBars(Player* player, Spec& spec)
    {
        Bars bars;
        for (uint8 button = 0; button < MAX_ACTION_BUTTONS; ++button)
        {
            if (ActionButton const* live = player->GetActionButton(button))
            {
                if (live->packedData)
                    bars[button] = live->packedData;
                continue;
            }
            // Left empty by ApplyBars because the spell isn't known now: keep it for when it is.
            auto saved = spec.bars.find(button);
            if (saved != spec.bars.end() && !Usable(player, button, saved->second))
                bars[button] = saved->second;
        }
        spec.bars = std::move(bars);
        spec.hasBars = true;

        uint32 const guid = player->GetGUID().GetCounter();
        std::string values;
        for (auto const& [button, packed] : spec.bars)
            values += Acore::StringFormat("{}({}, {}, {}, {}, {})", values.empty() ? "" : ", ", guid, spec.id, button,
                ACTION_BUTTON_ACTION(packed), ACTION_BUTTON_TYPE(packed));
        if (values.empty())
            values = Acore::StringFormat("({}, {}, {}, 0, 0)", guid, spec.id, MARKER_BUTTON);

        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        trans->Append("DELETE FROM talent_manager_action WHERE guid = {} AND spec_id = {}", guid, spec.id);
        trans->Append("INSERT INTO talent_manager_action (guid, spec_id, button, action, type) VALUES {}", values);
        CharacterDatabase.CommitTransaction(trans);
    }

    bool Mgr::BarsFor(Player* player, Profile const& profile, Spec const& spec, Bars& bars)
    {
        // Loaded in the other talent group too: that group's bars are newer than the ones stored in the spec. The
        // core wrote them to character_action when it left that group.
        uint8 const active = player->GetActiveSpec();
        for (uint8 group = 0; group < TALENT_GROUPS && group < player->GetSpecsCount(); ++group)
        {
            if (group == active || profile.loaded[group] != spec.id)
                continue;
            if (QueryResult result = CharacterDatabase.Query("SELECT button, action, type FROM character_action "
                "WHERE guid = {} AND spec = {}", player->GetGUID().GetCounter(), group))
            {
                bars.clear();
                do
                {
                    Field* fields = result->Fetch();
                    uint8 const button = fields[0].Get<uint8>();
                    if (button < MAX_ACTION_BUTTONS)
                        bars[button] = fields[1].Get<uint32>() | (uint32(fields[2].Get<uint8>()) << 24);
                } while (result->NextRow());
                return true;
            }
        }

        if (!spec.hasBars)
            return false;
        bars = spec.bars;
        return true;
    }

    void Mgr::ApplyBars(Player* player, Bars const& bars)
    {
        for (uint8 button = 0; button < MAX_ACTION_BUTTONS; ++button)
        {
            auto itr = bars.find(button);
            if (itr != bars.end() && Usable(player, button, itr->second))
                player->addActionButton(button, ACTION_BUTTON_ACTION(itr->second), ACTION_BUTTON_TYPE(itr->second));
            else
                player->removeActionButton(button);
        }
        player->SendActionButtons(1);
    }
}
