
IMAP for D / SIL

Status - usable alpha

Most functions are implemented but parsing responses needs to be done.
Further to that, MIME parsing functionality from another library
needs to be integrated.


Heavily inspired by imapfilter.


Features to add:

- MIME
- pipeFrom
- pipeTo
- more IMAP extensions


```
import imap;

int main(string[] args)
{
	import std.conv : to;
	import std.stdio : writeln;
	import std.range : back;

	if (args.length < 6)
	{
		import std.stdio: stderr;
		stderr.writeln("imap-example <user> <pass> <server> <port> <mailbox>");
		return -1;
	}

	auto user = args[1];
	auto pass = args[2];
	auto server = args[3];
	auto port = args[4];
	auto mailbox = args[5];

	// PASSWORD is set in IMAP_PASS environmental variable if none set here
	auto login = ImapLogin(user,pass);
	auto imapServer = ImapServer(server,port);

	auto session = Session(imapServer,login);
	session = session.openConnection;
	writeln(session.socket);

	session = session.login;
	writeln(session);
	//writeln(socketSecureWrite(session,"HELLO"));
	//writeln(socketSecureRead(session));


	// Select Inbox
	auto INBOX =Mailbox(mailbox,"/",'/');
	auto result = session.select(INBOX);
	writeln(result);

	// search all messages since 29 Jan 2019 and get UIDs
	auto searchResult = session.search("SINCE 29-Jan-2019");
	writeln(searchResult.value);
	writeln(searchResult.ids);

	// search all messages from GitHub since 29 Jan 2019 and get UIDs
	searchResult = session.search(`SINCE 29-Jan-2019 FROM "GitHub"`);
	writeln(searchResult.value);

	// fetch one of the messages from above
	auto messageResult = session.fetchText(searchResult.ids.back.to!string);
	writeln(messageResult.value);

	// just fetch the fields we care about
	auto fieldsResult = session.fetchFields(searchResult.ids.back.to!string,"FROM TO");
	writeln(fieldsResult.value);
	return 0;
}
```
