#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "TalentManagerComms.h"
#include "TalentManagerConfig.h"
#include "TalentManagerMgr.h"

using namespace TalentManager;

class TalentManagerWorldScript : public WorldScript
{
public:
    TalentManagerWorldScript() : WorldScript("TalentManagerWorldScript", {
        WORLDHOOK_ON_AFTER_CONFIG_LOAD,
        WORLDHOOK_ON_STARTUP
    }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        Cfg().Load();
    }

    void OnStartup() override
    {
        Mgr::Instance().OnStartup();
    }
};

class TalentManagerPlayerScript : public PlayerScript
{
public:
    TalentManagerPlayerScript() : PlayerScript("TalentManagerPlayerScript", {
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LOGOUT,
        PLAYERHOOK_ON_DELETE_FROM_DB,
        PLAYERHOOK_ON_UPDATE,
        PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT
    }) { }

    void OnPlayerUpdate(Player* player, uint32 diff) override
    {
        Mgr::Instance().OnUpdate(player, diff);
    }

    void OnPlayerLogin(Player* player) override
    {
        Mgr::Instance().OnLogin(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        Mgr::Instance().OnLogout(player);
    }

    void OnPlayerDeleteFromDB(CharacterDatabaseTransaction trans, uint32 guid) override
    {
        Mgr::Instance().OnDeleteFromDB(trans, guid);
    }

    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 language, std::string& msg,
        Player* receiver) override
    {
        // The addon whispers itself; swallow those messages so they are never delivered.
        std::string body;
        if (receiver != player || !Comms::Extract(language, msg, body))
            return true;

        Mgr::Instance().HandleAddonMessage(player, body);
        return false;
    }
};

void AddSC_talent_manager_scripts()
{
    new TalentManagerWorldScript();
    new TalentManagerPlayerScript();
}
