WORD FILTER FOR FIVEM
=====================

Blocks slurs in chat and in player names, even when people try to
disguise them (other alphabets, fancy fonts, leetspeak like n1gg3r,
spacing like n i g g e r, hidden characters, upside-down text).


INSTALL
-------
1. Put this "wordfilter" folder in your server's "resources" folder.
2. Add this line to server.cfg:

       ensure wordfilter

   Put it AFTER "ensure chat".
3. Open config.json and set "appealLink" to your Discord invite or
   ticket channel link, so banned players know where to appeal.
4. Restart the server. The console should say "Word filter loaded".


FILTERING /ooc, /me, /twt AND OTHER CHAT COMMANDS
-------------------------------------------------
Chat commands like /ooc are run by other scripts, so the filter can't
see them on its own. Each one needs this one line added:

    if exports['wordfilter']:checkMessage(source, message) then return end

It goes inside the command, right after the line that builds the
message, and before the message is sent to anyone. If it's blocked,
the player gets warned, gets a strike, and the message never shows.

Example (QBCore, resources/[qb]/qb-core/server/commands.lua):

    QBCore.Commands.Add('ooc', ..., function(source, args)
        local message = table.concat(args, ' ')
        if exports['wordfilter']:checkMessage(source, message) then return end   -- add this
        ...

Example (ESX esx_rpchat, server/main.lua):

    RegisterCommand('ooc', function(source, args, rawCommand)
        args = table.concat(args, ' ')
        if exports['wordfilter']:checkMessage(source, args) then return end      -- add this
        ...

To find where a command lives, search your resources folder for the
command name in quotes, e.g. 'ooc'.


BANS AND APPEALS
----------------
When a player hits the strike limit they are banned and shown a ban ID
(like WF-7K2QX) and your appeal link. The ban covers their license,
Discord, Steam and other IDs, so changing their name won't get them in.
Bans are saved in bans.json and survive restarts.

When they open a ticket, ask for their ban ID. To unban them, type in
the server console:

    wordfilter_unban WF-7K2QX

To list everyone who is banned:

    wordfilter_bans

To let staff unban from inside the game, add to server.cfg:

    add_ace group.admin command.wordfilter_unban allow

and they can type /wordfilter_unban WF-7K2QX in chat.

If you set discordWebhook, bans and unbans are posted there with the
ban ID and the exact unban command.


TEST IT BY YOURSELF (no other players needed)
---------------------------------------------
In game, as an admin (needs "add_ace group.admin command allow" in
server.cfg, which QBCore servers already have):

    /wordfilter_testmode
        Turns on test mode for you. Type in chat (and /ooc etc. once
        they have the export line) exactly like a normal player. Blocked
        messages are stopped and you're told what was caught, but you
        never get a strike or a ban, even if you have the bypass.
        Run it again to turn it off.

    /wordfilter_test some text here
        Says BLOCKED or Not blocked (also works in the server console).

    /wordfilter_selftest
        Runs every built-in word through common disguises (leetspeak,
        spacing, dots, fancy letters, hidden characters) plus some normal
        sentences, and prints the score.

If plain chat is blocked in test mode but /ooc isn't, that command
still needs the one export line from the section above.


SETTINGS (config.json)
----------------------
blockChat          true/false - filter chat messages.
checkPlayerNames   true/false - stop players joining with a slur in
                   their name.
kickAfterStrikes   Kick (or ban) a player after this many blocked
                   messages. Set to 0 to never kick (just block).
warningMessage     Shown in chat to the player whose message was blocked.
banOnKick          true  = ban them instead of just kicking. They can't
                           rejoin until staff unban them.
                   false = just kick, they can rejoin straight away.
banDurationHours   0 = banned until staff unban them (appeal needed).
                   Any other number = ban ends by itself after that
                   many hours.
appealLink         Your Discord invite / ticket link. Shown to banned
                   players.
banMessage         What banned players see when kicked and when they
                   try to rejoin. {banId} and {appealLink} get filled in.
kickMessage        Shown when a player is kicked (only if banOnKick is
                   false).
nameKickMessage    Shown when a player's name is blocked.
bypassAce          Players with this permission are not filtered.
                   To let admins bypass, add to server.cfg:
                       add_ace group.admin wordfilter.bypass allow
                   Leave it as "" so nobody bypasses.
discordWebhook     Paste a Discord webhook URL to get a log of blocked
                   messages, or leave "" for none.
customWords        Extra words to block, e.g. ["badword", "*worse*"].
                   Put * around a word to also catch it inside longer
                   words.
allowedWords       Words that should never be blocked, e.g. ["coon"].
                   Car talk: "tranny" (transmission) is blocked by
                   default; add it here if your players need it.

After editing config.json, type this in the console to apply it:

    wordfilter_reload


NOTES
-----
- Plain chat (no /command) is filtered automatically if your chat
  resource fires the normal "chatMessage" event. Commands need the
  one line above.
- Strikes reset when the server restarts. Bans do not.
- Blocked words are listed in server.js near the top if you want to
  look at or edit the built-in list.
