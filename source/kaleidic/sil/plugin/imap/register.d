///
module kaleidic.sil.plugin.imap.register;

import imap.set;
import std.meta : AliasSeq;

version (SIL) : import kaleidic.sil.lang.handlers : Handlers;

import kaleidic.sil.lang.typing.types : Variable, Function, SILdoc;

version (SIL_Plugin) {
    import kaleidic.sil.lang.plugin : pluginImpl;
    mixin pluginImpl!registerImap;
}

import std.socket;

import imap.defines;
import imap.socket;

import arsd.email : MimeContainer;

///
void registerImap(ref Handlers handlers) {
    import std.conv;
    import imap.session;
    import imap.request;
    import imap.response;
    import imap.namespace;
    import imap.searchquery;
    import arsd.email : IncomingEmailMessage, RelayInfo, ToType, EmailMessage, MimePart;

    // Register for imap.*.
    {
        handlers.openModule("imap");
        scope (exit) handlers.closeModule();

        static foreach (T; AliasSeq!(BodyResponse, EmailMessage, FlagResult, ImapLogin, ImapResult,
                                     ImapServer, ImapStatus, IncomingEmailMessage, ListEntry,
                                     ListResponse, Mailbox, MailboxList, MimeAttachment,
                                     MimeContainer_, MimePart, Options, ProtocolSSL, RelayInfo,
                                     Result!string, SearchResult, SearchResultType, Session, Status,
                                     StatusResult, StoreMode, ToType
                                    )) {
            handlers.registerType!T;
        }

        static foreach (F; AliasSeq!(append, attachments, close, closeConnection, copy, create,
                                     delete_, esearch, examine, expunge, fetchDate, fetchFast,
                                     fetchFields, fetchFlags, fetchHeader, fetchPart, fetchRFC822,
                                     fetchSize, fetchStructure, fetchText, idle, list, login,
                                     logout, lsub, move, moveUIDs, multiMove, multiSearch, noop,
                                     openConnection, rename, select, status, store, subscribe,
                                     unsubscribe, writeBinaryString,
                                     )) {
            handlers.registerHandler!F;
        }

        handlers.registerType!Socket;
        handlers.registerType!(Set!Capability)("Capabilities");
        handlers.registerType!(Set!ulong)("UidSet");

        handlers.registerHandler!(addSet!ulong)("addUidSet");
        handlers.registerHandler!(removeSet!ulong)("removeUidSet");

        handlers.registerType!SearchQuery("Query");
        handlers.registerHandlerOverloads!(
            ((Session session, SearchQuery query) => session.search(query.to!string)),
            ((Session session, string str) => session.search(str)),
        )("search");

        import jmap : registerHandlersJmap;
        handlers.registerHandlersJmap();
    }

    // Register for imap.query.*.
    {
        handlers.openModule("imap.query");
        scope (exit) handlers.closeModule();

        auto opDoc = SILdoc(`Compose search query terms with boolean operations. A query expression can be
created with 'and', 'or' and 'not', and also with 'andNot' and 'orNot'.

Query terms are specific filter criteria such as 'old()' or
'from("alice@example.com")'.

  E.g.,
  // Equivalent to (flagged OR subject contains "urgent") AND NOT from "gmail.com".
  query = imap.Query()
      |> and(flagged())
      |> or(subject("urgent"))
      |> andNot(from("gmail.com"))

This query can then be passed to 'imap.search()'.

When applying an or() operator the passed argument is OR'd with whatever is
already in the query.  Queries may be nested to enforce a precedence or to
essentially introduce parentheses.

  E.g.,
  // Equivalent to NOT flagged AND (seen OR recent) AND from "barry"
  query = imap.Query()
      |> not(flagged())
      |> and(imap.Query() |> or(seen()) |> or(recent()))
      |> and(from("barry"))

NOTE: These operators modify the Query in-place.  Be careful when re-using sub-queries:

  a = imap.Query(recent())    // 'a' matches 'recent'.
  b = a |> and(flagged())     // *Both* 'a' and 'b' now match ("recent" AND "flagged").

To use these operators and terms as shown above, use:

  import imap
  import * from imap.query`);

        // Boolean ops.
        handlers.registerHandlerOverloads!(
            (SearchQuery this_, const(SearchExpr)* expr) => this_.and(expr),
            (SearchQuery this_, const SearchQuery other) => this_.and(other),
        )("and", opDoc);
        handlers.registerHandlerOverloads!(
            (SearchQuery this_, const(SearchExpr)* expr) => this_.or(expr),
            (SearchQuery this_, const SearchQuery  other) => this_.or(other),
        )("or", opDoc);
        handlers.registerHandler!((SearchQuery this_, const(SearchExpr)* expr) => this_.not(expr))("not", opDoc);
        handlers.registerHandlerOverloads!(
            (SearchQuery this_, const(SearchExpr)* expr) => this_.andNot(expr),
            (SearchQuery this_, const SearchQuery other) => this_.andNot(other),
        )("andNot", opDoc);
        handlers.registerHandlerOverloads!(
            (SearchQuery this_, const(SearchExpr)* expr) => this_.orNot(expr),
            (SearchQuery this_, const SearchQuery other) => this_.orNot(other),
        )("orNot", opDoc);

        auto termDoc = SILdoc(`Search terms used to build a query to pass to imap.search().  Also see imap.query
functions, e.g., imap.query.and().

Flag terms, where the flag is set or unset:
    answered(), deleted(), draft(), flagged(), new(), old(), recent(), seen(),
    unanswered(), undeleted(), undraft(), unflagged, unseen(), keyword(str),
    unkeyword(str).

Field terms, where the field contains 'str':
    bcc(str), body(str), cc(str), from(str), subject(str), text(str), to(str).

Date terms, where date may be a dates.Date.
    before(date), on(date), sentBefore(date), sentOn(date), sendSince(date),
    since(date).

Size terms, where size is the entire message size in bytes.
    larger(size), smaller(size).`);

        // Flags.
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Answered)))("answered", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Deleted)))("deleted", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Draft)))("draft", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Flagged)))("flagged", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.New)))("new", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Old)))("old", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Recent)))("recent", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Seen)))("seen", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Unanswered)))("unanswered", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Undeleted)))("undeleted", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Undraft)))("undraft", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Unflagged)))("unflagged", termDoc);
        handlers.registerHandler!(() => new const SearchExpr(FlagTerm(FlagTerm.Flag.Unseen)))("unseen", termDoc);

        // Keyword.
        handlers.registerHandler!((string keyw) => new const SearchExpr(KeywordTerm(keyw)))("keyword", termDoc);
        handlers.registerHandler!((string keyw) => new const SearchExpr(KeywordTerm(keyw, true)))("unkeyword", termDoc);

        // Fields.
        handlers.registerHandler!((string str) => new const SearchExpr(FieldTerm(FieldTerm.Field.Bcc, str)))("bcc", termDoc);
        handlers.registerHandler!((string str) => new const SearchExpr(FieldTerm(FieldTerm.Field.Body, str)))("body", termDoc);
        handlers.registerHandler!((string str) => new const SearchExpr(FieldTerm(FieldTerm.Field.Cc, str)))("cc", termDoc);
        handlers.registerHandler!((string str) => new const SearchExpr(FieldTerm(FieldTerm.Field.From, str)))("from", termDoc);
        handlers.registerHandler!((string str) => new const SearchExpr(FieldTerm(FieldTerm.Field.Subject, str)))("subject", termDoc);
        handlers.registerHandler!((string str) => new const SearchExpr(FieldTerm(FieldTerm.Field.Text, str)))("text", termDoc);
        handlers.registerHandler!((string str) => new const SearchExpr(FieldTerm(FieldTerm.Field.To, str)))("to", termDoc);

        handlers.registerHandler!((string hdr, string str) => new const SearchExpr(HeaderTerm(hdr, str)))("header", termDoc);

        // Dates.
        import std.datetime : Date;
        handlers.registerHandler!((Date date) => new const SearchExpr(DateTerm(DateTerm.When.Before, date)))("before", termDoc);
        handlers.registerHandler!((Date date) => new const SearchExpr(DateTerm(DateTerm.When.On, date)))("on", termDoc);
        handlers.registerHandler!((Date date) => new const SearchExpr(DateTerm(DateTerm.When.SentBefore, date)))("sentBefore", termDoc);
        handlers.registerHandler!((Date date) => new const SearchExpr(DateTerm(DateTerm.When.SentOn, date)))("sentOn", termDoc);
        handlers.registerHandler!((Date date) => new const SearchExpr(DateTerm(DateTerm.When.SentSince, date)))("sentSince", termDoc);
        handlers.registerHandler!((Date date) => new const SearchExpr(DateTerm(DateTerm.When.Since, date)))("since", termDoc);

        // Sizes.
        handlers.registerHandler!((int size) => new const SearchExpr(SizeTerm(SizeTerm.Relation.Larger, size)))("larger", termDoc);
        handlers.registerHandler!((int size) => new const SearchExpr(SizeTerm(SizeTerm.Relation.Smaller, size)))("smaller", termDoc);

        // UID sequences.
        // XXX This is tricky.  We'd like some simple syntax to be able to declare them in SIL (I
        // assume?  Or do we?) but mostly we'd like to use whatever is returned from other APIs
        // (most likely prior searches).
    }
}

void writeBinaryString(string file, string data) {
    import std.file;
    write(file, data);
}

struct MimeContainer_ {
    MimeContainer h;
    string contentType() { return h._contentType; }
    string boundary() { return h.boundary; }
    string[] headers() { return h.headers; }
    string content() { return h.content; }

    MimeContainer_[] stuff() {
        import std.algorithm : map;
        import std.array : array;
        return h.stuff.map!(s => MimeContainer_(s)).array;
    }

    this(MimeContainer h) {
        this.h = h;
    }
}

MimeContainer_ accessMimeContainer(MimeContainer mimeContainer) {
    return MimeContainer_(mimeContainer);
}

