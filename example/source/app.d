import imap;

int main(string[] args) {
    import std.conv : to;
    import std.stdio : writeln, stderr;
    import std.range : back;
    import std.process : environment;
    import std.string : join;
    import std.datetime : Date;

    if (args.length != 4) {
        stderr.writeln("imap-example <server> <port> <mailbox>");
        return -1;
    }

    // user is set in IMAP_USER environmental variable
    // password is set in IMAP_PASS environmental variable

    auto user = environment.get("IMAP_USER", "");
    auto pass = environment.get("IMAP_PASS", "");

    if (user.length == 0 || pass.length == 0) {
        stderr.writeln("IMAP_USER and IMAP_PASS environment variables must be set.");
        return -1;
    }

    auto server = args[1];
    auto port = args[2];
    auto mailbox = args[3];

    auto login = ImapLogin(user, pass);
    auto imapServer = ImapServer(server, port);

    auto session = new Session(imapServer, login);
    session.options.debugMode = false;
    session = session.openConnection;
    session = session.login();

    // Select Inbox
    auto INBOX = Mailbox(mailbox, "", '/');
    auto result = session.select(INBOX);

    // search all messages since 29 Jan 2019 and get UIDs using raw query interface
    auto searchResult = session.search("SINCE 29-Jan-2019");
    writeln("--- Raw 'SINCE 29-Jan-2019' search results:");
    writeln(searchResult.value);
    writeln("--- Search result IDs: ", searchResult.ids);

    // search all messages from GitHub since 29 Jan 2019 and get UIDs using high level query interface
    auto query = new SearchQuery()
        .and(DateTerm(DateTerm.When.Since, Date(2019, 1, 29)))
        .and(FieldTerm(FieldTerm.Field.From, "GitHub"));
    searchResult = session.search(query.to!string);
    writeln("--- Structured 'since:Date(2019,1,29),fromContains:\"GitHub\"' search results:");
    writeln(searchResult.value);

    // fetch one of the messages from above
    if (searchResult.ids.length > 0) {
        auto exampleId = searchResult.ids.back.to!string;
        auto messageResult = session.fetchText(exampleId);
        writeln("--- Message text for ID ", exampleId, ":");
        writeln(messageResult.value);

        // just fetch the fields we care about
        auto relevantFields = ["FROM", "TO"];
        auto fieldsResult = session.fetchFields(exampleId, relevantFields.join(" "));
        writeln("--- Message 'from' and 'to' fields for ID ", exampleId, ":");
        writeln(fieldsResult.value);
    }
    return 0;
}
