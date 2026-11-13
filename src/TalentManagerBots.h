#ifndef MOD_TALENT_MANAGER_BOTS_H
#define MOD_TALENT_MANAGER_BOTS_H

class Player;

// Altbots: playerbots on your own account (random bots never use the talent manager). The addon manages an altbot's
// specs through its master, with requests tagged "@<guid>|" (TalentManagerComms.h). Without playerbots compiled in
// there are no bots and these do nothing.
namespace TalentManager::Bots
{
    // `bot` is a playerbot whose master is `viewer`.
    bool IsMasteredBy(Player* bot, Player* viewer);

    // After a spec load on a bot: playerbots picks its combat strategies from the talents, so they are set up again
    // (as its own "talents spec" command does), and glyphs from a spec are marked as chosen by hand so "maintenance"
    // leaves them alone.
    void AfterLoad(Player* bot, bool glyphsChosen);
}

#endif
