[![Build Status](https://travis-ci.org/symmetryinvestments/imap-d.svg?branch=master)](https://travis-ci.org/symmetryinvestments/imap-d)
[![Build status](https://ci.appveyor.com/api/projects/status/mpti6h28igwso71e/branch/master?svg=true)](https://ci.appveyor.com/project/Laeeth/imap-d/branch/master)
[![Coverage](https://codecov.io/gh/symmetryinvestments/imap-d/branch/master/graph/badge.svg)](https://codecov.io/gh/symmetryinvestments/imap-d)

# IMAP and JMAP for D / SIL

## Status - usable alpha
I am starting to use this daily, but there are probably many bugs - please file issues.  PRs welcomed.

### IMAP Features that should work (ones without a check may work but be more awkward to use)

- [X] session capabilities
- [X] copy message
- [X] create mailbox
- [X] createQuery (higher level API for IMAP search)
- [X] delete_ mailbox
- [X] esearch
- [X] examine
- [X] expunge
- [X] fetchFast
- [X] fetchFields
- [ ] fetchFlags
- [X] fetchHeader
- [ ] fetchPart
- [X] fetchRFC822 - whole email fetch and parse
- [ ] fetchSize
- [ ] fetchStructure
- [ ] fetchText
- [X] idle
- [X] list
- [X] login
- [X] logout
- [X] lsub
- [X] move
- [X] moveUIDs
- [X] multiMove
- [X] multiSearch - search multiple mailboxes (sadly not widely supported on IMAP servers)
- [X] noop
- [X] raw IMAP command
- [X] search
- [X] searchQuery
- [X] select
- [X] status
- [X] store
- [X] subscribe
- [X] unsubscribe

### JMAP Features that should work (ones without a check may work but have not yet been tested)

- [X] Email
- [ ] Contacts
- [ ] Calendar


Heavily inspired by imapfilter.

### Limitations
- currently IMAP literals are only parsed for returns of type responseBody
- only fetchRFC822 works for parsing results (works if you want whole email including
  attachments)
- mailbox UTF7 conversion code is horrible, may not work and needs improving
- more abstraction and better design needed for parsing
- synchronous and single threaded: use processes to start multiple connections for performance
- JMAP depends on internal Symmetry Variable type and will require changes to work without it


### Features to add

[ ] more IMAP extensions
[ ] more JMAP capabilities

## Example use

```d
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
```

