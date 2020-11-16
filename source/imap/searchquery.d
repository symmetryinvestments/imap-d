///
module imap.searchquery;

import sumtype;
import std.format : format;

import imap.defines;
import imap.socket;
import imap.session : Session;
import imap.sildoc : SILdoc;

// -------------------------------------------------------------------------------------------------

struct SearchQuery {
    // XXX would really like to be able to substitute 'SearchTerm' for each of these methods with a
    // XXX T which is a valid arg for the SearchTerm ctor, so that we don't have to pass
    // XXX SearchTerm(term) to them explicitly (which we never want).

    this(SearchTerm term) {
        query = new SearchOp(term);
    }

    ref SearchQuery and(SearchTerm term) {
        return applyBinOp!AndOp(new SearchOp(term));
    }

    ref SearchQuery or(SearchTerm term) {
        // Strictly speaking the implicit 'ALL' term should be ORed with a unit arg, but that
        // wouldn't really be helpful and is very likely not what the user wants.
        return applyBinOp!OrOp(new SearchOp(term));
    }

    ref SearchQuery not(SearchTerm term) {
        assert(query is null, "Cannot apply .not() to existing queries!  Use andNot() or orNot().");
        query = new SearchOp(NotOp(new SearchOp(term)));
        return this;
    }

    ref SearchQuery andNot(SearchTerm term) {
        return applyBinOp!AndOp(new SearchOp(NotOp(new SearchOp(term))));
    }

    ref SearchQuery orNot(SearchTerm term) {
        return applyBinOp!OrOp(new SearchOp(NotOp(new SearchOp(term))));
    }

    string toString() {
        return searchOpToString(query);
    }

    ref SearchQuery applyBinOp(O)(SearchOp* newTerm) {
        if (query is null)
            query = newTerm;
        else
            query = new SearchOp(O(query, newTerm));
        return this;
    }

    SearchOp* query;
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

alias SearchOp = SumType!(SearchTerm, NotOp, AndOp, OrOp);

struct NotOp {
    SearchOp* term;
}

struct AndOp {
    SearchOp* lhs;
    SearchOp* rhs;
}

struct OrOp {
    SearchOp* lhs;
    SearchOp* rhs;
}

bool isBinaryOp(SearchOp* op) {
    return (*op).match!(
        (AndOp _a) => true,
        (OrOp _o)  => true,
        (_)        => false,
    );
}

string searchOpToString(SearchOp* op) {
    import std.algorithm : map;
    import std.array : join;

    if (op is null) {
        return "ALL";
    }
    return (*op).match!(
        (SearchTerm term) => term.match!(
            (FlagTerm term)    => cast(string)term.flag,
            (KeywordTerm term) => format!"KEYWORD %s"(term.keyword),
            (FieldTerm term)   => format!`%s "%s"`(cast(string)term.field, term.term),
            (DateTerm term)    => format!"%s %s"(cast(string)term.when, term.date),
            (SizeTerm term)    => format!"%s %d"(cast(string)term.relation, term.size),
            (UidSeqTerm term)  => format!"UID %s"(term.sequences.map!(s => s.toString()).join(",")),
        ),
        (NotOp op) => notOpToString(op),
        (AndOp op) => format!"%s %s"(searchOpToString(op.lhs), searchOpToString(op.rhs)),
        (OrOp op)  => orOpToString(op),
    );
}

string notOpToString(NotOp op) {
    string termStr = searchOpToString(op.term);
    if (isBinaryOp(op.term)) {
        return format!"NOT (%s)"(termStr);
    }
    return format!"NOT %s"(termStr);
}

string orOpToString(OrOp op) {
    string lhsStr = searchOpToString(op.lhs);
    if (isBinaryOp(op.lhs)) {
        lhsStr = format!"(%s)"(lhsStr);
    }
    string rhsStr = searchOpToString(op.rhs);
    if (isBinaryOp(op.rhs)) {
        rhsStr = format!"(%s)"(rhsStr);
    }
    return format!"OR %s %s"(lhsStr, rhsStr);
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

alias SearchTerm = SumType!(FlagTerm, KeywordTerm, FieldTerm, DateTerm, SizeTerm, UidSeqTerm);

struct FlagTerm {
    enum Flag : string {
        Answered = "ANSWERED",
        Deleted  = "DELETED",
        Draft    = "DRAFT",
        Flagged  = "FLAGGED",
        New      = "NEW",
        Old      = "OLD",
        Recent   = "RECENT",
        Seen     = "SEEN",
    }
    Flag flag;
}

struct KeywordTerm {
    string keyword;
}

struct FieldTerm {
    enum Field : string {
        Bcc     = "BCC",
        Body    = "BODY",
        Cc      = "CC",
        From    = "FROM",
        Header  = "HEADER",
        Subject = "SUBJECT",
        Text    = "TEXT",
        To      = "TO",
    }
    Field field;
    string term;
}

struct DateTerm {
    enum When : string {
        Before     = "BEFORE",
        On         = "ON",
        SentBefore = "SENTBEFORE",
        SentOn     = "SENTON",
        SentSince  = "SENTSINCE",
        Since      = "SINCE",
    }
    When when;
    SearchDate date;
}

struct SizeTerm {
    enum Relation : string {
        Larger  = "LARGER",
        Smaller = "SMALLER",
    }
    Relation relation;
    int size;
}

struct UidSeqTerm {
    struct Range {
        // This is a little unintuitive; if length is 0 then there's a single value: start, else
        // it's a range *including* start+length.  I.e., if length is 1, then it's a range of start
        // and start+1 (2 values).
        int start, length = 0;

        invariant (start >= 1 && length >= 0);

        string toString() {
            if (length == 0)
                return format!"%d"(start);
            return format!"%d:%d"(start, start + length);
        }
    }
    Range[] sequences;
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

unittest {
    assert(SearchQuery().toString == "ALL");

    void termTest(T)(T term, string expected) {
        import std.stdio : writeln;

        auto got = SearchQuery(SearchTerm(term)).toString();
        if (got != expected) {
            writeln("FAILED MATCH:");
            writeln("expecting: ", expected);
            writeln("got:       ", got);
        }
        assert(SearchQuery(SearchTerm(term)).toString() == expected);
    }

    termTest(FlagTerm(FlagTerm.Flag.New), "NEW");
    termTest(KeywordTerm("foobar"), "KEYWORD foobar");
    termTest(FieldTerm(FieldTerm.Field.Cc, "alice"), `CC "alice"`);
    termTest(DateTerm(DateTerm.When.Since, SearchDate(1, 7, 2007)), "SINCE 1-Jul-2007");
    termTest(SizeTerm(SizeTerm.Relation.Larger, 12345), "LARGER 12345");
    termTest(UidSeqTerm([UidSeqTerm.Range(1, 3), UidSeqTerm.Range(7), UidSeqTerm.Range(33, 100)]), "UID 1:4,7,33:133");
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

unittest {
    import std.exception;
    import core.exception;

    void queryTest(Q)(Q query, string expected) {
        import std.stdio : writeln;

        auto got = query.toString();
        if (got != expected) {
            writeln("FAILED MATCH:");
            writeln("expecting: ", expected);
            writeln("got:       ", got);
        }
        assert(query.toString() == expected);
    }

    // AND.
    auto sq00 =
        SearchQuery(SearchTerm(FlagTerm(FlagTerm.Flag.Flagged)))
        .and(SearchTerm(FieldTerm(FieldTerm.Field.Subject, "welcome")));
    queryTest(sq00, `FLAGGED SUBJECT "welcome"`);
    auto sq01 =
        SearchQuery()
        .and(SearchTerm(FlagTerm(FlagTerm.Flag.Flagged)))
        .and(SearchTerm(FieldTerm(FieldTerm.Field.Subject, "welcome")));
    queryTest(sq01, `FLAGGED SUBJECT "welcome"`);

    // OR.
    auto sq10 =
        SearchQuery(SearchTerm(DateTerm(DateTerm.When.On, SearchDate(12, 12, 2012))))
        .or(SearchTerm(SizeTerm(SizeTerm.Relation.Smaller, 1212)));
    queryTest(sq10, "OR ON 12-Dec-2012 SMALLER 1212");
    auto sq11 =
        SearchQuery()
        .or(SearchTerm(DateTerm(DateTerm.When.On, SearchDate(12, 12, 2012))))
        .or(SearchTerm(SizeTerm(SizeTerm.Relation.Smaller, 1212)));
    queryTest(sq11, "OR ON 12-Dec-2012 SMALLER 1212");
    auto sq12 =
        SearchQuery()
        .or(SearchTerm(DateTerm(DateTerm.When.On, SearchDate(12, 12, 2012))))
        .or(SearchTerm(SizeTerm(SizeTerm.Relation.Smaller, 1212)))
        .or(SearchTerm(UidSeqTerm([UidSeqTerm.Range(40, 10)])));
    queryTest(sq12, "OR (OR ON 12-Dec-2012 SMALLER 1212) UID 40:50");

    // NOT/AND-NOT/OR-NOT.
    auto sq20 =
        SearchQuery()
        .not(SearchTerm(FieldTerm(FieldTerm.Field.To, "bob")));
    queryTest(sq20, `NOT TO "bob"`);
    auto sq21 =
        SearchQuery()
        .and(SearchTerm(FieldTerm(FieldTerm.Field.To, "bob")))
        .andNot(SearchTerm(FieldTerm(FieldTerm.Field.From, "carlos")));
    queryTest(sq21, `TO "bob" NOT FROM "carlos"`);
    auto sq22 =
        SearchQuery()
        .and(SearchTerm(FieldTerm(FieldTerm.Field.To, "bob")))
        .orNot(SearchTerm(FieldTerm(FieldTerm.Field.From, "carlos")));
    queryTest(sq22, `OR TO "bob" NOT FROM "carlos"`);
    auto sq23 =
        SearchQuery()
        .or(SearchTerm(FieldTerm(FieldTerm.Field.To, "bob")))
        .orNot(SearchTerm(FieldTerm(FieldTerm.Field.From, "carlos")));
    queryTest(sq23, `OR TO "bob" NOT FROM "carlos"`);
    auto sq24 =
        SearchQuery()
        .not(SearchTerm(FieldTerm(FieldTerm.Field.To, "bob")))
        .orNot(SearchTerm(FieldTerm(FieldTerm.Field.From, "carlos")));
    queryTest(sq24, `OR NOT TO "bob" NOT FROM "carlos"`);
    assertThrown!AssertError(SearchQuery()
                 .and(SearchTerm(FieldTerm(FieldTerm.Field.To, "bob")))
                 .not(SearchTerm(FieldTerm(FieldTerm.Field.From, "carlos"))));
}

// -------------------------------------------------------------------------------------------------

struct SearchDate {
    int day, month, year;

    invariant (1 <= day && day <= 31);
    invariant (1 <= month && month <= 12);
    invariant (year >= 0);

    string toString() {
        return format!"%d-%s-%d"(day,
                                 ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1],
                                 year);
    }
}

unittest {
    assert(SearchDate(18, 7, 1999).toString() == "18-Jul-1999");
    assert(SearchDate(1, 1, 1).toString() == "1-Jan-1");
    assert(SearchDate(31, 2, 2222).toString() == "31-Feb-2222");

    import std.exception;
    import core.exception;

    assertThrown!AssertError(SearchDate(0, 1, 1999).toString());
    assertThrown!AssertError(SearchDate(-5, 1, 1999).toString());
    assertThrown!AssertError(SearchDate(32, 1, 1999).toString());
    assertThrown!AssertError(SearchDate(1, 0, 1999).toString());
    assertThrown!AssertError(SearchDate(1, 13, 1999).toString());
    assertThrown!AssertError(SearchDate(1, -2, 1999).toString());
}

// -------------------------------------------------------------------------------------------------

@SILdoc(`Generate query string to serch the selected mailbox according to the supplied criteria.
This string may be passed to imap.search.

The searchQueries are ORed together.  There is an implicit AND within a searchQuery
For NOT, set not within the query to be true - this applies to all the conditions within
the query.
`)
string createQuery(SearchQuery[] searchQueries) {
    import std.range : chain, repeat;
    import std.algorithm : map;
    import std.string : join, strip;
    import std.conv : to;

    if (searchQueries.length == 0)
        return "ALL";

    return chain("OR".repeat(searchQueries.length - 1),
            searchQueries.map!(q => q.to!string.strip)).join(" ").strip;
}

@SILdoc(`Search selected mailbox according to the supplied search criteria.
There is an implicit AND within a searchQuery. For NOT, set not within the query
to be true - this applies to all the conditions within the query.
`)
auto searchQuery(Session session, string mailbox, SearchQuery searchQuery, string charset = null) {
    import imap.namespace : Mailbox;
    import imap.request;
    select(session, Mailbox(mailbox));
    return search(session, createQuery([searchQuery]), charset);
}

@SILdoc(`Search selected mailbox according to the supplied search criteria.
The searchQueries are ORed together.  There is an implicit AND within a searchQuery
For NOT, set not within the query to be true - this applies to all the conditions within
the query.
`)
auto searchQueries(Session session, string mailbox, SearchQuery[] searchQueries, string charset = null) {
    import imap.namespace : Mailbox;
    import imap.request;
    select(session, Mailbox(mailbox));
    return search(session, createQuery(searchQueries), charset);
}

struct UidRange {
    long start = -1;
    long end = -1;

    string toString() {
        import std.string : format;
        import std.conv : to;

        return format!"%s:%s"(
            (start == -1) ? 0 : start,
            (end == -1) ? "*" : end.to!string
        );
    }
}
