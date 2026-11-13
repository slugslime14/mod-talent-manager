#include "TalentManagerBots.h"
#include "Player.h"
#include "TalentManagerComms.h"

#if __has_include("PlayerbotAI.h")
#include "AiObjectContext.h"
#include "PlayerbotAI.h"
#include "Playerbots.h"
#define TALENT_MANAGER_PLAYERBOTS
#endif

namespace TalentManager::Bots
{
    bool IsMasteredBy([[maybe_unused]] Player* bot, [[maybe_unused]] Player* viewer)
    {
#ifdef TALENT_MANAGER_PLAYERBOTS
        if (!Comms::IsBot(bot) || !viewer || bot == viewer)
            return false;
        PlayerbotAI* botAI = GET_PLAYERBOT_AI(bot);
        return botAI && botAI->GetMaster() == viewer;
#else
        return false;
#endif
    }

    void AfterLoad([[maybe_unused]] Player* bot, [[maybe_unused]] bool glyphsChosen)
    {
#ifdef TALENT_MANAGER_PLAYERBOTS
        PlayerbotAI* botAI = GET_PLAYERBOT_AI(bot);
        if (!botAI)
            return;
        // The flag EquipGlyphsAction sets: PlayerbotFactory::InitGlyphs then keeps the bot's glyphs.
        if (glyphsChosen)
            botAI->GetAiObjectContext()->GetValue<bool>("custom_glyphs")->Set(true);
        botAI->ResetStrategies();
#endif
    }
}
