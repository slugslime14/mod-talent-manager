// Loading a saved spec onto the character: the checks, the swap cast and putting the talents, glyphs and action bars
// in place.

#include "Battleground.h"
#include "SpellAuras.h"
#include "SpellInfo.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include "Player.h"
#include "StringConvert.h"
#include "StringFormat.h"
#include "TalentManagerBots.h"
#include "TalentManagerComms.h"
#include "TalentManagerConfig.h"
#include "TalentManagerGlyphs.h"
#include "TalentManagerMgr.h"
#include "TalentManagerTalents.h"
#include <algorithm>
#include <array>

namespace TalentManager
{
    namespace
    {
        // Moving farther than this from where the swap cast began stops it.
        constexpr float MAX_MOVE = 1.0f;

        using Talents::LiveRank;

        // The subject of a message about the player: you, or an altbot by name.
        std::string Who(Player* player)
        {
            return Comms::IsBot(player) ? player->GetName() : "You";
        }

        // Bots cast buffs on their own all the time; their casts are stopped instead of stopping the load.
        void StopBotCast(Player* player)
        {
            if (Comms::IsBot(player) && player->IsNonMeleeSpellCast(false))
                player->InterruptNonMeleeSpells(false);
        }

        // True when the build only adds ranks to the live talents: no reset, no swap cast.
        bool OnlyAdds(Player* player, Talents::Build const& build)
        {
            uint8 const classId = player->getClass();
            for (uint8 t = 0; t < Talents::TREES; ++t)
            {
                std::vector<TalentEntry const*> const& tree = Talents::Tree(classId, t);
                for (std::size_t k = 0; k < tree.size(); ++k)
                    if (LiveRank(player, tree[k]) > build[t][k])
                        return false;
            }
            return true;
        }

        // Parses the spec for the player and checks the point total. Returns false and a reason when it can't load.
        bool ReadBuild(Player* player, Spec const& spec, Talents::Build& build, std::string& error)
        {
            if (!Talents::Parse(player->getClass(), spec.talents, build, error))
                return false;
            uint32 const points = Talents::Points(build);
            if (points > player->CalculateTalentsPoints())
            {
                error = Acore::StringFormat("it uses {} talent points and you have {}", points,
                    player->CalculateTalentsPoints());
                return false;
            }
            return true;
        }

        // Takes a glyph out of its socket as Spell::EffectApplyGlyph does: its aura, the auras it triggered, and
        // the client's spell tooltip data.
        void RemoveGlyph(Player* player, uint8 slot, uint32 glyphId)
        {
            if (GlyphPropertiesEntry const* entry = sGlyphPropertiesStore.LookupEntry(glyphId))
            {
                player->RemoveAurasDueToSpell(entry->SpellId);
                Unit::AuraMap& owned = player->GetOwnedAuras();
                for (Unit::AuraMap::iterator itr = owned.begin(); itr != owned.end();)
                {
                    SpellInfo const* triggeredBy = itr->second->GetTriggeredByAuraSpellInfo();
                    if (triggeredBy && triggeredBy->Id == entry->SpellId)
                    {
                        player->RemoveOwnedAura(itr);
                        continue;
                    }
                    ++itr;
                }
                player->SendLearnPacket(entry->SpellId, false);
            }
            player->SetGlyph(slot, 0, true);
        }

        void InscribeGlyph(Player* player, uint8 slot, Glyphs::Glyph const& glyph)
        {
            player->SendLearnPacket(glyph.spellId, true);
            // The flags Spell::EffectApplyGlyph and Player::ActivateSpec use: shapeshift checks stay on.
            player->CastSpell(player, glyph.spellId, TriggerCastFlags(TRIGGERED_FULL_MASK
                & ~(TRIGGERED_IGNORE_SHAPESHIFT | TRIGGERED_IGNORE_CASTER_AURASTATE)));
            player->SetGlyph(slot, glyph.id, true);
        }

        std::string JoinIds(std::vector<uint32> const& ids)
        {
            std::string text;
            for (uint32 id : ids)
                text += (text.empty() ? "" : "/") + std::to_string(id);
            return text;
        }
    }

    std::string Mgr::LoadBlocker(Player* player)
    {
        std::string const who = Who(player);
        if (!player->IsAlive())
            return who + " can't change talents while dead.";
        if (player->IsInCombat())
            return who + " can't change talents in combat.";
        if (player->InArena())
            return who + " can't change talents in an arena.";
        if (Battleground* bg = player->GetBattleground())
            if (bg->GetStatus() == STATUS_IN_PROGRESS)
                return who + " can't change talents once the battleground has started.";
        if (player->IsInFlight())
            return who + " can't change talents while flying a taxi.";
        if (player->GetVehicle())
            return who + " can't change talents on a vehicle.";
        if (player->IsNonMeleeSpellCast(false))
            return who + " can't change talents while casting.";
        return {};
    }

    std::string Mgr::SwapInterrupt(Player* player, Swap const& swap)
    {
        if (!player->IsAlive())
            return "dead";
        if (player->IsInCombat())
            return "combat";
        if (player->GetMapId() != swap.mapId || player->IsInFlight())
            return "moved";
        // An altbot follows its master around and casts buffs on its own; only combat, death and leaving stop it.
        if (swap.bot)
            return {};
        if (player->GetExactDist(swap.x, swap.y, swap.z) > MAX_MOVE)
            return "moved";
        if (player->IsNonMeleeSpellCast(false))
            return "cast";
        return {};
    }

    void Mgr::CancelSwap(Player* player, std::string_view reason)
    {
        if (!_swaps.erase(player->GetGUID().GetCounter()))
            return;
        _swapCount = uint32(_swaps.size());
        Comms::Send(player, "CASTSTOP", reason);
    }

    // LOAD:id. A build that only adds points loads at once, like spending points in the talent frame (glyphs alone
    // too, as inscribing is instant); otherwise a swap cast starts (CAST:ms,id) and the spec loads when it ends.
    // Answers LOADED:id,missing,skipped,used,bars and the list, or ERR. bars is 1 when the spec's action bars were put
    // on.
    void Mgr::HandleLoad(Player* player, std::string_view payload)
    {
        Profile& profile = GetProfile(player);
        uint32 const id = Acore::StringTo<uint32>(payload).value_or(0);
        auto itr = profile.specs.find(id);
        if (itr == profile.specs.end())
        {
            Comms::SendError(player, "That spec no longer exists.");
            SendSpecs(player);
            return;
        }

        StopBotCast(player);
        std::string error = LoadBlocker(player);
        Talents::Build build;
        if (error.empty() && !ReadBuild(player, itr->second, build, error))
            error = Acore::StringFormat("Can't load {}: {}.", itr->second.name, error);
        if (!error.empty())
        {
            Comms::SendError(player, error);
            return;
        }

        // A new load replaces one still casting.
        uint32 const guid = player->GetGUID().GetCounter();
        if (_swaps.erase(guid))
            _swapCount = uint32(_swaps.size());

        if (!Cfg().swapCastTime || OnlyAdds(player, build))
        {
            FinishLoad(player, id);
            return;
        }

        Swap& swap = _swaps[guid];
        swap.specId = id;
        swap.remaining = Cfg().swapCastTime;
        swap.mapId = player->GetMapId();
        swap.x = player->GetPositionX();
        swap.y = player->GetPositionY();
        swap.z = player->GetPositionZ();
        swap.bot = Comms::IsBot(player);
        _swapCount = uint32(_swaps.size());
        Comms::Send(player, "CAST", Acore::StringFormat("{},{}", Cfg().swapCastTime, id));
    }

    void Mgr::OnUpdate(Player* player, uint32 diff)
    {
        if (!_swapCount.load(std::memory_order_relaxed))
            return;

        std::lock_guard<std::mutex> guard(_lock);
        auto itr = _swaps.find(player->GetGUID().GetCounter());
        if (itr == _swaps.end())
            return;

        std::string const reason = SwapInterrupt(player, itr->second);
        if (!reason.empty())
        {
            CancelSwap(player, reason);
            return;
        }

        if (itr->second.remaining > diff)
        {
            itr->second.remaining -= diff;
            return;
        }

        uint32 const specId = itr->second.specId;
        _swaps.erase(itr);
        _swapCount = uint32(_swaps.size());
        FinishLoad(player, specId);
    }

    void Mgr::FinishLoad(Player* player, uint32 specId)
    {
        Profile& profile = GetProfile(player);
        auto itr = profile.specs.find(specId);
        if (itr == profile.specs.end())
        {
            Comms::SendError(player, "That spec no longer exists.");
            return;
        }
        Spec const& spec = itr->second;

        // Things may have changed during the swap cast.
        StopBotCast(player);
        std::string error = LoadBlocker(player);
        Talents::Build build;
        if (error.empty() && !ReadBuild(player, spec, build, error))
            error = Acore::StringFormat("Can't load {}: {}.", spec.name, error);
        if (!error.empty())
        {
            Comms::Send(player, "CASTSTOP", "failed");
            Comms::SendError(player, error);
            return;
        }

        // Action bars: the spec loaded in this group so far gets the bars you have now. The new spec's bars, if it
        // has any, go on after the talents; the client's bars are cleared first, as a dual-spec switch does, so the
        // client doesn't take buttons off by itself while spells are unlearned. Bots have no bars to keep.
        Bars bars;
        bool restoreBars = false;
        if (!Comms::IsBot(player))
        {
            uint8 const group = player->GetActiveSpec();
            uint32 const previous = group < TALENT_GROUPS ? profile.loaded[group] : 0;
            auto previousSpec = profile.specs.find(previous);
            if (previousSpec != profile.specs.end())
                StoreBars(player, previousSpec->second);
            restoreBars = previous != specId && BarsFor(player, profile, spec, bars);
            if (restoreBars)
                player->SendActionButtons(2);
        }

        // Wipe the active talent group for free unless the build only adds ranks, then learn the build row by row,
        // so each talent's points-per-row and prerequisite checks in Player::LearnTalent pass.
        if (!OnlyAdds(player, build))
            player->resetTalents(true);

        uint8 const classId = player->getClass();
        for (uint8 t = 0; t < Talents::TREES; ++t)
        {
            std::vector<TalentEntry const*> const& tree = Talents::Tree(classId, t);
            for (std::size_t k = 0; k < tree.size(); ++k)
                if (build[t][k] > LiveRank(player, tree[k]))
                    player->LearnTalent(tree[k]->TalentID, build[t][k] - 1);
        }

        std::vector<uint32> skipped;
        std::vector<uint32> used;
        ApplyGlyphs(player, profile, spec, skipped, used);
        player->SendTalentsInfoData(false);
        if (restoreBars)
            ApplyBars(player, bars);

        uint32 missing = 0;
        for (uint8 t = 0; t < Talents::TREES; ++t)
        {
            std::vector<TalentEntry const*> const& tree = Talents::Tree(classId, t);
            for (std::size_t k = 0; k < tree.size(); ++k)
                if (LiveRank(player, tree[k]) != build[t][k])
                    ++missing;
        }
        if (missing)
            LOG_WARN("module", "mod-talent-manager: {} talents of spec '{}' didn't load on {}", missing, spec.name,
                player->GetName());

        MarkLoaded(player, profile, specId);
        player->SaveToDB(false, false);

        if (Comms::IsBot(player))
        {
            bool const glyphsChosen = std::any_of(spec.glyphs.begin(), spec.glyphs.end(), [](uint32 g) { return g; });
            Bots::AfterLoad(player, glyphsChosen);
            SendLive(player);
        }

        Comms::Send(player, "LOADED", Acore::StringFormat("{},{},{},{},{}", specId, missing, JoinIds(skipped),
            JoinIds(used), restoreBars ? 1 : 0));
        SendSpecs(player);
        if (!used.empty())
            SendGlyphs(player);
    }

    // An empty socket in the spec keeps the glyph that's there. A socket still locked by level, a glyph that doesn't
    // fit, and a glyph neither known nor in the bags are skipped. A glyph not known yet uses up its item and is known
    // from then on.
    void Mgr::ApplyGlyphs(Player* player, Profile& profile, Spec const& spec, std::vector<uint32>& skipped,
        std::vector<uint32>& used)
    {
        std::array<uint32, GLYPH_SLOTS> current{};
        std::array<uint32, GLYPH_SLOTS> target{};
        std::array<bool, GLYPH_SLOTS> chosen{};
        for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
        {
            current[slot] = target[slot] = player->GetGlyph(slot);
            uint32 const want = spec.glyphs[slot];
            if (!want || want == current[slot])
            {
                chosen[slot] = want != 0;
                continue;
            }

            Glyphs::Glyph const* glyph = Glyphs::Find(want);
            if (!glyph || !Glyphs::SocketOpen(player, slot) || !Glyphs::Fits(player, slot, *glyph)
                || (!profile.known.count(want) && !player->HasItemCount(glyph->itemId, 1)))
            {
                skipped.push_back(want);
                continue;
            }
            target[slot] = want;
            chosen[slot] = true;
        }

        // A glyph goes in one socket only: a kept socket holding a glyph the spec puts in another one is emptied.
        for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
            if (!chosen[slot] && target[slot])
                for (uint8 other = 0; other < GLYPH_SLOTS; ++other)
                    if (other != slot && chosen[other] && target[other] == target[slot])
                        target[slot] = 0;

        // Every glyph that changes comes out first, so a glyph moving to another socket isn't taken out after it
        // went in.
        for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
            if (target[slot] != current[slot] && current[slot])
                RemoveGlyph(player, slot, current[slot]);

        for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
        {
            if (target[slot] == current[slot] || !target[slot])
                continue;
            Glyphs::Glyph const* glyph = Glyphs::Find(target[slot]);
            if (!profile.known.count(glyph->id))
            {
                player->DestroyItemCount(glyph->itemId, 1, true);
                used.push_back(glyph->id);
                AddKnown(player, profile, glyph->id);
            }
            InscribeGlyph(player, slot, *glyph);
        }
    }

    void Mgr::MarkLoaded(Player* player, Profile& profile, uint32 specId)
    {
        uint8 const group = player->GetActiveSpec();
        if (group >= TALENT_GROUPS)
            return;
        profile.loaded[group] = specId;
        CharacterDatabase.Execute("REPLACE INTO talent_manager_loaded (guid, talent_group, spec_id) "
            "VALUES ({}, {}, {})", player->GetGUID().GetCounter(), group, specId);
    }
}
