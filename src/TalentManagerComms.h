#ifndef MOD_TALENT_MANAGER_COMMS_H
#define MOD_TALENT_MANAGER_COMMS_H

#include "Define.h"
#include <string>
#include <string_view>
#include <vector>

class Player;

// Addon protocol. The addon whispers itself with SendAddonMessage("TMGR", "CMD:payload", "WHISPER", me); the server
// answers in kind. Payload fields are ',' separated and list entries ';' separated.
//
// A request about one of your altbots is "@<guid>|CMD:payload". Messages about an altbot go to its master, tagged the
// same way: every Send below takes the character the message is about and finds who gets it.
namespace TalentManager::Comms
{
    // A character with no client of its own (a playerbot).
    bool IsBot(Player* player);

    // Who reads messages about `about`: the player itself, or a bot's master (nullptr when the bot has none).
    // `tag` receives "@<guid>|" for a bot, else nothing.
    Player* Recipient(Player* about, std::string& tag);

    // True when `msg` is an addon whisper for this module; `body` receives the text after the prefix.
    bool Extract(uint32 language, std::string const& msg, std::string& body);

    void Send(Player* player, std::string_view command, std::string_view payload = {});

    // Sends `entries` as one or more `command:` messages, splitting between entries to stay under the wire limit.
    void SendList(Player* player, std::string_view command, std::vector<std::string> const& entries);

    void SendError(Player* player, std::string_view text);
    void SendInfo(Player* player, std::string_view text);
}

#endif
