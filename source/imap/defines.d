///
module imap.defines;
import std.stdio;
import deimos.openssl.ssl;
import imap.socket;
import imap.sil : SILdoc;
import core.sys.posix.sys.stat;

static if (is(size_t==uint))
    alias ssize_t=int;
else 
    alias ssize_t=long;


@SILdoc("IMAP protocol supported by the server")
enum ImapProtocol
{
    none = 0,
    imap4Rev1 = 1,
    imap4 = 2,
}

@SILdoc("Capabilities of mail server")
enum Capability
{
	none = 0x00,

	@("NAMESPACE")
    namespace = 0x01,

	@("AUTH=CRAM-MD5")
    cramMD5 = 0x02,

	@("STARTTLS")
    startTLS = 0x04,

	@("CHILDREN")
    children = 0x08,

	@("IDLE")
    idle = 0x10,

	@("IMAP4rev1")
	imap4Rev1,

	@("IMAP4")
	imap4,

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

@SILdoc("Status responses and response codes")
enum ImapStatus
{
    none = 0,

	@("OK")
    ok = 1,

	@("NO")
    no = 2,

	@("BAD")
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

///
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



