[![Build Status](https://travis-ci.org/Laeeth/imap-d.png?branch=master)](https://travis-ci.org/Laeeth/imap-d)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/symmetryinvestments/imap-d?branch=master&svg=true)](https://ci.appveyor.com/project/symmetryinvestments/imap-d)
[![Coverage](https://codecov.io/gh/symmetryinvestments/imap-d/branch/master/graph/badge.svg)](https://codecov.io/gh/symmetryinvestments/imap-d)

# IMAP for D / SIL

## Status - usable alpha
I am starting to use this daily, but there are probably many bugs - please file issues.  PRs welcomed.

### Features that should work (ones without a check may work but be more awkward to use)

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


Heavily inspired by imapfilter.

### Limitations
- currently IMAP literals are only parsed for returns of type responseBody
- only fetchRFC822 works for parsing results (works if you want whole email including
  attachments)
- mailbox UTF7 conversion code is horrible, may not work and needs improving
- more abstraction and better design needed for parsing
- synchronous and single threaded: use processes to start multiple connections for performance


### Features to add

[ ] more IMAP extensions

## Example use

```d
import imap;

int main(string[] args)
{
	import std.conv : to;
	import std.stdio : writeln;
	import std.range : back;
	import std.process : environment 
	
	if (args.length < 6)
	{
		import std.stdio: stderr;
		stderr.writeln("imap-example <user> <server> <port> <mailbox>");
		return -1;
	}

	auto user = args[1];
	auto server = args[2];
	auto port = args[3];
	auto mailbox = args[4];

	auto login = ImapLogin(user,environment.get("IMAP_PASS"));
	auto imapServer = ImapServer(server,port);

	auto session = Session(imapServer,login);
			.openConnection
			.login()
	
	// Select Inbox
	auto INBOX =Mailbox(mailbox,"/",'/');
	auto result = session.select(INBOX);
	
	// search all messages since 29 Jan 2019 and get UIDs
	auto searchResult = session.search("SINCE 29-Jan-2019");
	writeln(searchResult.value);
	writeln(searchResult.ids);
	
	// higher level API
	auto searchResult2 = session.searchQuery(SearchQuery(since:Date(2019,1,29)));

	// search all messages from GitHub since 29 Jan 2019 and get UIDs
	searchResult = session.search(`SINCE 29-Jan-2019 FROM "GitHub"`);
	writeln(searchResult.value);
	
	// higher level API
	searchResult2 = session.searchQuery(SearchQuery(since:Date(2019,1,29),fromContains:"GitHub"));

	// fetch one of the messages from above
	auto messageResult = session.fetchText(searchResult.ids.back.to!string);
	writeln(messageResult.value);

	// just fetch the fields we care about
	auto fieldsResult = session.fetchFields(searchResult.ids.back.to!string,"FROM TO");
	writeln(fieldsResult.value);

	// see example in SIL directory for how to fetch a whole message including attachments
	return 0;
}
```
