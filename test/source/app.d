import std.stdio;

import imap;

// -------------------------------------------------------------------------------------------------
// These tests depend on a running IMAP server with an IMAP service on port 143 and an IMAPS service
// on port 993.
//
// To keep things simple these tests assume they are run in order and the effects of previous tests
// are present.  We are NOT resetting the state of the server between tests.
//
// Therefore, if one test fails the server may be in an unknown state and no assumptions can be made
// for subsequent tests.  So it's all or none as far as success goes -- as soon as one test fails
// the suite will abort.
//
// That said, each of the tests should leave the server in an empty state, as it found it.

enum TestUser = "mailuser";
enum TestPass = "secret123";

int main(string[] args) {
    if (args.length != 2) {
        writeln("use: ", args[0], " <host>");
        return 1;
    }

    auto runTest = (string name, void function(string) testFn) {
        // args[1] is the host.
        write(name, " - "); testFn(args[1]); writeln("passed.");
    };

    try {
        // Not authenticated state.
        runTest("auth     ", &testAuthentication);
        // Authenticated state.
        runTest("mailbox  ", &testMailboxOps);
        runTest("subscribe", &testSubscriptions);
        runTest("append   ", &testAppend);
        runTest("status   ", &testStatus);
        runTest("select   ", &testSelect);
        // Selected state.
        runTest("copy     ", &testCopy);
        // TODO move/multimove
        runTest("store    ", &testStore);
        runTest("examine  ", &testExamine);
        runTest("close    ", &testCloseExpunge);
        runTest("fetch    ", &testFetch);
        runTest("search   ", &testSearch);
        runTest("uid      ", &testUid);
    } catch (ImapTestException e) {
        writeln("failure: ", e.test, " => ", e.msg);
        return 1;
    } catch (Exception e) {
        writeln("error: library threw: ", e.msg);
        return 1;
    }
    return 0;
}

// -------------------------------------------------------------------------------------------------

class ImapTestException : Exception {
    this(string test, string msg) {
        super(msg);
        test = test;
    }

    string test;
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

private T imapEnforce(T)(T value, string test, string msg) {
    import std.exception;
    return enforce(value, new ImapTestException(test, msg));
}

private bool imapFail(F)(F fn) {
    try {
        fn();
    } catch (Exception e) {
        // Success: the test was supposed to throw.
        return true;
    }
    return false;
}

// -------------------------------------------------------------------------------------------------

private void testAuthentication(string host) {
    {
        auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
        session = session.openConnection();
        session = session.login();
        imapEnforce(session.status == "ok", "auth", "SSL login failure.");
        imapEnforce(session.logout() == ImapStatus.ok, "auth", "SSL logout failure.");
    }
    {
        // Logging in without opening a connection first should still work.
        auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
        session = session.login();
        imapEnforce(session.status == "ok", "auth", "Login without connection failure.");
        imapEnforce(session.logout() == ImapStatus.ok, "auth", "Logout without connection failure.");
    }
    {
        auto session = new Session(ImapServer(host, "993"), ImapLogin("invalidusername", TestPass));
        imapEnforce(imapFail(() => session.login()), "auth", "Bad username succeeded.");
    }
    {
        auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, "incorrectpass"));
        imapEnforce(imapFail(() => session.login()), "auth", "Bad password succeeded.");
    }
    {
        // The server is configured to reject plaintext password authentication over a non-encrypted
        // connection.
        auto session = new Session(ImapServer(host, "143"), ImapLogin(TestUser, TestPass), false);
        session = session.openConnection();
        imapEnforce(imapFail(() => session.login()), "auth", "Able to login without encryption.");
    }
}

// -------------------------------------------------------------------------------------------------

private void testMailboxOps(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    {
        // By default reference is empty, mailbox is '*'.  We expect just INBOX at this stage.
        auto resp = session.list();
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Listing all failed.");
        imapEnforce(resp.entries.length == 1, "mailboxOps", "Listing all != 1 entry.");
        auto entry = resp.entries[0];
        imapEnforce(entry.path == "INBOX", "mailboxOps", "Listing all didn't have INBOX.");
    }

    {
        auto mbox0 = new Mailbox(session, "mbox0");

        auto resp = session.create(mbox0);
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Creating a new mail box (mbox0).");

        resp = session.create(mbox0);
        imapEnforce(resp.status != ImapStatus.ok,
                    "mailboxOps", "Recreating extant mail box (mbox0) succeeded.");

        resp = session.create(new Mailbox(session, "INBOX"));
        imapEnforce(resp.status != ImapStatus.ok,
                    "mailboxOps", "Recreating extant mail box (INBOX) succeeded.");

        // A trailing delimiter indicates intent for sub-mailboxes, and should still work and be
        // stripped from the name.
        char delim = session.namespaceDelim;
        imapEnforce(delim != '\0', "mailboxOps", "Delimiter is not in session?!");

        resp = session.create(new Mailbox(session, "mbox1" ~ delim));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Creating a new mail box (mbox1).");

        resp = session.create(new Mailbox(session, ["mbox2", "sub0", "sub1"]));
        imapEnforce(resp.status == ImapStatus.ok,
                    "mailboxOps", "Creating a new mail box (mbox2.sub0.sub1).");
    }

    {
        import std.algorithm: canFind;
        import std.format: format;

        char delim = session.namespaceDelim;
        imapEnforce(delim != '\0', "mailboxOps", "Delimiter is not in session?!");

        // We should have INBOX, mbox0, mbox1 and mbox2.sub0.sub1 (6 mailboxes).
        auto resp = session.list();
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Listing all again failed.");
        imapEnforce(resp.entries.length == 6, "mailboxOps", "Listing all != 6 entries.");

        resp = session.list("", "mbox*");
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Listing 'mbox*' failed.");
        imapEnforce(resp.entries.length == 5, "mailboxOps", "Listing 'mbox*' != 5 entries.");

        resp = session.list("", "mbox1");
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Listing 'mbox1' failed.");
        imapEnforce(resp.entries.length == 1, "mailboxOps", "Listing 'mbox1' != 1 entries.");

        resp = session.list("mbox2");
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Listing 'mbox2' failed.");
        imapEnforce(resp.entries.length == 3, "mailboxOps", "Listing 'mbox2' != 3 entries.");
        foreach (entry; resp.entries) {
            if (entry.path == "mbox2") {
                imapEnforce(entry.attributes.canFind(ListNameAttribute.hasChildren),
                            "mailboxOps", "mbox2 is missing 'hasChildren' attribute.");
            } else if (entry.path == ("mbox2" ~ delim ~ "sub0")) {
                imapEnforce(entry.attributes.canFind(ListNameAttribute.hasChildren),
                            "mailboxOps", "mbox2.sub0 is missing 'hasChildren' attribute.");
            } else if (entry.path == ("mbox2" ~ delim ~ "sub0" ~ delim ~ "sub1")) {
                imapEnforce(entry.attributes.canFind(ListNameAttribute.hasNoChildren),
                            "mailboxOps", "mbox2.sub0.sub1 is missing 'hasNoChildren' attribute.");
                imapEnforce(!entry.attributes.canFind(ListNameAttribute.hasChildren),
                            "mailboxOps", "mbox2.sub0.sub1 has the 'hasChildren' attribute.");
            } else {
                imapEnforce(false, "mailboxOps", format!"unexpected mailbox name: %s"(entry.path));
            }
        }
    }

    {
        auto mbox0 = new Mailbox(session, "mbox0");
        auto mbox1 = new Mailbox(session, "mbox1");
        auto foo = new Mailbox(session, "foo");

        auto resp = session.rename(mbox1, foo);
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Renaming mbox1 -> foo failed.");

        resp = session.rename(mbox1, new Mailbox(session, "bar"));
        imapEnforce(resp.status != ImapStatus.ok,
                    "mailboxOps", "Renaming non-existent mbox1 -> bar succeeded.");

        resp = session.rename(foo, mbox0);
        imapEnforce(resp.status != ImapStatus.ok,
                    "mailboxOps", "Renaming foo -> existing mbox0 succeeded.");
    }

    {

        auto resp = session.delete_(new Mailbox(session, "mbox0"));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Deleting mbox0 failed.");

        resp = session.delete_(new Mailbox(session, "mbox1"));
        imapEnforce(resp.status != ImapStatus.ok,
                    "mailboxOps", "Deleting non-existing mbox1 succeeded.");

        auto foo = new Mailbox(session, "foo");

        resp = session.delete_(foo);
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Deleting foo failed.");

        resp = session.delete_(foo);
        imapEnforce(resp.status != ImapStatus.ok, "mailboxOps", "Deleting foo twice succeeded.");

        auto lsResp = session.list();
        imapEnforce(lsResp.status == ImapStatus.ok, "mailboxOps", "Listing all after delete failed.");
        imapEnforce(lsResp.entries.length == 4, "mailboxOps", "Listing all after delete != 4 entries.");

        resp = session.delete_(new Mailbox(session, "sub0"));
        imapEnforce(resp.status != ImapStatus.ok, "mailboxOps", "Deleting mbox2.sub0 succeeded.");

        // Deleting mbox2.sub0.sub1 will delete mbox2.sub0 and mbox2 too.
        resp = session.delete_(new Mailbox(session, ["mbox2", "sub0", "sub1"]));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Deleting mbox2.sub0.sub1 failed.");

        lsResp = session.list();
        imapEnforce(lsResp.status == ImapStatus.ok,
                    "mailboxOps", "Listing all after delete all failed.");
        imapEnforce(lsResp.entries.length == 1,
                    "mailboxOps", "Listing all after delete all != 1 entries.");
    }

    {
        // NOTE: All of the namespacing stuff in the RFC is SHOULD or SHOULD NOT (as opposed to MUST).

        auto resp = session.create(new Mailbox(session, "an_&_ampersand"));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Creating a new mail box (ampersand).");
        resp = session.create(new Mailbox(session, "über"));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Creating a new mail box (diacritics).");
        resp = session.create(new Mailbox(session, ["über", "café"]));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Creating a new mail box (diacritics).");

        // Ugh, this delimiter stuff is a pain.  To keep things easy we're enforcing it to be a '.'
        // here.
        char delim = session.namespaceDelim;
        imapEnforce(delim == '.', "mailboxOps", "Delimiter is not a '.' when we would prefer that for these tests.");

        bool foundAmp = false, foundUber = false, foundCafe = false;
        auto lresp = session.list();
        foreach (entry; lresp.entries) {
            switch (entry.path) {
                case "an_&_ampersand": foundAmp  = true; break;
                case "über":           foundUber = true; break;
                case "über.café":      foundCafe = true; break;
                default:               /* INBOX */       break;
            }
        }
        imapEnforce(foundAmp,  "mailboxOps", "Listing an_&_ampersand");
        imapEnforce(foundUber, "mailboxOps", "Listing über");
        imapEnforce(foundCafe, "mailboxOps", "Listing über.café");

        resp = session.delete_(new Mailbox(session, "an_&_ampersand"));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Deleting an_&_ampersand failed.");
        resp = session.delete_(new Mailbox(session, "über"));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Deleting über failed.");
        resp = session.delete_(new Mailbox(session, ["über", "café"]));
        imapEnforce(resp.status == ImapStatus.ok, "mailboxOps", "Deleting über.café failed.");

//        resp = session.create(new Mailbox(session, "with/a/slash"));
    }
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - automatic subscription upon mailbox creation.

private void testSubscriptions(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");
    auto mbox1 = new Mailbox(session, "mbox1");

    session.create(mbox0);
    session.create(mbox1);
    scope(exit) {
        session.delete_(mbox0);
        session.delete_(mbox1);
    }

    auto resp = session.lsub();
    imapEnforce(resp.status == ImapStatus.ok, "subscribe", "Lsub failed.");
    imapEnforce(resp.entries.length == 0, "subscribe", "Empty lsub returned values.");

    auto result = session.subscribe(mbox0);
    imapEnforce(result.status == ImapStatus.ok, "subscribe", "Subscribe to mbox0 failed.");

    resp = session.lsub();
    imapEnforce(resp.status == ImapStatus.ok, "subscribe", "Lsub of * failed.");
    imapEnforce(resp.entries.length == 1, "subscribe", "Lsub of * not single value.");
    imapEnforce(resp.entries[0].path == "mbox0", "subscribe", "Lsub of * not to mbox0.");

    result = session.subscribe(mbox0);
    imapEnforce(result.status == ImapStatus.ok, "subscribe", "Second subscribe to mbox0 failed.");

    resp = session.lsub("", "foobar*");
    imapEnforce(resp.status == ImapStatus.ok, "subscribe", "Lsub of foobar* failed.");
    imapEnforce(resp.entries.length == 0, "subscribe", "Lsub of foobar* not empty.");

    result = session.subscribe(mbox1);
    imapEnforce(result.status == ImapStatus.ok, "subscribe", "Subscribe to mbox1 failed.");

    resp = session.lsub("", "mbo*");
    imapEnforce(resp.status == ImapStatus.ok, "subscribe", "Lsub of mbo* failed.");
    imapEnforce(resp.entries.length == 2, "subscribe", "Lsub of mbo* not 2 values.");

    result = session.unsubscribe(mbox0);
    imapEnforce(result.status == ImapStatus.ok, "subscribe", "Unsubscribe from mbox0 failed.");

    resp = session.lsub("", "mbo*");
    imapEnforce(resp.status == ImapStatus.ok, "subscribe", "2nd Lsub of mbo* failed.");
    imapEnforce(resp.entries.length == 1, "subscribe", "2nd Lsub of mbo* not 1 value.");

    // It's OK to unsubscribe from something not in LSUB results..?
    result = session.unsubscribe(mbox0);
    imapEnforce(result.status == ImapStatus.ok, "subscribe", "2nd unsubscribe from mbox0 failed.");

    result = session.unsubscribe(new Mailbox(session, "nonexistent"));
    imapEnforce(result.status == ImapStatus.ok, "subscribe", "Unsubscribe from nonexistent failed.");

    result = session.unsubscribe(mbox1);
    imapEnforce(result.status == ImapStatus.ok, "subscribe", "Unsubscribe from mbox1 failed.");

    resp = session.lsub();
    imapEnforce(resp.status == ImapStatus.ok, "subscribe", "Lsub failed.");
    imapEnforce(resp.entries.length == 0, "subscribe", "Empty lsub returned values.");
}

// -------------------------------------------------------------------------------------------------

private string[] exampleMessage0 =
    [ `Date: Mon, 7 Feb 1994 21:52:25 -0800 (PST)`
    , `From: Fred Foobar <foobar@Blurdybloop.COM>`
    , `Subject: afternoon meeting`
    , `To: mooch@owatagu.siam.edu`
    , `Message-Id: <B27397-0100000@Blurdybloop.COM>`
    , `MIME-Version: 1.0`
    , `Content-Type: TEXT/PLAIN; CHARSET=US-ASCII`
    , ``
    , `Hello Joe, do you think we can meet at 3:30 tomorrow?`
    , ``
    , `XXX`
    ];

private string[] exampleMessage1 =
    [ `Date: Tue, 8 Feb 1994 11:08:37 -0800 (PST)`
    , `From: Joe Scaramucci <mooch@owatagu.siam.edu>`
    , `Subject: Re: afternoon meeting`
    , `To: Fred Foobar <foobar@Blurdybloop.COM>`
    , `Message-Id: <1791262678.384741@e62ca8cb9b28>`
    , `MIME-Version: 1.0`
    , `Content-Type: TEXT/PLAIN; CHARSET=US-ASCII`
    , ``
    , `new phone who dis?`
    , ``
    , `Fred Foobar wrote:`
    , `> Hello Joe, do you think we can meet at 3:30 tomorrow?`
    , `> `
    , `> XXX`
    ];

private string[] exampleMessage2 =
    [ `From: Brian Kernighan <bwk@cs.princeton.edu>`
    , `Date: Tue, 11 Oct 2011 14:44:56 -0500 (EST)`
    , `Message-ID: <CAGdgZmvj6KO7Qyp4iQj5inXebF@cs.princeton.edu>`
    , `Subject: No, THIS is a tilde.`
    , `To: Dennis Ritchie <dmr@bell-labs.com>`
    , `Content-Type: multipart/related; boundary="000000000000e609c005b32bafc0"`
    , ``
    , `--000000000000e609c005b32bafc0`
    , `Content-Type: multipart/alternative; boundary="000000000000e609be05b32bafbf"`
    , ``
    , `--000000000000e609be05b32bafbf`
    , `Content-Type: text/plain; charset="UTF-8"`
    , ``
    , `Look, just to settle the argument, *this* is a tilde!`
    , ``
    , `[image: tilde.png]`
    , ``
    , `--000000000000e609be05b32bafbf`
    , `Content-Type: text/html; charset="UTF-8"`
    , ``
    , `<div dir="ltr"><div>Look, just to settle the argument, <i>this</i> is a tilde!</div><div><br></div><div><div><img src="cid:ii_kh1fi4ki0" alt="tilde.png" width="18" height="12"><br></div></div></div>`
    , ``
    , `--000000000000e609be05b32bafbf--`
    , `--000000000000e609c005b32bafc0`
    , `Content-Type: image/png; name="tilde.png"`
    , `Content-Disposition: inline; filename="tilde.png"`
    , `Content-Transfer-Encoding: base64`
    , `Content-ID: <ii_kh1fi4ki0>`
    , `X-Attachment-Id: ii_kh1fi4ki0`
    , ``
    , `iVBORw0KGgoAAAANSUhEUgAAABIAAAAMCAIAAADgcHrrAAAAA3NCSVQICAjb4U/gAAAAT0lEQVQo`
    , `U2NgGDmAkZGxsdHl9u2SgwfTnJ2V2dlZGhpcdHTECYSAnp7EmjXRamoi8fFGL19W//7dumNHIhcX`
    , `KwFtyNIsLExCQlwkaBjRSgECvRIrfic4DgAAAABJRU5ErkJggg==`
    , `--000000000000e609c005b32bafc0--`
    , ``
    ];

// TODO:
// - Automatic creation of mailbox.
// - Subscription on create.
// NOTE:
// - we're testing the flags and date is set properly down in `testFetch()` below.

private void testAppend(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");

    session.create(mbox0);
    scope(exit) session.delete_(mbox0);

    auto resp = session.append(mbox0, exampleMessage0);
    imapEnforce(resp.status == ImapStatus.ok, "append", "Append failed.");

    resp = session.append(new Mailbox(session, "notexist"), exampleMessage0);
    imapEnforce(resp.status == ImapStatus.tryCreate,
                "append", "Append to non-existent mailbox should be try-create.");

    resp = session.append(mbox0, exampleMessage1, [`\Seen`, `\Flagged`]);
    imapEnforce(resp.status == ImapStatus.ok, "append", "Append with flags failed.");

    resp = session.append(mbox0, exampleMessage1, [`\Flagged`], " 5-Nov-2020 14:19:28 +1100");
    imapEnforce(resp.status == ImapStatus.ok, "append", "Append with flags and date failed.");
}

// -------------------------------------------------------------------------------------------------

private void testStatus(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");
    session.create(mbox0);
    scope(exit) session.delete_(mbox0);

    auto resp = status(session, mbox0);
    imapEnforce(resp.status = ImapStatus.ok, "status", "Failed to get status of mbox0.");
    imapEnforce(resp.messages == 0 &&
                resp.recent == 0 &&
                resp.unseen == 0, "status", "Bad status for mbox0.");

    session.append(mbox0, exampleMessage0);

    resp = status(session, mbox0);
    imapEnforce(resp.status = ImapStatus.ok, "status", "Failed to get status of mbox0.");
    imapEnforce(resp.messages == 1 &&
                resp.recent == 1 &&
                resp.unseen == 1, "status", "Bad status for mbox0.");
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - Check all the flags and stats are parsed properly.
// - Try different mailbox hierarchies.
// - Getting a BAD response.
// - Removing mailbox when selected (will log you out).

private void testSelect(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto inbox = new Mailbox(session, "INBOX");
    auto resp = session.select(inbox);
    imapEnforce(resp.status == ImapStatus.ok, "select", "Failed to select INBOX.");

    auto mbox0 = new Mailbox(session, "mbox0");
    session.create(mbox0);
    scope(exit) {
        session.select(inbox);
        session.delete_(mbox0);
    }

    resp = session.select(mbox0);
    imapEnforce(resp.status == ImapStatus.ok, "select", "Failed to select mbox0.");

    resp = session.select(new Mailbox(session, "notexist"));
    imapEnforce(resp.status != ImapStatus.ok, "select", "Success selecting non-existent mailbox.");
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - Subscription on create.
// - Try different mailbox hierarchies.

private void testCopy(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");
    auto mbox1 = new Mailbox(session, "mbox1");

    session.create(mbox0);
    session.create(mbox1);
    scope(exit) {
        session.select(new Mailbox(session, "INBOX"));
        session.delete_(mbox0);
        session.delete_(mbox1);
    }
    session.append(mbox0, exampleMessage0);
    session.select(mbox0);

    auto resp = session.copy("#1", mbox1);
    imapEnforce(resp.status == ImapStatus.ok, "copy", "Copy to mbox1 failed.");

    resp = session.copy("#2", mbox1);
    imapEnforce(resp.status != ImapStatus.ok, "copy", "Copy of bad ID to mbox1 succeeded.");

    resp = session.copy("#1", new Mailbox(session, "mbox2"));
    imapEnforce(resp.status == ImapStatus.ok, "copy", "Copy and create to mbox2 failed.");
    scope(exit) session.delete_(new Mailbox(session, "mbox2"));
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - (Fetch response rather than just generic.  It'd be much easier to validate results with it.)
// - (Replace, once we have a fetch response.)
// - Auto expunge in options.

private void testStore(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");

    session.create(mbox0);
    scope(exit) {
        session.select(new Mailbox(session, "INBOX"));
        session.delete_(mbox0);
    }
    session.append(mbox0, exampleMessage0);
    session.select(mbox0);

    auto resp = session.store("#1", StoreMode.add, `\Seen`);
    imapEnforce(resp.status == ImapStatus.ok, "store", "Failed to add Seen flag.");

    resp = session.store("#1", StoreMode.add, `\Flagged`);
    imapEnforce(resp.status == ImapStatus.ok, "store", "Failed to add Flagged flag.");

    resp = session.store("#1", StoreMode.remove, `\Flagged`);
    imapEnforce(resp.status == ImapStatus.ok, "store", "Failed to remove Flagged flag.");

    resp = session.store("#1", StoreMode.add, `\Seen`);
    imapEnforce(resp.status == ImapStatus.ok, "store", "Failed to add Seen flag again.");

    resp = session.store("#1", StoreMode.remove, `\Flagged`);
    imapEnforce(resp.status == ImapStatus.ok, "store", "Failed to remove Flagged flag again.");

    resp = session.store("#1", StoreMode.remove, `\Deleted`);
    imapEnforce(resp.status == ImapStatus.ok, "store", "Failed to remove Deleted flag.");
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - (Get non-generic response info.)
// - Check read-only state.  Not allowed to lose \Recent, nor to delete messages I assume.

private void testExamine(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto inbox = new Mailbox(session, "INBOX");
    auto mbox0 = new Mailbox(session, "mbox0");

    auto resp = session.examine(inbox);
    imapEnforce(resp.status == ImapStatus.ok, "examine", "Failed to examine INBOX.");

    session.create(mbox0);
    scope(exit) {
        session.select(inbox);
        session.delete_(mbox0);
    }
    session.append(mbox0, exampleMessage0);

    resp = session.examine(new Mailbox(session, "notexist"));
    imapEnforce(resp.status != ImapStatus.ok, "examine", "Success examine non-existent mailbox.");

    resp = session.examine(mbox0);
    imapEnforce(resp.status == ImapStatus.ok, "examine", "Failed to examine mbox0.");
}

// -------------------------------------------------------------------------------------------------

private void testCloseExpunge(string host) {
    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");
    auto mbox1 = new Mailbox(session, "mbox1");

    session.create(mbox0);
    session.create(mbox1);
    scope(exit) {
        session.select(new Mailbox(session, "INBOX"));
        session.delete_(mbox0);
        session.delete_(mbox1);
    }
    session.append(mbox0, exampleMessage0);
    session.append(mbox0, exampleMessage1);
    session.select(mbox0);
    session.copy("#1", mbox1);
    session.copy("#2", mbox1);

    session.store("#1", StoreMode.add, `\Deleted`);
    auto statusResp = status(session, mbox0);
    imapEnforce(statusResp.messages == 2, "close", `Message missing after getting flagged \Deleted.`);

    auto resp = session.expunge();
    imapEnforce(resp.status == ImapStatus.ok, "close", "Expunge failed.");
    statusResp = status(session, mbox0);
    imapEnforce(statusResp.messages == 1, "close", "Message not expunged.");

    session.select(mbox1);
    session.store("#2", StoreMode.add, `\Deleted`);
    session.close();

    // Back to authenticated state.  Copy (of the remaining message) shouldn't work.
    resp = session.copy("#1", mbox0);
    imapEnforce(resp.status != ImapStatus.ok, "close", "Still in selected state after close?");

    // It should work if we select mbox1 again.
    session.select(mbox1);
    resp = session.copy("#1", mbox0);
    imapEnforce(resp.status == ImapStatus.ok, "close", "Failed to copy message after close.");

    statusResp = status(session, mbox1);
    imapEnforce(statusResp.messages == 1, "close", "Message not expunged after close.");
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - (fetchFast() to parse its response.)
// - (fetchFlags() parsing seems to be broken.)
// - (fetchSize() to parse its response.)
// - (fetchStructure() to parse its response.)

private void testFetch(string host) {
    import std.algorithm: canFind;

    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");

    session.create(mbox0);
    scope(exit) {
        session.select(new Mailbox(session, "INBOX"));
        session.delete_(mbox0);
    }
    session.append(mbox0, exampleMessage0, [`\Flagged`]);
    session.append(mbox0, exampleMessage2, [], "12-May-2017 09:00:00 +0000");
    session.select(mbox0);

    auto resp = session.fetchFast("#1");
    imapEnforce(resp.status == ImapStatus.ok, "fetch", "Failed fetch fast.");

    auto flagsResp = session.fetchFlags("#1");
    imapEnforce(flagsResp.status == ImapStatus.ok, "fetch", "Failed fetch flags.");
    // The flags should be in flagsResp.flags or flagsResp.ids but don't seem to be.
    imapEnforce(flagsResp.value.canFind(`\Flagged`), "fetch", "Flag missing from message.");

    // The header date of message2 is `Tue, 11 Oct 2011 14:44:56 -0500 (EST)` and by default APPEND
    // will use the current date/time but the internal date we set when appending above is
    // `12-May-2017 09:00:00 +0000`.
    resp = session.fetchDate("#2");
    imapEnforce(resp.status == ImapStatus.ok, "fetch", "Failed fetch date.");
    imapEnforce(resp.value.canFind("12-May-2017"), "fetch", "Fetched date is incorrect.");

    resp = session.fetchSize("#1");
    imapEnforce(resp.status == ImapStatus.ok, "fetch", "Failed fetch size.");

    auto bodyResp = session.fetchHeader("#1");
    imapEnforce(bodyResp.status == ImapStatus.ok, "fetch", "Failed fetch header.");
    imapEnforce(bodyResp.lines.canFind("Subject: afternoon meeting"),
                "fetch", "Failed to find subject in headers.");

    bodyResp = session.fetchRFC822("#1");
    imapEnforce(bodyResp.status == ImapStatus.ok, "fetch", "Failed fetch RFC822.");
    imapEnforce(bodyResp.lines.canFind("Subject: afternoon meeting"),
                "fetch", "Failed to find subject in full message.");
    imapEnforce(bodyResp.lines.canFind("Hello Joe, do you think we can meet at 3:30 tomorrow?"),
                "fetch", "Failed to find body in full message.");

    bodyResp = session.fetchText("#1");
    imapEnforce(bodyResp.status == ImapStatus.ok, "fetch", "Failed fetch text.");
    imapEnforce(bodyResp.lines.length > 0 &&
                bodyResp.lines[0] == "Hello Joe, do you think we can meet at 3:30 tomorrow?",
                "fetch", "Failed to find body in text.");

    bodyResp = session.fetchFields("#1", "from subject");
    imapEnforce(bodyResp.status == ImapStatus.ok, "fetch", "Failed fetch fields (0).");
    imapEnforce(bodyResp.lines.canFind("Subject: afternoon meeting"),
                "fetch", "Failed to find 'subject' in fields.");
    imapEnforce(!bodyResp.lines.canFind("To: mooch@owatagu.siam.edu"),
                "fetch", "Succeeded in finding 'to' in wrong fields.");
    bodyResp = session.fetchFields("#1", "to from");
    imapEnforce(bodyResp.status == ImapStatus.ok, "fetch", "Failed fetch fields (1).");
    imapEnforce(!bodyResp.lines.canFind("Subject: afternoon meeting"),
                "fetch", "Succeeded in finding 'subject' in wrong fields.");
    imapEnforce(bodyResp.lines.canFind("To: mooch@owatagu.siam.edu"),
                "fetch", "Failed to find 'to' in fields.");

    // TODO - Is this structure standard or peculiar to Dovecot?
    resp = session.fetchStructure("#2");
    imapEnforce(resp.status == ImapStatus.ok, "fetch", "Failed fetch struture.");
    imapEnforce(resp.value.canFind(`"image" "png" ("name" "tilde.png") "<ii_kh1fi4ki0>" NIL "base64" 208 NIL ("inline" ("filename" "tilde.png")) NIL NIL`),
                "fetch", "Failed to find inline image in structure.");

    bodyResp = session.fetchPart("#2", "1.1");
    imapEnforce(bodyResp.status == ImapStatus.ok, "fetch", "Failed fetch plaintext part.");
    imapEnforce(bodyResp.lines.canFind("Look, just to settle the argument, *this* is a tilde!"),
                "fetch", "Failed to fetch plaintext part.");
    bodyResp = session.fetchPart("#2", "2");
    imapEnforce(bodyResp.status == ImapStatus.ok, "fetch", "Failed fetch image part.");
    imapEnforce(bodyResp.value.canFind("fTnJ2V2dlZGhpcdHTEC"),
                "fetch", "Failed to fetch image part.");
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - Use proper checks against UIDs -- these assume the UIDs for the messages are just 1, 2 and 3.

private void testSearch(string host) {
    import std.algorithm: canFind;
    import std.conv: to;
    import std.datetime : Date;

    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");

    session.create(mbox0);
    scope(exit) {
        session.select(new Mailbox(session, "INBOX"));
        session.delete_(mbox0);
    }
    session.append(mbox0, exampleMessage0);
    session.append(mbox0, exampleMessage1); // From mooch.
    session.append(mbox0, exampleMessage2);
    session.select(mbox0);

    // With raw search strings.
    auto resp = session.search(`NOT FROM "mooch"`);
    imapEnforce(resp.status == ImapStatus.ok, "search", "Failed search #1.");
    imapEnforce(resp.ids == [1, 3], "search", "Bad results for search #1.");

    resp = session.search(`SENTSINCE 31-Dec-1994`);
    imapEnforce(resp.status == ImapStatus.ok, "search", "Failed search #2.");
    imapEnforce(resp.ids == [3], "search", "Bad results for search #2.");

    resp = session.search(`OR LARGER 1000 BODY "new phone"`);
    imapEnforce(resp.status == ImapStatus.ok, "search", "Failed search #3.");
    imapEnforce(resp.ids == [2, 3], "search", "Bad results for search #3.");

    // Same searches with search expressions.
    resp = session.search(new SearchQuery().not(FieldTerm(FieldTerm.Field.From, "mooch")).to!string);
    imapEnforce(resp.status == ImapStatus.ok, "search", "Failed search #4.");
    imapEnforce(resp.ids == [1, 3], "search", "Bad results for search #4.");

    resp = session.search(new SearchQuery(DateTerm(DateTerm.When.SentSince, Date(1994, 12, 31))).to!string);
    imapEnforce(resp.status == ImapStatus.ok, "search", "Failed search #5.");
    imapEnforce(resp.ids == [3], "search", "Bad results for search #5.");

    resp = session.search(
        new SearchQuery(SizeTerm(SizeTerm.Relation.Larger, 1000))
        .or(FieldTerm(FieldTerm.Field.Body, "new phone")).to!string);
    imapEnforce(resp.status == ImapStatus.ok, "search", "Failed search #6.");
    imapEnforce(resp.ids == [2, 3], "search", "Bad results for search #6.");
}

// -------------------------------------------------------------------------------------------------

// TODO:
// - UIDNEXT is returned by SELECT and we should use it.
// - And FETCH UID rather than a SEARCH to get the new UIDs.

private void testUid(string host) {
    import std.algorithm: canFind;
    import std.conv;

    auto session = new Session(ImapServer(host, "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope(exit) logout(session);

    auto mbox0 = new Mailbox(session, "mbox0");
    auto mbox1 = new Mailbox(session, "mbox1");

    session.create(mbox0);
    session.create(mbox1);
    scope(exit) {
        session.select(new Mailbox(session, "INBOX"));
        session.delete_(mbox0);
        session.delete_(mbox1);
    }
    session.append(mbox0, exampleMessage0);
    session.append(mbox0, exampleMessage1);
    session.append(mbox0, exampleMessage2);
    session.select(mbox0);

    // We have 3 messages in mbox0, probably with UIDs 1, 2 and 3.  Let's delete message '#3' and
    // re-append it and it should have a different UID.

    auto searchResp = session.search(`FROM bwk@cs.princeton.edu`);
    imapEnforce(searchResp.status == ImapStatus.ok && searchResp.ids.length == 1,
                "uid", "Failed to get UID for '#3'.");

    auto origUid = searchResp.ids[0];

    session.store("#3", StoreMode.add, `\Deleted`);
    session.expunge();
    searchResp = session.search(`FROM bwk@cs.princeton.edu`);
    imapEnforce(searchResp.status == ImapStatus.ok && searchResp.ids.length == 0,
                "uid", "Failed to delete '#3'.");

    session.append(mbox0, exampleMessage2);

    searchResp = session.search(`FROM bwk@cs.princeton.edu`);
    imapEnforce(searchResp.status == ImapStatus.ok && searchResp.ids.length == 1,
                "uid", "Failed to get *new* UID for '#3'.");

    auto newUid = searchResp.ids[0];
    imapEnforce(newUid > origUid, "uid", "New UID is not greater than original UID.");

    auto origUidStr = text(origUid);
    auto newUidStr = text(newUid);

    // So now try some COPY, STORE and FETCH operations using the UIDs rather than '#n' sequence IDs.

    auto resp = session.copy(newUidStr, mbox1);
    imapEnforce(resp.status == ImapStatus.ok, "uid", "Copy to mbox1 by UID failed.");
    resp = session.copy(origUidStr, mbox1);
    imapEnforce(resp.status == ImapStatus.ok && resp.value.canFind(`No messages found`),
                "uid", "Copy of bad UID to mbox1 succeeded.");

    resp = session.store(newUidStr, StoreMode.add, `\Flagged`);
    imapEnforce(resp.status == ImapStatus.ok, "uid", "Failed to flag '#3' by UID.");
    resp = session.store(origUidStr, StoreMode.add, `\Flagged`);
    // STORE on a missing message seems to succeed anyway, as a no-op I guess.
    imapEnforce(resp.status == ImapStatus.ok, "uid", "Failed to flag missing message by stale UID.");

    // Parsing is broken, just check the value.
    auto flagsResp = session.fetchFlags(newUidStr);
    imapEnforce(flagsResp.status == ImapStatus.ok && flagsResp.value.canFind(`\Flagged`),
                "uid", "Failed to fetch flags by UID.");
    flagsResp = session.fetchFlags(origUidStr);
    imapEnforce(flagsResp.status == ImapStatus.ok && !flagsResp.value.canFind(`\Flagged`),
                "uid", "Succeeded fetching flags by stale UID.");
}

// -------------------------------------------------------------------------------------------------
