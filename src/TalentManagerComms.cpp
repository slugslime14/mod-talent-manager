#include "TalentManagerComms.h"
#include "Chat.h"
#include "Player.h"
#include "SharedDefines.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#if __has_include("PlayerbotAI.h")
#include "PlayerbotAI.h"
#include "Playerbots.h"
#define TALENT_MANAGER_PLAYERBOTS
#endif

namespace TalentManager::Comms
{
    namespace
    {
        constexpr std::string_view ENVELOPE = "TMGR\t";
        // The client drops chat packets whose text exceeds 255 bytes; leave headroom for the envelope.
        constexpr std::size_t MAX_WIRE = 250;

        void SendWire(Player* player, std::string const& wire)
        {
            if (!player || !player->GetSession())
                return;

            WorldPacket data;
            ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, wire);
            player->SendDirectMessage(&data);
        }

        // Free-text fields share the separators of the protocol.
        std::string Clean(std::string_view text)
        {
            std::string out(text);
            for (char& c : out)
                if (c == '\t' || c == '\n' || c == '\r')
                    c = ' ';
            return out;
        }
    }

    bool IsBot(Player* player)
    {
        return player && player->GetSession() && player->GetSession()->IsHeadless();
    }

    Player* Recipient(Player* about, std::string& tag)
    {
        tag.clear();
        if (!about || !about->GetSession())
            return nullptr;
        if (!IsBot(about))
            return about;

#ifdef TALENT_MANAGER_PLAYERBOTS
        if (PlayerbotAI* botAI = GET_PLAYERBOT_AI(about))
        {
            Player* master = botAI->GetMaster();
            if (master && master != about && !IsBot(master))
            {
                tag = "@" + std::to_string(about->GetGUID().GetCounter()) + "|";
                return master;
            }
        }
#endif
        return nullptr;
    }

    bool Extract(uint32 language, std::string const& msg, std::string& body)
    {
        if (language != LANG_ADDON || msg.size() <= ENVELOPE.size() || msg.compare(0, ENVELOPE.size(), ENVELOPE) != 0)
            return false;

        body = msg.substr(ENVELOPE.size());
        return true;
    }

    void Send(Player* player, std::string_view command, std::string_view payload)
    {
        std::string tag;
        Player* to = Recipient(player, tag);
        if (!to)
            return;

        std::string wire(ENVELOPE);
        wire.append(tag);
        wire.append(command);
        wire.push_back(':');
        wire.append(payload);
        if (wire.size() > MAX_WIRE)
            wire.resize(MAX_WIRE);
        SendWire(to, wire);
    }

    void SendList(Player* player, std::string_view command, std::vector<std::string> const& entries)
    {
        std::string tag;
        Player* to = Recipient(player, tag);
        if (!to)
            return;

        std::string header(ENVELOPE);
        header.append(tag);
        header.append(command);
        header.push_back(':');

        std::string wire = header;
        bool empty = true;
        for (std::string const& entry : entries)
        {
            std::size_t const extra = entry.size() + (empty ? 0 : 1);
            if (!empty && wire.size() + extra > MAX_WIRE)
            {
                SendWire(to, wire);
                wire = header;
                empty = true;
            }

            if (!empty)
                wire.push_back(';');
            wire.append(entry);
            empty = false;
        }

        if (!empty)
            SendWire(to, wire);
    }

    void SendError(Player* player, std::string_view text)
    {
        Send(player, "ERR", Clean(text));
    }

    void SendInfo(Player* player, std::string_view text)
    {
        Send(player, "MSG", Clean(text));
    }
}
