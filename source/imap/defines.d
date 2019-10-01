module imap.defines;
import std.stdio;
version(SSL) import deimos.openssl.ssl;
import imap.socket;
// import imap.regex;
import core.sys.posix.sys.stat;
enum VERSION="2.6.2";
enum COPYRIGHT="Copyright (c) 2001-2015 Eleftherios Chatzimparmpas";
enum ConfigSharedir="/usr/share/imapd";

static if (is(size_t==uint))
    alias ssize_t=int;
else 
    alias ssize_t=long;

/* Fatal error exit codes. */
enum Error
{
    signal = 1,
    config = 2,
    memAlloc = 3,
    pathname = 4,
    certificate = 5,
}

/* IMAP protocol supported by the server. */
enum ImapProtocol
{
    none = 0,
    imap4Rev1 = 1,
    imap4 = 2,
}

/* Capabilities of mail server. */
enum Capability
{
    none = 0x00,
    namespace = 0x01,
    cramMD5 = 0x02,
    startTLS = 0x04,
    children = 0x08,
    idle = 0x10,

	@("LITERAL+")
	literalPlus,

	@("ID")
	id,

	@("ENABLE")
	enable,

	@("ACL")
	acl,

	@("RIGHTS=kxten")
	rightsKxTen,

	@("QUOTA")
	quota,

	@("MAILBOX-REFERRALS")
	mailboxReferrals,

	@("UIDPLUS")
	uidPlus,

	@("NO_ATOMIC_RENAME")
	noAtomicRename,

	@("UNSELECT")
	unselect,

	@("MULTIAPPEND")
	multiAppend,

	@("BINARY")
	binary,

	@("CATENATE")
	catenate,

	@("CONDSTORE")
	condStore,

	@("ESEARCH")
	esearch,

	@("SEARCH=FUZZY")
	fuzzySearch,

	@("SORT")
	sort,

	@("SORT=MODSEQ")
	sortModSeq,

	@("SORT=DISPLAY")
	sortDisplay,

	@("SORT=UID")
	sortUID,

	@("THREAD=ORDEREDSUBJECT")
	threadOrderedSubject,

	@("THREAD=REFERENCES")
	threadReferences,

	@("THREAD=REFS")
	threadRefs,

	@("ANNOTATE-EXPERIMENT-1")
	annotateExperiment1,

	@("METADATA")
	metadata,

	@("LIST-EXTENDED")
	listExtended,

	@("LIST-STATUS")
	listStatus,

	@("LIST-MYRIGHTS")
	listMyRights,

	@("LIST-METADATA")
	listMetadata,

	@("WITHIN")
	within,

	@("QRESYNC")
	qResync,

	@("SCAN")
	scan,

	@("XLIST")
	xlist,

	@("MOVE")
	move,

	@("SPECIAL-USE")
	specialUse,

	@("CREATE-SPECIAL-USE")
	createSpecialUse,

	@("DIGEST=SHA1")
	digestSHA1,

	@("X-REPLICATION")
	xReplication,

	@("STATUS=SIZE")
	statusSize,

	@("OBJECTID")
	objectID,

	@("SAVEDATE")
	saveDate,

	@("X-CREATEDMODSEQ")
	xCreatedModSeq,

	@("PREVIEW=FUZZY")
	previewFuzzy,

	@("XAPPLEPUSHSERVICE")
	xApplePushService,

	@("LOGINDISABLED")
	loginDisabled,

	@("XCONVERSATIONS")
	xConversations,

	@("COMPRESS=DEFLATE")
	compressDeflate,

	@("X-QUOTA=STORAGE")
	xQuoteStorage,

	@("X-QUOTA=MESSAGE")
	xQuotaMessage,

	@("X-QUOTA=X-ANNOTATION-STORAGE")
	xQuotaXAnnotationStorage,

	@("X-QUOTA=X-NUM-FOLDERS")
	xQuotaXNumFolders,

	@("XMOVE")
	xMove,
}

/* Status responses and response codes. */
enum ImapStatus
{
    none = 0,
    ok = 1,
    no = 2,
    bad = 3,
    untagged = 4,
    continue_ = 5,
    bye = 6,
    preAuth = 7,
    readOnly = 8,
    tryCreate = 9,
    timeout = 10,
	unknown = -1,
}

/* Initial size for buffers. */
enum BufferSize
{
    input = 4096,
    output = 1024,
    namespace = 512,
    conversion = 512,
}

enum Pathname
{
    // Lua imap set functions file.
    common=ConfigSharedir~"/common.lua",

    /* Lua imap set functions file. */
    set=ConfigSharedir~"/set.lua",

    /* Lua imap account functions file. */
    account=ConfigSharedir~"/account.lua",

    /* Lua imap mailbox functions file. */
    mailbox=ConfigSharedir~ "/mailbox.lua",

    /* Lua imap message functions file. */
    message=ConfigSharedir~ "/message.lua",

    /* Lua imap message functions file. */
    options=ConfigSharedir~"/options.lua",

    /* Lua imap regex functions file. */
    regex=ConfigSharedir~"/regex.lua",

    /* Lua imap auxiliary functions file. */
    auxiliary=ConfigSharedir~"/auxiliary.lua",
}

enum ImapFlag
{
	@(`\Seen`)
	seen,

	@(`\Answered`)
	answered,

	@(`\Flagged`)
	flagged,

	@(`\Deleted`)
	deleted,

	@(`\Draft`)
	draft,
}

// Maximum length, in bytes, of a utility's input line.
enum LineMax=2048;


// Program's options.
struct Options
{
	int verbose;       // Verbose mode.
	int interactive;   // Act as an interpreter.
	string log;		   // Log file for error messages.
	string config;      // Configuration file.
	string oneline;     // One line of program/configuration.
	string debug_;       // Debug file.
    string truststore;  // CA TrustStore.
}
Options options;

/* Environment variables. */
struct Environment
{
	string home;		   // Program's home directory
	long pathmax;	   // Maximum pathname.
}
Environment environment;


// Temporary buffer.
struct Buffer
{
    string data;     /* Text or binary data. */
    size_t len;     /* Length of text or binary data. */
    size_t size;        /* Maximum size of data. */
}


// Regular expression convenience structure.
struct Regexp
{
    string pattern;   // Regular expression pattern string
	// FIXME
    // regex_t *preg;              // Compiled regular expression
    size_t nmatch;              // Number of subexpressions in pattern
    // regmatch_t *pmatch;         // Structure for substrings that matched
}

version(None)
extern(C)
{
    /*	auth.c		*/
    string auth_cram_md5(string  user, string  pass,
        string chal);

    /*	cert.c		*/
    int get_cert(Session *ssn);

    /*	core.c		*/
     int luaopen_ifcore(lua_State *lua);

    /*	file.c		*/
    void create_homedir() ;
    int exists_file(string fname);
    int exists_dir(string fname);
    int create_file(string fname, mode_t mode);
    int get_pathmax() ;
    string get_filepath(string fname);

    /*	log.c		*/
    void verbose(string  info,...);
    pragma(mangle, "debug") extern(C) void debug_func(string  debug_,...);
    void debugc(char c);
    void error(string  errmsg,...);
    void fatal(uint  errnum, string  fatal,...);

    int open_debug() ;
    int close_debug() ;

    int open_log() ;
    int close_log() ;

    /*	lua.c	*/
    void start_lua() ;
    void stop_lua() ;

    int get_option_boolean(string  opt);
    lua_Number get_option_number(string  opt);
    string  get_option_string(string  opt);

    int set_table_boolean(string  key, int value);
    int set_table_number(string  key, lua_Number value);
    int set_table_string(string  key, string  value);

    /*	memory.c	*/
    void *xmalloc(size_t size);
    void *xrealloc(void *ptr, size_t size);
    void xfree(void *ptr);
    string xstrdup(string  str);
    string xstrndup(string  str, size_t len);

    /*	misc.c		*/
    string  xstrcasestr(string  haystack, string  needle);
    string xstrncpy(string dest, string  src, size_t size);

    /*	namespace.c	*/
    string  apply_namespace(string  mbox, string prefix, char delim);
    string  reverse_namespace(string  mbox, string prefix, char delim);

    /*	pcre.c		*/
    int luaopen_ifre(lua_State *lua);

    /*	request.c	*/
    int request_noop(Session *ssn);
    int request_login(Session **ssn, string  server, string  port, const
        string protocol, string  user, string  pass);
    int request_logout(Session *ssn);
    int request_status(Session *ssn, string  mbox, uint*  exist,
        uint*  recent, uint*  unseen, uint*  uidnext);
    int request_select(Session *ssn, string  mbox);
    int request_close(Session *ssn);
    int request_expunge(Session *ssn);
    int request_list(Session *ssn, string  refer, string  name, char
        **mboxs, string *folders);
    int request_lsub(Session *ssn, string  refer, string  name, char
        **mboxs, string *folders);
    int request_search(Session *ssn, string  criteria, string  charset,
        string *mesgs);
    int request_fetchfast(Session *ssn, string  mesg, string *flags, char
        **date, string *size);
    int request_fetchflags(Session *ssn, string  mesg, string *flags);
    int request_fetchdate(Session *ssn, string  mesg, string *date);
    int request_fetchsize(Session *ssn, string  mesg, string *size);
    int request_fetchstructure(Session *ssn, string  mesg, string *structure);
    int request_fetchheader(Session *ssn, string  mesg, string *header, size_t
        *len);
    int request_fetchtext(Session *ssn, string  mesg, string *text, size_t
        *len);
    int request_fetchfields(Session *ssn, string  mesg, const char
        *headerfields, string *fields, size_t *len);
    int request_fetchpart(Session *ssn, string  mesg, string  bodypart,
        string *part, size_t *len);
    int request_store(Session *ssn, string  mesg, string  mode, const char
        *flags);
    int request_copy(Session *ssn, string  mesg, string  mbox);
    int request_append(Session *ssn, string  mbox, string  mesg, size_t
        mesglen, string  flags, string  date);
    int request_create(Session *ssn, string  mbox);
    int request_delete(Session *ssn, string  mbox);
    int request_rename(Session *ssn, string  oldmbox, string  newmbox);
    int request_subscribe(Session *ssn, string  mbox);
    int request_unsubscribe(Session *ssn, string  mbox);
    int request_idle(Session *ssn, string *event);

    /*	response.c	*/
    int response_generic(Session *ssn, int tag);
    int response_continuation(Session *ssn, int tag);
    int response_greeting(Session *ssn);
    int response_capability(Session *ssn, int tag);
    int response_authenticate(Session *ssn, int tag, char** cont);
    int response_namespace(Session *ssn, int tag);
    int response_status(Session *ssn, int tag, uint*  exist, uint*  recent, uint*  unseen, uint*  uidnext);
    int response_examine(Session *ssn, int tag, uint*  exist, uint*  recent);
    int response_select(Session *ssn, int tag);
    int response_list(Session *ssn, int tag, string *mboxs, string *folders);
    int response_search(Session *ssn, int tag, string *mesgs);
    int response_fetchfast(Session *ssn, int tag, string *flags, string *date, string *size);
    int response_fetchflags(Session *ssn, int tag, string *flags);
    int response_fetchdate(Session *ssn, int tag, string *date);
    int response_fetchsize(Session *ssn, int tag, string *size);
    int response_fetchstructure(Session *ssn, int tag, string *structure);
    int response_fetchbody(Session *ssn, int tag, string *body_, size_t *len);
    int response_idle(Session *ssn, int tag, string *event);

    /*	signal.c	*/
    void catch_signals();
    void release_signals();

    /*	socket.c	*/
    int open_connection(Session *ssn);
    int close_connection(Session *ssn);
    ssize_t socket_read(Session *ssn, string buf, size_t len, long timeout, int timeoutfail);
    ssize_t socket_write(Session *ssn, string  buf, size_t len);
    int open_secure_connection(Session *ssn);
    int close_secure_connection(Session *ssn);
    ssize_t socket_secure_read(Session *ssn, string buf, size_t len);
    ssize_t socket_secure_write(Session *ssn, string  buf, size_t len);

    /*	system.c	*/
     int luaopen_ifsys(lua_State *lua);
}
