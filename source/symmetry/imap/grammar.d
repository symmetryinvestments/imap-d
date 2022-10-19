///
module symmetry.imap.grammar;

/++
    This code is not currently used or required.  An experiment with replacing custom parsing code by
    a PEG grammer.
+/

version (SIL) :
    import pegged.grammar;


///
public PT tee(PT)(PT p) {
    import std.stdio;
    writeln("****");
    writeln(p);
    writeln("****");
    return p;
}


mixin(grammar(`
Imap:
	Expr			<-  ((whitespace)* Response)*
	whitespace		<-	[\r\n \t]
	dash			<-	"-"
	plus			<-	"+"
	colon			<-	":"
	comma			<-	","
	bang            <-	"!"
	star			<-	"*"
	percent			<-	"%"
	LParens			<-	"("
	RParens			<-	")"

	LowerCase		<-	[a-z]
	UpperCase		<-	[A-Z]
	Alpha			<-	[a-zA-Z]
	HexDigit		<-	[a-f0-9A-F]
	Digit			<-	[0-9]
	DigitNonZero	<-	[1-9]
	Digits			<~	[0-9]+
	Zero			<-	"0"
	Number			<-	Digits # unsigned 32 bit/check size
	NzNumber		<-	!Zero Digits
	Underscore		<-	"_"
	Base64Char		<-	[a-zA-Z0-9\+\/]
	Base64Terminal	<-	(Base64Char Base64Char "==") / (Base64Char Base64Char Base64Char "=")
	Base64			<~	Base64Char Base64Char Base64Char Base64Char Base64Terminal
	StrChar         <~ backslash doublequote
	                    / backslash backslash
	                    / backslash [abfnrtv]
	                    / (!doublequote .)
	CRLF			<-	"\r" "\n"
	TextChar		<-	!CRLF .
	Text			<-	Text+
	Char			<-	!"\0" .
	#literal			<-	"{" Number "}" CRLF Char*
	Literal			<-	Alpha*
	QuotedSpecial	<-	doublequote / backslash
	QuotedChar		<-	(!QuotedSpecial TextChar) / (backslash QuotedSpecial)
	Quoted			<~	doublequote QuotedChar* doublequote
	String			<-	Quoted / Literal
	CTL				<-	"\a" "\b"
	ListWildCard	<-	"%" / star
	RespSpecial		<- "]"
	AtomSpecial		<-	LParens / RParens / "{" / space / CTL / ListWildCard / QuotedSpecial / RespSpecial
	AtomChar		<-	!AtomSpecial Char
	Atom			<-	AtomChar+
	AstringChar		<-	AtomChar / RespSpecial
	Astring			<-	AstringChar+ / String
	Nil				<-	"NIL"
	Nstring			<-	Nil / String
	AddrName		<-	Nstring
	AddrAdl			<-	Nstring
	AddrMailbox		<-	Nstring
	AddrHost		<-	Nstring
	Address			<-	LParens AddrName space AddrAdl space AddrMailbox space AddrHost RParens
	Envelope		<-	"(" EnvDate space EnvSubject space EnvFrom space EnvSender space EnvReplyTo space EnvTo space EnvCC space EnvBCC space EnvInReplyTo space EnvMessageId ")"
	EnvBCC			<-	("(" Address+ ")") / Nil
	EnvCC			<-	( "(" Address+ ")" ) / Nil
	EnvDate			<-	Nstring
	EnvFrom			<-	( "(" Address+ ")" ) / Nil
	EnvInReplyTo	<-	Nstring
	EnvMessageId	<-	Nstring
	EnvReplyTo		<-	( "(" Address+ ")" ) / Nil
	EnvSender		<-	(LParens Address+ RParens ) / Nil
	EnvSubject		<- Nstring
	EnvTo			<-	(LParens Address+ RParens) / Nil
	Inbox			<-	"INBOX" / "inbox" # FIXME - should be completely case insensitive
	Mailbox			<-	Inbox / Astring
	FlagExtension	<-	backslash Atom
	FlagKeyword		<-	Atom
	Flag			<-	"\\Answered" / "\\Flagged" / "\\Deleted" / "\\Seen" / "\\Draft" / FlagKeyword / FlagExtension
	FlagList		<-	LParens Flag (space Flag)* RParens
	DateDay			<-	Digit Digit / Digit
	DateDayFixed	<-	Digit Digit / (space Digit)
	DateMonth		<-	"Jan" / "Feb" / "Mar" / "Apr" / "May" / "Jun" / "Jul" / "Aug" / "Sep" / "Oct" / "Nov" / "Dec"
	DateYear		<-	Digit Digit Digit Digit
	DateText		<-	DateDay dash DateMonth dash DateYear
	Time			<-	Digit Digit colon Digit Digit colon Digit Digit
	Zone			<-	( "+" / "-" ) Digit Digit Digit Digit
	Date			<-	DateText / (doublequote DateText doublequote)
	DateTime		<-	doublequote DateDayFixed dash DateMonth dash DateYear space Time space Zone doublequote

	HeaderFldName	<-	Astring
	HeaderList		<-	"(" HeaderFldName (space HeaderFldName)* ")"
	ListMailbox		<-	AtomChar / ListWildCard / RespSpecial
	MailboxData		<-	"FLAGS" space FlagList / "LIST" space MailboxList / "LSUB" space MailboxList / "SEARCH" (space NzNumber)*  "STATUS" space Mailbox space "(" (StatusAttList)? ")" / Number space "EXISTS" / Number space "RECENT"
	MailboxList		<-	LParens (MbxListFlags)? RParens (space doublequote QuotedChar doublequote) / Nil space Mailbox
	MbxListFlags	<-	((MbxListOFlag space)* MbxListSFlag (MbxListOFlag)*) / (MbxListOFlag (space MbxListOFlag)*)
	MbxListOFlag	<-	backslash "Noinferiors" / FlagExtension
	MbxListSFlag	<-	backslash "Noselect" / backslash "Marked" / backslash "Unmarked"
	MessageData		<-	NzNumber space ("EXPUNGE" / ("FETCH" space MsgAtt))
	MsgAtt			<-	LParens (MsgAttDynamic / MsgAttStatic) (space MsgAttDynamic / MsgAttStatic)* RParens
	MsgAttDynamic	<-	"FLAGS" space (FlagFetch (space FlagFetch)*)? RParens
	MsgAttStatic	<-	"ENVELOPE" space Envelope /
						"INTERNALDATE" space DateTime /
						"RFC822" (".HEADER" / ".TEXT")? space Nstring /
						"RFC822.SIZE" space Number /
						"BODY" ("STRUCTURE")? space Body /
						"BODY" Section ("<" Number ">")? space Nstring /
						"UID" space UniqueId
	StatusAttList	<-	StatusAtt space Number (space StatusAtt space Number)*
	UserID			<-	Astring
	Password		<-	Astring
	Tag				<-	( !"+" AstringChar)+
	UniqueId		<-	NzNumber
	SearchKey		<-	"ALL" "ANSWERED" "BCC" space Astring / "BEFORE" space Date / "BODY" space Astring / "CC" space Astring / "DELETED" / "FLAGGED" / "FROM" space Astring / "KEYWORD" space FlagKeyword / "NEW" / "OLD" / "ON" space Date / "RECENT" / "SEEN" / "SINCE" space Date / "SUBJECT" space Astring / "TEXT" space  Astring / "TO" space Astring / "UNANSWERED" / "UNDELETED" / "UNFLAGGED" / "UNKEYWORD" space FlagKeyword / "UNSEEN" / "DRAFT" / "HEADER" space HeaderFldName space Astring / "LARGER" space Number / "NOT" space SearchKey / "OR" space SearchKey / "SENTON" space Date / "SENTSINCE" space Date / "SMALLER" space Number / "UID" space SequenceSet / "UNDRAFT" / SequenceSet/ "(" SearchKey (space SearchKey)* ")"
	Section			<- "[" SectionSpec? "]"
	SectionMsgText	<-	"HEADER" / "HEADER.FIELDS" ".NOT"? space HeaderList / "TEXT"
	SectionPart		<-	NzNumber ("." NzNumber)*
	SectionSpec		<-	SectionMsgText / SectionPart / ("." SectionText)?
	SectionText		<-	SectionMsgText / "MIME"
	SeqNumber		<-	NzNumber / star
	SeqRange		<-	SeqNumber colon SeqNumber
	SequenceSet		<-	(SeqNumber / SeqRange) (comma SequenceSet)*
	FetchAtt		<-	"ENVELOPE" / "FLAGS" / "INTERNALDATE" / "RFC822" / (".HEADER" / ".SIZE" / ".TEXT")? / "BODY" ("STRUCTURE")? / "UID" / "BODY" Section ("<" Number "." NzNumber ">" )?
	StoreAttFlags	<-	("+" / "-") "FLAGS" (".SILENT")? space (FlagList / (Flag (space Flag)*))
	Uid				<-	"UID" space (Copy/Fetch/Search/Store)

# Commands
	AuthType		<-	Atom
	Authenticate	<-	"AUTHENTICATE" space AuthType (CRLF Base64)*
	Capability		<-	("AUTH=" AuthType) / Atom
	CapabilityData	<-	"CAPABILITY" (space Capability)* space "IMAP4rev1" (space Capability)*
	Append			<-	"APPEND" space Mailbox (space FlagList)? (space DateTime) (space Literal)
	Copy			<-	"COPY" space SequenceSet space Mailbox
	Create			<-	"CREATE" space Mailbox
	Delete			<-	"DELETE" space Mailbox
	Examine			<-	"EXAMINE" space Mailbox
	FlagFetch		<-	Flag / "\\Recent"
	FlagPerm		<-	Flag / (backslash star)
	Fetch			<-	"FETCH" space SequenceSet space ("ALL" / "FULL" / "FAST" / FetchAtt / "(" FetchAtt (space FetchAtt)* ")" )
	List			<-	"LIST" space Mailbox space ListMailbox
	Login			<-	"LOGIN" space UserID Password
	Lsub			<-	"LSUB" space Mailbox space ListMailbox
	Rename			<-	"RENAME" space Mailbox space Mailbox
	Search			<-	"SEARCH" (space "CHARSET" space Astring)? (space SearchKey)+
	Select			<-	"SELECT" space Mailbox
	StatusAtt		<-	"MESSAGES" / "RECENT" / "UIDNEXT" / "UIDVALIDITY" / "UNSEEN"
	Status			<-	"STATUS" space Mailbox space LParens StatusAtt (space StatusAtt)* RParens
	Subscribe		<-	"SUBSCRIBE" space Mailbox
	Unsubscribe		<-	"UNSUBSCRIBE" space Mailbox
	XCommand		<-	"X" Atom Text #FIXME

	Command			<-	Tag space (CommandAny / CommandAuth / CommandNonAuth / CommandSelect) CRLF
	CommandAuth		<-	Append / Create / Delete / Examine / List / Lsub / Rename/ Select / Status / Subscribe / Unsubscribe
	CommandNonAuth	<-	Login / Authenticate / "STARTTLS"
	CommandAny		<-	"CAPABILITY" / "LOGOUT" / "NOOP" / XCommand
	CommandSelect	<-	"CHECK" / "CLOSE" / "EXPUNGE" / Copy / Fetch / Store / Uid / Search

# Response
	ContinueReq		<-	plus space (RespText / Base64) CRLF
	ResponseData	<-	star space (RespCondState / RespCondBye / MailboxData / MessageData / CapabilityData) CRLF
	ResponseTagged	<-	star space RespCondState CRLF
	ResponseFatal	<-	star RespCondBye CRLF
	RespCondAuth	<-	("OK" / "PREAUTH") space RespText
	RespCondBye		<-	"BYE" space RespText
	RespCondState	<-	( "OK" / "NO" / "BAD" ) / RespText
	RespText		<-	( "[" RespTextCode "]" space )? Text
	RespTextCode	<-	"ALERT" /
						"BADCHARSET" (space LParens Astring (space Astring)* RParens )? /
						CapabilityData /
					    "PARSE" /
						"PERMANENTFLAGS" space LParens (FlagPerm (space FlagPerm))* RParens /
						"READ-ONLY" /
						"READ-WRITE" /
						"TRYCREATE" /
						"UIDNEXT" space NzNumber /
						"UIDVALIDITY" space NzNumber /
						"UNSEEN" space NzNumber /
						Atom (space ( !"]" TextChar+)?)
	ResponseDone	<-	ResponseTagged / ResponseFatal

	Response		<-	(ContinueReq / ResponseData)* ResponseDone
	Store			<-	"STORE" space SequenceSet space StoreAttFlags

	BodyFields		<-	BodyFieldParam space BodyFieldID space BodyFieldDesc space BodyFieldEnc space BodyFieldOctets
	BodyFieldDesc	<-	Nstring
	BodyFieldDsp	<-	( "(" String space BodyFieldParam ")" ) / Nil
	BodyFieldEnc	<-	(doublequote ("7BIT"/"8BIT"/"BINARY"/"BASE64"/"QUOTED-PRINTABLE") doublequote) / String
	BodyFieldID		<-	Nstring
	BodyFieldLang	<-	Nstring / "(" String (space String)* ")"
	BodyFieldLoc	<-	Nstring
	BodyFieldLines	<-	Number
	BodyFieldMD5	<-	Nstring
	BodyFieldOctets	<-	Number
	BodyFieldParam	<-	("(" String space String (space String space String)* ")") / Nil
	BodyExtension	<-	Nstring / Number / ("(" BodyExtension (space BodyExtension)* ")" )
	BodyExtSinglePart <- BodyFieldMD5 (space BodyFieldDsp (space BodyFieldLang (space BodyFieldLoc (space BodyExtension)* )? )? )?
	BodyExtMultiPart <- BodyFieldParam (space BodyFieldDsp (space BodyFieldLang (space BodyFieldLoc (space BodyExtension)* )? )? )?
	BodyTypeSinglePart <- (BodyTypeBasic / BodyTypeMsg / BodyTypeText) (space BodyExtSinglePart)?
	BodyTypeBasic	<-	MediaBasic space BodyFields
	BodyTypeMultiPart <- Body+ space MediaSubType (space BodyExtMultiPart)?
	BodyTypeMsg		<-	MediaMessage space BodyFields space Envelope space Body space BodyFieldLines
	BodyTypeText	<-	MediaText space BodyFields space BodyFieldLines
	Body			<-	LParens (BodyTypeSinglePart / BodyTypeMultiPart) RParens

	MediaBasic		<-	(( doublequote ("APPLICATION" / "AUDIO" / "IMAGE" / "MESSAGE" / "VIDEO") doublequote) / String) space MediaSubType
	MediaMessage	<-	doublequote "MESSAGE" doublequote space doublequote "RFC822" doublequote
	MediaSubType	<- String
	MediaText		<-	doublequote "TEXT" doublequote space MediaSubType
	Greeting		<-	star space (RespCondAuth / RespCondBye) CRLF
`));
