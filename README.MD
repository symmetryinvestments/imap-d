
IMAP for D / SIL

Status - usable alpha

Most functions are implemented but parsing responses needs to be done.
Further to that, MIME parsing functionality from another library
needs to be integrated.

Heavily inspired by imapfilter.

```
// PASSWORD is set in IMAP_PASS environmental variable
login = imap.ImapLogin("laeeth@kaleidic.io","")
server = imap.ImapServer("imap.fastmail.com","993")

session = imap.Session(server,login)
session=imap.openConnection(session)
print(session.socket)
session = imap.login(session);

print(session)
//print(imap.socketSecureWrite(session,"HELLO"))
//print(imap.socketSecureRead(session))


// Select Inbox
INBOX =imap.Mailbox("INBOX/kaleidic","/",'/')
result = imap.select(session,INBOX)
print(result)

// search all messages since 29 Jan 2019 and get UIDs
result=imap.search(session,"SINCE 29-Jan-2019")
print(result.value)

// search all messages since 29 Jan 2019 and get UIDs
result=imap.search(session,"SINCE 29-Jan-2019 FROM \"John Colvin\"")
print(result.value)

// search all messages from GitHub since 29 Jan 2019 and get UIDs
result=imap.search(session,"SINCE 29-Jan-2012 FROM \"Github\"")
print(result.value)

// fetch one of the messages from above
message_result = imap.fetchText(session,"70290")
print(message_result.value)

```
