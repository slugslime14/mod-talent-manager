#include "TalentManagerTalents.h"
#include "DBCStores.h"
#include "Player.h"
#include "SharedDefines.h"
#include "StringFormat.h"
#include <algorithm>

namespace TalentManager::Talents
{
    namespace
    {
        std::array<std::array<std::vector<TalentEntry const*>, TREES>, MAX_CLASSES> sTrees;
        std::vector<TalentEntry const*> const sNoTree;

        // Index of a talent in its tree's link order, or -1.
        int32 IndexOf(std::vector<TalentEntry const*> const& tree, uint32 talentId)
        {
            for (std::size_t i = 0; i < tree.size(); ++i)
                if (tree[i]->TalentID == talentId)
                    return int32(i);
            return -1;
        }
    }

    void Load()
    {
        for (auto& classTrees : sTrees)
            for (auto& tree : classTrees)
                tree.clear();

        for (uint32 i = 0; i < sTalentStore.GetNumRows(); ++i)
        {
            TalentEntry const* talent = sTalentStore.LookupEntry(i);
            if (!talent)
                continue;

            TalentTabEntry const* tab = sTalentTabStore.LookupEntry(talent->TalentTab);
            if (!tab || !tab->ClassMask || tab->tabpage >= TREES)
                continue;

            for (uint8 classId = 1; classId < MAX_CLASSES; ++classId)
                if (tab->ClassMask & (1 << (classId - 1)))
                    sTrees[classId][tab->tabpage].push_back(talent);
        }

        for (auto& classTrees : sTrees)
            for (auto& tree : classTrees)
                std::sort(tree.begin(), tree.end(), [](TalentEntry const* a, TalentEntry const* b)
                {
                    return a->Row != b->Row ? a->Row < b->Row : a->Col < b->Col;
                });
    }

    std::vector<TalentEntry const*> const& Tree(uint8 classId, uint8 tree)
    {
        if (classId >= MAX_CLASSES || tree >= TREES)
            return sNoTree;
        return sTrees[classId][tree];
    }

    uint8 MaxRank(TalentEntry const* talent)
    {
        uint8 rank = 0;
        for (uint32 spell : talent->RankID)
            if (spell)
                ++rank;
        return rank;
    }

    bool Parse(uint8 classId, std::string_view link, Build& build, std::string& error)
    {
        for (uint8 t = 0; t < TREES; ++t)
            build[t].assign(Tree(classId, t).size(), 0);

        uint8 t = 0;
        std::size_t k = 0;
        for (char c : link)
        {
            if (c == '-')
            {
                if (++t >= TREES)
                {
                    error = "the talent link has too many trees";
                    return false;
                }
                k = 0;
                continue;
            }
            if (c < '0' || c > '9')
            {
                error = "the talent link may only hold digits and '-'";
                return false;
            }

            std::vector<TalentEntry const*> const& tree = Tree(classId, t);
            if (k >= tree.size())
            {
                error = "the talent link has too many talents in a tree";
                return false;
            }
            uint8 const rank = uint8(c - '0');
            if (rank > MaxRank(tree[k]))
            {
                error = "the talent link has a talent above its highest rank";
                return false;
            }
            build[t][k++] = rank;
        }

        for (t = 0; t < TREES; ++t)
        {
            std::vector<TalentEntry const*> const& tree = Tree(classId, t);
            for (std::size_t i = 0; i < tree.size(); ++i)
            {
                if (!build[t][i])
                    continue;

                // Points in the rows above this one.
                uint32 above = 0;
                for (std::size_t j = 0; j < tree.size(); ++j)
                    if (tree[j]->Row < tree[i]->Row)
                        above += build[t][j];
                if (above < tree[i]->Row * POINTS_PER_ROW)
                {
                    error = Acore::StringFormat("a talent in row {} of tree {} needs {} points in the rows above it",
                        tree[i]->Row + 1, t + 1, tree[i]->Row * POINTS_PER_ROW);
                    return false;
                }

                // The prerequisite needs DependsOnRank + 1 points, as Player::LearnTalent checks.
                if (tree[i]->DependsOn)
                {
                    int32 const dep = IndexOf(tree, tree[i]->DependsOn);
                    if (dep < 0 || build[t][dep] < tree[i]->DependsOnRank + 1)
                    {
                        error = Acore::StringFormat("a talent in row {} of tree {} is missing its prerequisite",
                            tree[i]->Row + 1, t + 1);
                        return false;
                    }
                }
            }
        }
        return true;
    }

    uint32 Points(Build const& build)
    {
        uint32 total = 0;
        for (auto const& tree : build)
            for (uint8 rank : tree)
                total += rank;
        return total;
    }

    std::string Encode(Build const& build)
    {
        std::array<std::string, TREES> parts;
        for (uint8 t = 0; t < TREES; ++t)
        {
            for (uint8 rank : build[t])
                parts[t].push_back(char('0' + rank));
            while (!parts[t].empty() && parts[t].back() == '0')
                parts[t].pop_back();
        }

        uint8 last = TREES;
        while (last > 0 && parts[last - 1].empty())
            --last;

        std::string link;
        for (uint8 t = 0; t < last; ++t)
        {
            if (t)
                link.push_back('-');
            link += parts[t];
        }
        return link;
    }

    uint8 LiveRank(Player* player, TalentEntry const* talent)
    {
        for (int8 rank = MAX_TALENT_RANK - 1; rank >= 0; --rank)
            if (talent->RankID[rank] && player->HasTalent(talent->RankID[rank], player->GetActiveSpec()))
                return uint8(rank + 1);
        return 0;
    }

    Build Live(Player* player)
    {
        Build build;
        for (uint8 t = 0; t < TREES; ++t)
        {
            std::vector<TalentEntry const*> const& tree = Tree(player->getClass(), t);
            build[t].resize(tree.size());
            for (std::size_t k = 0; k < tree.size(); ++k)
                build[t][k] = LiveRank(player, tree[k]);
        }
        return build;
    }
}
