import std.stdio;
import std.exception;

import imap;

enum TestUser = "siluser";
enum TestPass = "secret123";

int main(string[] args) {
    if (args.length != 2) {
        writeln("use: ", args[0], " <host>");
        return 1;
    }

    auto session = new Session(ImapServer(args[1], "993"), ImapLogin(TestUser, TestPass));
    session = login(session);
    scope (exit) logout(session);

    auto lsResp = session.list();
    char delim = lsResp.entries[0].hierarchyDelimiter[0];

    // These are some simple emails which live in INBOX.  Some are 'seen' and some are new.  Some
    // are old, some are more recent.
    auto inboxMbox = Mailbox("INBOX", "", delim);
    enforce(session.append(inboxMbox, alice00, [`\Seen`], ` 6-Apr-2019 21:30:13 +0800`).status == ImapStatus.ok);
    enforce(session.append(inboxMbox, alice01, [`\Seen`], `20-Mar-2020 06:53:33 +0800`).status == ImapStatus.ok);
    enforce(session.append(inboxMbox, alice02, [],        `31-Mar-2020 20:40:13 +0800`).status == ImapStatus.ok);
    enforce(session.append(inboxMbox, alice03, [],        ` 9-Dec-2031 12:47:28 +0800`).status == ImapStatus.ok);

    // These are the 'robot' emails which are queried by the `search.sil` script.
    auto supportMbox = Mailbox("support", "", delim);
    session.create(supportMbox);
    enforce(session.append(supportMbox, message00, [], `11-May-2020 22:26:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message01, [], `12-May-2020 12:20:00 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message02, [], `12-May-2020 12:36:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message03, [], `13-May-2020 02:13:20 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message04, [], `13-May-2020 18:53:20 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message05, [], `14-May-2020 03:13:20 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message06, [], `14-May-2020 08:46:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message07, [], `14-May-2020 17:06:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message08, [], `15-May-2020 09:46:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message09, [], `15-May-2020 12:33:20 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message10, [], `15-May-2020 15:20:00 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message11, [], `15-May-2020 18:06:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message12, [], `18-May-2020 12:46:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message13, [], `18-May-2020 15:33:20 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message14, [], `19-May-2020 05:26:40 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message15, [], `19-May-2020 08:13:20 +0400`).status == ImapStatus.ok);
    enforce(session.append(supportMbox, message16, [], `19-May-2020 11:00:00 +0400`).status == ImapStatus.ok);

    // These are to print out a hierarchy of mailboxes.
    session.create(Mailbox("spam"));
    session.create(Mailbox("archive" ~ delim ~ "work"));
    session.create(Mailbox("archive" ~ delim ~ "personal"));

    return 0;
}

private string[] message00 =
    [ `From robot@example.com Mon May 11 22:26:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Mon, 11 May 2020 22:26:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 123`
    , ``
    , `Process 4324 (postfix) crashed.`
    ];

private string[] message01 =
    [ `From robot@example.com Tue May 12 12:20:00 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Tue, 12 May 2020 12:20:00 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Notification: service change`
    , ``
    , `The service 'director' changed from BEMUSED to IDLE.`
    ];

private string[] message02 =
    [ `From robot@example.com Tue May 12 12:36:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Tue, 12 May 2020 12:36:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 124`
    , ``
    , `Too many owls.`
    ];

private string[] message03 =
    [ `From robot@example.com Wed May 13 02:13:20 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Wed, 13 May 2020 02:13:20 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Resolution: issue 124`
    , ``
    , `Issue 124 has been resolved.`
    ];

private string[] message04 =
    [ `From person@example.com Wed May 13 18:53:20 2020`
    , `Return-Path: <person@example.com>`
    , `Date: Wed, 13 May 2020 18:53:20 +0400 (SCT)`
    , `From: person <person@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Email not from robot.`
    , ``
    , `Hello fellow human.  I too am not a robot.  So, how about those {local-sporting-team}?`
    ];

private string[] message05 =
    [ `From robot@example.com Thu May 14 03:13:20 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Thu, 14 May 2020 03:13:20 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 125`
    , ``
    , `We have developed an unhealthy co-dependency.`
    ];

private string[] message06 =
    [ `From robot@example.com Thu May 14 08:46:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Thu, 14 May 2020 08:46:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Resolution: issue 123`
    , ``
    , `Issue 123 has been resolved.`
    ];

private string[] message07 =
    [ `From robot@example.com Thu May 14 17:06:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Thu, 14 May 2020 17:06:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 126`
    , ``
    , `Process 6654 (wget) crashed.`
    ];

private string[] message08 =
    [ `From robot@example.com Fri May 15 09:46:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Fri, 15 May 2020 09:46:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Resolution: issue 126`
    , ``
    , `Issue 126 has been resolved.`
    ];

private string[] message09 =
    [ `From robot@example.com Fri May 15 12:33:20 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Fri, 15 May 2020 12:33:20 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 127`
    , ``
    , `Unexpected reboot.`
    ];

private string[] message10 =
    [ `From robot@example.com Fri May 15 15:20:00 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Fri, 15 May 2020 15:20:00 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Notification: service change`
    , ``
    , `The service 'director' changed from IDLE to ANNOYED.`
    ];

private string[] message11 =
    [ `From robot@example.com Fri May 15 18:06:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Fri, 15 May 2020 18:06:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Resolution: issue 127`
    , ``
    , `Issue 127 has been resolved.`
    ];

private string[] message12 =
    [ `From robot@example.com Mon May 18 12:46:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Mon, 18 May 2020 12:46:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 128`
    , ``
    , `I have both arms stuck in vending machines.`
    ];

private string[] message13 =
    [ `From robot@example.com Mon May 18 15:33:20 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Mon, 18 May 2020 15:33:20 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 129`
    , ``
    , `Process 332 (perl) crashed.`
    ];

private string[] message14 =
    [ `From robot@example.com Tue May 19 05:26:40 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Tue, 19 May 2020 05:26:40 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Resolution: issue 128`
    , ``
    , `Issue 128 has been resolved.`
    ];

private string[] message15 =
    [ `From robot@example.com Tue May 19 08:13:20 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Tue, 19 May 2020 08:13:20 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Notification: service change`
    , ``
    , `The service 'director' changed from ANNOYED to IDLE.`
    ];

private string[] message16 =
    [ `From robot@example.com Tue May 19 11:00:00 2020`
    , `Return-Path: <robot@example.com>`
    , `Date: Tue, 19 May 2020 11:00:00 +0400 (SCT)`
    , `From: robot <robot@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Alert: new issue 130`
    , ``
    , `Maurice's locker is ticking.`
    ];

private string[] alice00 =
    [ `From bob@example.com Sat Apr  6 21:30:13 2019`
    , `Return-Path: <bob@example.com>`
    , `Date: Sat,  6 Apr 2019 21:30:13 +0800 (HKT)`
    , `From: bob <bob@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: I have an idea.`
    , ``
    , `Hi Alice.`
    , ``
    , `I think I can get time travelling to work.  Stay tuned. :)`
    , ``
    , `Bob.`
    ];

private string[] alice01 =
    [ `From carlos@example.com Fri Mar 20 06:53:33 2020`
    , `Return-Path: <carlos@example.com>`
    , `Date: Fri, 20 Mar 2020 06:53:33 +0800 (HKT)`
    , `From: carlos <carlos@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Re: Have you seen Bob?`
    , ``
    , `Alice wrote:`
    , `> Have you seen Bob?  I haven't heard from him in ages.`
    , ``
    , `nope last i heard he was working on time travel`
    ];

private string[] alice02 =
    [ `From carlos@example.com Tue Mar 31 20:40:13 2020`
    , `Return-Path: <carlos@example.com>`
    , `Date: Tue, 31 Mar 2020 20:40:13 +0800 (HKT)`
    , `From: carlos <carlos@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Re: Have you seen Bob?`
    , ``
    , `Alice wrote:`
    , `> Carlos wrote:`
    , `>> Alice wrote:`
    , `>>> Have you seen Bob?  I haven't heard from him in ages.`
    , `>>`
    , `>> nope last i heard he was working on time travel`
    , `>`
    , `> OMG!  Maybe he sucked himself into a black hole?`
    , ``
    , `yah sure`
    ];

private string[] alice03 =
    [ `From bob@example.com Tue Dec  9 12:47:28 2031`
    , `Return-Path: <bob@example.com>`
    , `Date: Tue,  9 Dec 2031 12:47:28 +0800 (HKT)`
    , `From: bob <bob@example.com>`
    , `To: alice <alice@example.com>`
    , `Subject: Greetings from the future!`
    , ``
    , `Hello Alice!`
    , ``
    , `Yes, it worked!  Here I am in 2031!  It's the same!`
    , ``
    , `Future Bob!`
    ];

