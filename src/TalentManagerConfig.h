#ifndef MOD_TALENT_MANAGER_CONFIG_H
#define MOD_TALENT_MANAGER_CONFIG_H

#include "Define.h"

namespace TalentManager
{
    struct Config
    {
        bool enable = true;
        uint32 maxSpecs = 20;       // saved specs per character

        void Load();
    };

    Config& Cfg();
}

#endif
