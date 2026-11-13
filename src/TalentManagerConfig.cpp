#include "TalentManagerConfig.h"
#include "Config.h"

namespace TalentManager
{
    Config& Cfg()
    {
        static Config config;
        return config;
    }

    void Config::Load()
    {
        enable = sConfigMgr->GetOption<bool>("TalentManager.Enable", true);
        maxSpecs = sConfigMgr->GetOption<uint32>("TalentManager.MaxSpecs", 20);
    }
}
