#include "TalentManagerMgr.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include "Player.h"
#include "StringConvert.h"
#include "StringFormat.h"
#include "TalentManagerComms.h"
#include "TalentManagerConfig.h"
#include "TalentManagerGlyphs.h"
#include "TalentManagerTalents.h"
#include "Tokenize.h"
#include "Util.h"
#include "WorldSession.h"
#include <algorithm>

#if __has_include("PlayerbotAIConfig.h")
#include "PlayerbotAIConfig.h"
#define TALENT_MANAGER_PLAYERBOTS
#endif

namespace TalentManager
{
    namespace
    {
        // A glyph id the client sent for a socket: 0 unless it's a glyph of the player's class that fits the
        // socket. Sockets still locked by level are allowed; a load skips them.
        uint32 CleanGlyph(Player* player, uint8 slot, std::string_view text)
        {
            uint32 const id = Acore::StringTo<uint32>(text).value_or(0);
            Glyphs::Glyph const* glyph = id ? Glyphs::Find(id) : nullptr;
            return glyph && Glyphs::Fits(player, slot, *glyph) ? id : 0;
        }

        std::string LowerName(std::string const& name)
        {
            std::wstring wide;
            if (!Utf8toWStr(name, wide))
                return name;
            wstrToLower(wide);
            std::string out;
            WStrToUtf8(wide, out);
            return out;
        }
    }

    Mgr& Mgr::Instance()
    {
        static Mgr instance;
        return instance;
    }

    bool Mgr::IsUser(Player* player)
    {
        if (!Cfg().enable || !player || !player->GetSession())
            return false;

#ifdef TALENT_MANAGER_PLAYERBOTS
        // Random bots (addclass bots too) live on the rndbot accounts. Altbots are on the player's own account.
        if (sPlayerbotAIConfig.IsInRandomAccountList(player->GetSession()->GetAccountId()))
            return false;
#endif

        return true;
    }

    void Mgr::OnStartup()
    {
        Talents::Load();
        Glyphs::Load();
    }

    void Mgr::OnLogin(Player* player)
    {
        if (!IsUser(player))
            return;
        std::lock_guard<std::mutex> guard(_lock);
        GetProfile(player);
    }

    void Mgr::OnLogout(Player* player)
    {
        std::lock_guard<std::mutex> guard(_lock);
        uint32 const guid = player->GetGUID().GetCounter();
        _profiles.erase(guid);
        if (_swaps.erase(guid))
            _swapCount = uint32(_swaps.size());
    }

    void Mgr::OnDeleteFromDB(CharacterDatabaseTransaction trans, uint32 guid)
    {
        std::lock_guard<std::mutex> guard(_lock);
        _profiles.erase(guid);
        trans->Append("DELETE FROM talent_manager_spec WHERE guid = {}", guid);
        trans->Append("DELETE FROM talent_manager_loaded WHERE guid = {}", guid);
        trans->Append("DELETE FROM talent_manager_glyph WHERE guid = {}", guid);
    }

    Profile& Mgr::GetProfile(Player* player)
    {
        uint32 const guid = player->GetGUID().GetCounter();
        auto [itr, inserted] = _profiles.try_emplace(guid);
        if (!inserted)
            return itr->second;

        Profile& profile = itr->second;
        if (QueryResult result = CharacterDatabase.Query("SELECT id, sort, name, talents, glyph1, glyph2, glyph3, "
            "glyph4, glyph5, glyph6 FROM talent_manager_spec WHERE guid = {}", guid))
        {
            do
            {
                Field* fields = result->Fetch();
                Spec spec;
                spec.id = fields[0].Get<uint32>();
                spec.sort = fields[1].Get<uint32>();
                spec.name = fields[2].Get<std::string>();
                spec.talents = fields[3].Get<std::string>();
                for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
                    spec.glyphs[slot] = fields[4 + slot].Get<uint32>();
                profile.specs.emplace(spec.id, std::move(spec));
            } while (result->NextRow());
        }
        if (QueryResult result = CharacterDatabase.Query("SELECT talent_group, spec_id FROM talent_manager_loaded "
            "WHERE guid = {}", guid))
        {
            do
            {
                Field* fields = result->Fetch();
                uint8 const group = fields[0].Get<uint8>();
                uint32 const specId = fields[1].Get<uint32>();
                if (group < TALENT_GROUPS && profile.specs.count(specId))
                    profile.loaded[group] = specId;
            } while (result->NextRow());
        }

        if (QueryResult result = CharacterDatabase.Query("SELECT glyph_id FROM talent_manager_glyph WHERE guid = {}",
            guid))
        {
            do
            {
                profile.known.insert(result->Fetch()[0].Get<uint32>());
            } while (result->NextRow());
        }
        // Glyphs in either talent group are known. This also fills the list for characters that had glyphs before
        // the module was installed.
        if (QueryResult result = CharacterDatabase.Query("SELECT glyph1, glyph2, glyph3, glyph4, glyph5, glyph6 "
            "FROM character_glyphs WHERE guid = {}", guid))
        {
            do
            {
                Field* fields = result->Fetch();
                for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
                    if (uint32 const glyph = fields[slot].Get<uint32>())
                        AddKnown(player, profile, glyph);
            } while (result->NextRow());
        }
        LearnSocketedGlyphs(player, profile);
        return profile;
    }

    void Mgr::AddKnown(Player* player, Profile& profile, uint32 glyphId)
    {
        if (!Glyphs::Find(glyphId) || !profile.known.insert(glyphId).second)
            return;
        CharacterDatabase.Execute("INSERT IGNORE INTO talent_manager_glyph (guid, glyph_id) VALUES ({}, {})",
            player->GetGUID().GetCounter(), glyphId);
    }

    bool Mgr::LearnSocketedGlyphs(Player* player, Profile& profile)
    {
        std::size_t const before = profile.known.size();
        for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
            if (uint32 const glyph = player->GetGlyph(slot))
                AddKnown(player, profile, glyph);
        return profile.known.size() != before;
    }

    // GLYPHBEGIN:count, then GLYPH: entries "id,spellId,type,itemId,iconId,known" separated by ';', then GLYPHEND:.
    // type is 0 for major, 1 for minor; known is 1 or 0. The addon counts glyph items in the bags itself.
    void Mgr::SendGlyphs(Player* player)
    {
        Profile const& profile = GetProfile(player);
        std::vector<Glyphs::Glyph const*> const& list = Glyphs::ForClass(player->getClass());
        Comms::Send(player, "GLYPHBEGIN", std::to_string(list.size()));
        std::vector<std::string> entries;
        entries.reserve(list.size());
        for (Glyphs::Glyph const* glyph : list)
            entries.push_back(Acore::StringFormat("{},{},{},{},{},{}", glyph->id, glyph->spellId, glyph->type,
                glyph->itemId, glyph->iconId, profile.known.count(glyph->id) ? 1 : 0));
        Comms::SendList(player, "GLYPH", entries);
        Comms::Send(player, "GLYPHEND");
    }

    void Mgr::HandleAddonMessage(Player* player, std::string const& body)
    {
        if (!IsUser(player))
        {
            Comms::SendError(player, "The talent manager is disabled on this server.");
            return;
        }

        std::lock_guard<std::mutex> guard(_lock);
        std::string_view const text(body);
        std::size_t const colon = text.find(':');
        std::string_view const command = text.substr(0, colon);
        std::string_view const payload = colon == std::string_view::npos ? std::string_view() : text.substr(colon + 1);

        if (command == "HELLO")
            SendInfo(player);
        else if (command == "LIST")
            SendSpecs(player);
        else if (command == "SAVE")
            HandleSave(player, payload);
        else if (command == "RENAME")
            HandleRename(player, payload);
        else if (command == "DELETE")
            HandleDelete(player, payload);
        else if (command == "LOAD")
            HandleLoad(player, payload);
        else if (command == "STOP")
            CancelSwap(player, "stopped");
        else if (command == "GLYPHS")
            SendGlyphs(player);
        else if (command == "GSYNC")
        {
            // A glyph was inscribed by hand.
            if (LearnSocketedGlyphs(player, GetProfile(player)))
                SendGlyphs(player);
        }
    }

    // INFO:version,maxSpecs,swapCastMs,talentPoints,activeGroup,groupCount
    // activeGroup is 1-based, as the client's GetActiveTalentGroup() counts.
    void Mgr::SendInfo(Player* player)
    {
        Comms::Send(player, "INFO", Acore::StringFormat("{},{},{},{},{},{}", PROTOCOL_VERSION, Cfg().maxSpecs,
            Cfg().swapCastTime, player->CalculateTalentsPoints(), uint32(player->GetActiveSpec()) + 1,
            uint32(player->GetSpecsCount())));
    }

    // SPECBEGIN:count,maxSpecs,loaded1,loaded2 (the spec loaded in each talent group, 0 for none), then SPEC:
    // entries "id,sort,name,talents,glyph1..glyph6" separated by ';', then SPECEND:. Names never hold ',' or ';'
    // (CheckName).
    void Mgr::SendSpecs(Player* player)
    {
        Profile const& profile = GetProfile(player);
        Comms::Send(player, "SPECBEGIN", Acore::StringFormat("{},{},{},{}", profile.specs.size(), Cfg().maxSpecs,
            profile.loaded[0], profile.loaded[1]));

        std::vector<std::string> entries;
        for (auto const& [id, spec] : profile.specs)
        {
            std::string entry = Acore::StringFormat("{},{},{},{}", spec.id, spec.sort, spec.name, spec.talents);
            for (uint32 glyph : spec.glyphs)
                entry += Acore::StringFormat(",{}", glyph);
            entries.push_back(std::move(entry));
        }
        Comms::SendList(player, "SPEC", entries);
        Comms::Send(player, "SPECEND");
    }

    bool Mgr::CheckName(Player* player, Profile const& profile, std::string const& name, uint32 exceptId)
    {
        std::string copy = name;
        // The byte limit keeps a SPEC entry inside one addon message even for names in other alphabets.
        if (name.empty() || utf8length(copy) > MAX_NAME_LENGTH || name.size() > 2 * MAX_NAME_LENGTH)
        {
            Comms::SendError(player, Acore::StringFormat("A spec name needs 1 to {} characters.", MAX_NAME_LENGTH));
            return false;
        }
        if (name.find_first_of(",;:|\t\r\n") != std::string::npos)
        {
            Comms::SendError(player, "A spec name can't hold , ; : or |.");
            return false;
        }

        std::string const lower = LowerName(name);
        for (auto const& [id, spec] : profile.specs)
        {
            if (id != exceptId && LowerName(spec.name) == lower)
            {
                Comms::SendError(player, Acore::StringFormat("You already have a spec called {}.", spec.name));
                return false;
            }
        }
        return true;
    }

    void Mgr::SaveSpec(Player* player, Spec const& spec)
    {
        std::string name = spec.name;
        CharacterDatabase.EscapeString(name);
        CharacterDatabase.Execute("REPLACE INTO talent_manager_spec (guid, id, sort, name, talents, glyph1, glyph2, "
            "glyph3, glyph4, glyph5, glyph6, updated) VALUES ({}, {}, {}, '{}', '{}', {}, {}, {}, {}, {}, {}, "
            "UNIX_TIMESTAMP())", player->GetGUID().GetCounter(), spec.id, spec.sort, name, spec.talents,
            spec.glyphs[0], spec.glyphs[1], spec.glyphs[2], spec.glyphs[3], spec.glyphs[4], spec.glyphs[5]);
    }

    // SAVE:id,name,talents,glyph1..glyph6. id 0 makes a new spec. Answers SAVED:id and the list.
    void Mgr::HandleSave(Player* player, std::string_view payload)
    {
        std::vector<std::string_view> fields = Acore::Tokenize(payload, ',', true);
        if (fields.size() < 3)
            return;

        Profile& profile = GetProfile(player);
        uint32 const id = Acore::StringTo<uint32>(fields[0]).value_or(0);
        if (id && !profile.specs.count(id))
        {
            Comms::SendError(player, "That spec no longer exists.");
            SendSpecs(player);
            return;
        }
        if (!id && profile.specs.size() >= Cfg().maxSpecs)
        {
            Comms::SendError(player, Acore::StringFormat("You can keep at most {} specs.", Cfg().maxSpecs));
            return;
        }

        std::string const name(fields[1]);
        if (!CheckName(player, profile, name, id))
            return;

        Talents::Build build;
        std::string error;
        if (!Talents::Parse(player->getClass(), fields[2], build, error))
        {
            Comms::SendError(player, "Can't save that spec: " + error + ".");
            return;
        }
        uint32 const points = Talents::Points(build);
        if (points > player->CalculateTalentsPoints())
        {
            Comms::SendError(player, Acore::StringFormat("Can't save that spec: it uses {} talent points and you "
                "have {}.", points, player->CalculateTalentsPoints()));
            return;
        }

        Spec spec;
        if (id)
            spec = profile.specs[id];
        else
        {
            for (auto const& [otherId, other] : profile.specs)
            {
                spec.id = std::max(spec.id, otherId);
                spec.sort = std::max(spec.sort, other.sort);
            }
            ++spec.id;
            ++spec.sort;
        }
        spec.name = name;
        spec.talents = Talents::Encode(build);
        for (uint8 slot = 0; slot < GLYPH_SLOTS; ++slot)
        {
            uint32 const glyph = 3 + slot < fields.size() ? CleanGlyph(player, slot, fields[3 + slot]) : 0;
            // A glyph goes in one socket only, as in the game.
            bool const repeated = std::find(spec.glyphs.begin(), spec.glyphs.begin() + slot, glyph)
                != spec.glyphs.begin() + slot;
            spec.glyphs[slot] = glyph && !repeated ? glyph : 0;
        }

        SaveSpec(player, spec);
        profile.specs[spec.id] = spec;
        Comms::Send(player, "SAVED", std::to_string(spec.id));
        SendSpecs(player);
    }

    // RENAME:id,name
    void Mgr::HandleRename(Player* player, std::string_view payload)
    {
        std::vector<std::string_view> fields = Acore::Tokenize(payload, ',', true);
        if (fields.size() < 2)
            return;

        Profile& profile = GetProfile(player);
        auto itr = profile.specs.find(Acore::StringTo<uint32>(fields[0]).value_or(0));
        if (itr == profile.specs.end())
        {
            SendSpecs(player);
            return;
        }

        std::string const name(fields[1]);
        if (!CheckName(player, profile, name, itr->first))
            return;

        itr->second.name = name;
        SaveSpec(player, itr->second);
        SendSpecs(player);
    }

    // DELETE:id
    void Mgr::HandleDelete(Player* player, std::string_view payload)
    {
        Profile& profile = GetProfile(player);
        uint32 const id = Acore::StringTo<uint32>(payload).value_or(0);
        if (id && profile.specs.erase(id))
        {
            uint32 const guid = player->GetGUID().GetCounter();
            CharacterDatabase.Execute("DELETE FROM talent_manager_spec WHERE guid = {} AND id = {}", guid, id);
            CharacterDatabase.Execute("DELETE FROM talent_manager_loaded WHERE guid = {} AND spec_id = {}", guid, id);
            for (uint32& loaded : profile.loaded)
                if (loaded == id)
                    loaded = 0;
            auto swap = _swaps.find(guid);
            if (swap != _swaps.end() && swap->second.specId == id)
                CancelSwap(player, "deleted");
        }
        SendSpecs(player);
    }
}
