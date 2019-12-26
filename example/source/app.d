import imap;

int main(string[] args)
{
	import std.conv : to;
	import std.stdio : writeln, stderr, writefln;
	import std.range : back;
	import std.process : environment;
	import std.string  : join;
	import std.datetime : Date;

	if (args.length != 4)
	{
		import std.stdio: stderr;
		stderr.writeln("imap-example <server> <port> <mailbox>");
		return -1;
	}

	// user is set in IMAP_USER environmental variable
	// password is set in IMAP_PASS environmental variable

	auto user = environment.get("IMAP_USER","");
	auto pass = environment.get("IMAP_PASS","");

	if (user.length ==0 || pass.length == 0)
	{
		stderr.writeln("./imap-example <server> <port> <mailbox>\n");
		stderr.writeln("eg ./imap-example imap.fastmail.com 993 INBOX");
		return -1;
	}

	auto server = args[1];
	auto port = args[2];
	auto mailbox = args[3];

	auto login = ImapLogin(user,pass);
	auto imapServer = ImapServer(server,port);

	auto session = Session(imapServer,login);
	session.options.debugMode = false;
	session = session.openConnection;
	session = session.login();

	// Select Inbox
	auto INBOX =Mailbox(mailbox,"/",'/');
	auto result = session.select(INBOX);

	// search all messages since 29 Jan 2019 and get UIDs using raw query interface
	auto searchResult = session.search("SINCE 29-Jan-2019");
	writeln(searchResult.value);
	writeln(searchResult.ids);

	// search all messages from GitHub since 29 Jan 2019 and get UIDs using high level query interface
	SearchQuery query = {since:Date(2019,1,29),fromContains:"GitHub"};
	searchResult = session.searchQuery("INBOX",query);
	writeln(searchResult.value);

	// fetch one of the messages from above
	auto messageResult = session.fetchText(searchResult.ids.back.to!string);
	writeln(messageResult.value);

	// just fetch the fields we care about
	auto relevantFields = [ "FROM", "TO" ];
	auto fieldsResult = session.fetchFields(searchResult.ids.back.to!string,relevantFields.join(" "));
	writeln(fieldsResult.value);
	return 0;
}

