#ifndef MOD_TALENT_MANAGER_MGR_H
#define MOD_TALENT_MANAGER_MGR_H

#include "DatabaseEnvFwd.h"
#include "Define.h"
#include "SharedDefines.h"
#include "TalentManagerTalents.h"
#include <array>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

class Player;

namespace TalentManager
{
    // Protocol version sent in INFO. The addon warns when it doesn't match its own.
    constexpr uint32 PROTOCOL_VERSION = 6;
    constexpr std::size_t MAX_NAME_LENGTH = 32;    // characters; talent_manager_spec.name is VARCHAR(32)
    constexpr uint8 GLYPH_SLOTS = MAX_GLYPH_SLOT_INDEX;
    constexpr uint8 TALENT_GROUPS = 2;              // dual spec (MAX_TALENT_SPECS)

    // Action bars by button (0 to MAX_ACTION_BUTTONS - 1), as ActionButton::packedData: action | type << 24.
    using Bars = std::map<uint8, uint32>;

    struct Spec
    {
        uint32 id = 0;          // per character
        uint32 sort = 0;        // list order
        std::string name;
        std::string talents;    // talent calculator link, shortest form (Talents::Encode)
        std::array<uint32, GLYPH_SLOTS> glyphs{};   // GlyphProperties.dbc ids by socket, 0 = empty
        // The action bars the spec had when another spec was last loaded over it. A spec that was never left has
        // none, and loading it keeps the bars you have.
        Bars bars;
        bool hasBars = false;
    };

    // One character's saved specs, kept in memory while the character is online.
    struct Profile
    {
        std::map<uint32, Spec> specs;
        std::array<uint32, TALENT_GROUPS> loaded{};    // the spec last loaded into each talent group, 0 = none
        std::set<uint32> known;                         // glyphs the character has had in a socket
    };

    class Mgr
    {
    public:
        static Mgr& Instance();

        // Random bot accounts never use the talent manager.
        static bool IsUser(Player* player);

        void OnStartup();
        void OnLogin(Player* player);
        void OnLogout(Player* player);
        void OnDeleteFromDB(CharacterDatabaseTransaction trans, uint32 guid);

        // `body` is "CMD:payload", the text after the TMGR envelope, or "@<guid>|CMD:payload" for one of the player's
        // altbots.
        void HandleAddonMessage(Player* player, std::string const& body);

    private:
        Profile& GetProfile(Player* player);

        void SendInfo(Player* player);
        void SendSpecs(Player* player);
        // You and the online altbots you are master of, for the addon's character picker.
        void SendCharacters(Player* viewer);
        // The talent trees of the player's class, for an addon showing a character of another class.
        void SendTrees(Player* player);
        // The live talents and glyphs, for an addon that can't read them from the client (an altbot's).
        void SendLive(Player* player);

        // The altbot `guid` when `viewer` may manage its talents, else nullptr and an error sent to the viewer.
        Player* ResolveBot(Player* viewer, uint32 guid);

        void HandleSave(Player* player, std::string_view payload);
        void HandleRename(Player* player, std::string_view payload);
        void HandleDelete(Player* player, std::string_view payload);
        void HandleLoad(Player* player, std::string_view payload);

        // Known glyphs: everything ever in a socket, and anything a load inscribed from the bags.
        void SendGlyphs(Player* player);
        // Adds the active talent group's glyphs to the known list. True when one was new.
        bool LearnSocketedGlyphs(Player* player, Profile& profile);
        void AddKnown(Player* player, Profile& profile, uint32 glyphId);

        // TalentManagerLoad.cpp. All of these run with _lock held.
        // Why the player can't change talents now, or empty when they can.
        std::string LoadBlocker(Player* player);
        // Puts the spec on the player: talents, glyphs, then action bars.
        void FinishLoad(Player* player, Spec const& spec, Talents::Build const& build);
        // Puts the spec's glyphs in their sockets. Glyphs that can't go in are added to `skipped`, glyphs inscribed
        // from an item in the bags to `used`.
        void ApplyGlyphs(Player* player, Profile& profile, Spec const& spec, std::vector<uint32>& skipped,
            std::vector<uint32>& used);
        void MarkLoaded(Player* player, Profile& profile, uint32 specId);

        // TalentManagerBars.cpp. Copies the live action bars into the spec (and the database). A button that is
        // empty now because its spell isn't known keeps what the spec had there.
        void StoreBars(Player* player, Spec& spec);
        // The bars to put on when `spec` loads, if any: the other talent group's when the spec is loaded there,
        // else the spec's own.
        bool BarsFor(Player* player, Profile const& profile, Spec const& spec, Bars& bars);
        // Puts the bars on the player. Buttons whose spell isn't known (yet) are left empty.
        void ApplyBars(Player* player, Bars const& bars);

        // Checks a spec name: length, no protocol separators, not used by another spec of this character.
        bool CheckName(Player* player, Profile const& profile, std::string const& name, uint32 exceptId);

        void SaveSpec(Player* player, Spec const& spec);

        // Addon messages and the login, logout and delete hooks may not all run on one thread, so the profiles are
        // used under _lock.
        std::mutex _lock;
        std::unordered_map<uint32, Profile> _profiles;  // by character guid (low)
    };
}

#endif
