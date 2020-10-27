import std.conv, std.stdio;

import imap;

int main(string[] args) {
    if (args.length != 3) {
        writeln("use: ", args[0], " <host> <port>");
        return 1;
    }

    string host = args[1];
    string port = args[2];
    try
        to!int(args[2]);
    catch (ConvException ) {
        writeln("error: port must be an integer.");
        return 1;
    }

    writeln("Connecting to ", host, " on port ", port);

    auto login = ImapLogin("mailuser", "secret123");
    auto server = ImapServer(host, port);

    auto session = Session(server, login);
    session = session.openConnection();
    session = session.login();
    scope(exit) session.logout();

    auto inbox = Mailbox("INBOX", "", '/');
    auto selectResult = session.select(inbox);
    if (selectResult.status != ImapStatus.ok) {
        writeln("error: selecting INBOX: ", selectResult.value);
        return 1;
    }

    auto statusResult = status(session, inbox);
    if (statusResult.status != ImapStatus.ok) {
        writeln("error: status for INBOX: ", statusResult.value);
        return 1;
    }
    writeln(statusResult.messages, " messages in inbox.");

    return 0;
}
