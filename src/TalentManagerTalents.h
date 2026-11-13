#ifndef MOD_TALENT_MANAGER_TALENTS_H
#define MOD_TALENT_MANAGER_TALENTS_H

#include "Define.h"
#include <array>
#include <string>
#include <string_view>
#include <vector>

struct TalentEntry;

// A class's talent trees and builds written as talent calculator links: one digit per talent (its rank), talents in
// row then column order, trees in tab order (TalentTab.dbc tabpage) joined by '-'. The same format as Wowhead's
// calculator, playerbots' PremadeSpecLink and the TalentManager addon.
namespace TalentManager::Talents
{
    constexpr uint8 TREES = 3;
    constexpr uint32 POINTS_PER_ROW = 5;

    // Ranks per tree, in link order (same length as the tree).
    using Build = std::array<std::vector<uint8>, TREES>;

    // Builds the per-class tree lists from the DBC stores. Call once at startup.
    void Load();

    // The talents of one tree of a class, in link order.
    std::vector<TalentEntry const*> const& Tree(uint8 classId, uint8 tree);

    uint8 MaxRank(TalentEntry const* talent);

    // Reads `link` for `classId` and checks it against the talent rules (ranks, prerequisites, points per row).
    // On failure returns false and a reason the player can read.
    bool Parse(uint8 classId, std::string_view link, Build& build, std::string& error);

    uint32 Points(Build const& build);

    // The link in its shortest form: trailing zeros and empty trailing trees left out.
    std::string Encode(Build const& build);
}

#endif
