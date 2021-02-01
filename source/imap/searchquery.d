///
module imap.searchquery;

import mir.algebraic : Variant, This, match;
import std.format : format;
import std.datetime : Date;

import imap.defines;
import imap.socket;
import imap.session : Session;
import imap.sildoc : SILdoc;

// -------------------------------------------------------------------------------------------------

final class SearchQuery {
    this(const SearchExpr * expr = null) {
        query = expr;
    }

    this(T)(T value) {
        this(new SearchExpr(value));
    }


    SearchQuery not(T)(T value) {
        return not(new SearchExpr(value));
    }

    SearchQuery not(const(SearchExpr) * term) {
        assert(query is null, "Cannot apply .not() to existing queries!  Use andNot() or orNot().");
        query = new SearchExpr(SearchOp('!', term, null));
        return this;
    }

    alias and = applyBinOpImpl!('&');
    alias or = applyBinOpImpl!('|');

    alias andNot = applyBinOpImpl!('&', true);
    alias orNot = applyBinOpImpl!('|', true);

    private template applyBinOpImpl(char op, bool not = false) {
        SearchQuery applyBinOpImpl(T)(T value) {
            return applyBinOpImpl(new SearchExpr(value));
        }
        SearchQuery applyBinOpImpl(const(SearchExpr) * term) {
            static if (not) {
                return applyBinOp(op, new SearchExpr(SearchOp('!', term, null)));
            } else {
                return applyBinOp(op, term);
            }
        }
        SearchQuery applyBinOpImpl(const SearchQuery other) {
            return applyBinOpImpl(other.query);
        }
    }

    override string toString() const {
        return searchExprToString(query);
    }

    SearchQuery applyBinOp(char op, const(SearchExpr) * newTerm) {
        if (query is null) {
            query = newTerm;
        } else {
            query = new SearchExpr(SearchOp(op, query, newTerm));
        }
        return this;
    }

    const(SearchExpr) *query;
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

string searchExprToString(const SearchExpr* expr) {
    import std.algorithm : map;
    import std.array : join;

    if (expr is null) {
        return "ALL";
    }
    return (*expr).match!(
        (FlagTerm term)    => cast(string)term.flag,
        (KeywordTerm term) => format!"%sKEYWORD %s"(term.negated ? "UN" : "", term.keyword),
        (FieldTerm term)   => format!`%s "%s"`(cast(string)term.field, term.term),
        (HeaderTerm term)  => format!`HEADER %s "%s"`(term.header, term.term),
        (DateTerm term)    => format!"%s %s"(cast(string)term.when, rfcDateStr(term.date)),
        (SizeTerm term)    => format!"%s %d"(cast(string)term.relation, term.size),
        (UidSeqTerm term)  => format!"UID %s"(term.sequences.map!(s => s.toString()).join(",")),
        (SearchOp expr)    => searchOpToString(expr),
    );
}

string searchOpToString(SearchOp op) {
    switch (op.op) {
        case '!': return notOpToString(op.lhs);
        case '&': return format!"%s %s"(searchExprToString(op.lhs), searchExprToString(op.rhs));
        case '|': return orOpToString(op.lhs, op.rhs);
        default:  assert(false, "Unknown search operation.");
    }
}

string notOpToString(const SearchExpr* expr) {
    string exprStr = searchExprToString(expr);
    if (isBinaryOp(expr)) {
        return format!"NOT (%s)"(exprStr);
    }
    return format!"NOT %s"(exprStr);
}

string orOpToString(const(SearchExpr) * lhs, const(SearchExpr) * rhs) {
    string lhsStr = searchExprToString(lhs);
    if (isBinaryOp(lhs)) {
        lhsStr = format!"(%s)"(lhsStr);
    }
    string rhsStr = searchExprToString(rhs);
    if (isBinaryOp(rhs)) {
        rhsStr = format!"(%s)"(rhsStr);
    }
    return format!"OR %s %s"(lhsStr, rhsStr);
}

bool isBinaryOp(const SearchExpr* expr) {
    return (*expr).match!(
        (SearchOp op) => op.op == '&' || op.op == '|',
        (_)           => false,
    );
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

import std.typecons : Tuple;

alias SearchExpr = Variant!(
    FlagTerm,
    KeywordTerm,
    FieldTerm,
    HeaderTerm,
    DateTerm,
    SizeTerm,
    UidSeqTerm,

    // '!' == NOT, '&' == AND, '|' == OR.
    Tuple!(char, "op", const(This) *, "lhs", const(This) *, "rhs"),
);

alias SearchOp = Tuple!(char, "op", const(SearchExpr) *, "lhs", const(SearchExpr) *, "rhs");

struct FlagTerm {
    enum Flag : string {
        Answered   = "ANSWERED",
        Deleted    = "DELETED",
        Draft      = "DRAFT",
        Flagged    = "FLAGGED",
        New        = "NEW",
        Old        = "OLD",
        Recent     = "RECENT",
        Seen       = "SEEN",
        Unanswered = "UNANSWERED",
        Undeleted  = "UNDELETED",
        Undraft    = "UNDRAFT",
        Unflagged  = "UNFLAGGED",
        Unseen     = "UNSEEN",
    }
    Flag flag;
}

struct KeywordTerm {
    string keyword;
    bool negated = false;
}

struct FieldTerm {
    enum Field : string {
        Bcc     = "BCC",
        Body    = "BODY",
        Cc      = "CC",
        From    = "FROM",
        Subject = "SUBJECT",
        Text    = "TEXT",
        To      = "TO",
    }
    Field field;
    string term;
}

struct HeaderTerm {
    string header;
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
    Date date;
}

string rfcDateStr(Date date) {
    return format!"%d-%s-%d"(date.day,
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][date.month - 1],
        date.year);
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

        invariant(start >= 1 && length >= 0);

        string toString() const {
            if (length == 0)
                return format!"%d"(start);
            return format!"%d:%d"(start, start + length);
        }
    }
    const(Range)[] sequences;
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

unittest {
    assert(new SearchQuery().toString == "ALL");

    void termTest(T)(T term, string expected) {
        import std.stdio : writeln;

        auto got = new SearchQuery(term).toString();
        if (got != expected) {
            writeln("FAILED MATCH:");
            writeln("expecting: ", expected);
            writeln("got:       ", got);
        }
        assert(new SearchQuery(new SearchExpr(term)).toString() == expected);
    }

    termTest(FlagTerm(FlagTerm.Flag.New), "NEW");
    termTest(KeywordTerm("foobar"), "KEYWORD foobar");
    termTest(FieldTerm(FieldTerm.Field.Cc, "alice"), `CC "alice"`);
    termTest(HeaderTerm("X-SPAM", "high"), `HEADER X-SPAM "high"`);
    termTest(DateTerm(DateTerm.When.Since, Date(2007, 7, 1)), "SINCE 1-Jul-2007");
    termTest(SizeTerm(SizeTerm.Relation.Larger, 12345), "LARGER 12345");
    termTest(UidSeqTerm([UidSeqTerm.Range(1, 3), UidSeqTerm.Range(7), UidSeqTerm.Range(33, 100)]), "UID 1:4,7,33:133");
}

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

unittest {
    import std.conv : to;
    import std.exception;
    import core.exception;

    void queryTest(Q)(Q query, string expected) {
        import std.stdio : writeln;

        auto got = query.to!string;
        if (got != expected) {
            writeln("FAILED MATCH:");
            writeln("expecting: ", expected);
            writeln("got:       ", got);
        }
        assert(query.to!string == expected);
    }

    // AND.
    auto sq00 =
        new SearchQuery(FlagTerm(FlagTerm.Flag.Flagged))
        .and(FieldTerm(FieldTerm.Field.Subject, "welcome"));
    queryTest(sq00, `FLAGGED SUBJECT "welcome"`);
    auto sq01 =
        new SearchQuery()
        .and(FlagTerm(FlagTerm.Flag.Unflagged))
        .and(FieldTerm(FieldTerm.Field.Subject, "welcome"));
    queryTest(sq01, `UNFLAGGED SUBJECT "welcome"`);
    auto sq02 =
        new SearchQuery()
        .and(FlagTerm(FlagTerm.Flag.Unflagged))
        .and(FieldTerm(FieldTerm.Field.Subject, "welcome"))
        .and(KeywordTerm("quux", true));
    queryTest(sq02, `UNFLAGGED SUBJECT "welcome" UNKEYWORD quux`);

    // OR.
    auto sq10 =
        new SearchQuery(DateTerm(DateTerm.When.On, Date(2012, 12, 12)))
        .or(SizeTerm(SizeTerm.Relation.Smaller, 1212));
    queryTest(sq10, "OR ON 12-Dec-2012 SMALLER 1212");
    auto sq11 =
        new SearchQuery()
        .or(DateTerm(DateTerm.When.On, Date(2012, 12, 12)))
        .or(SizeTerm(SizeTerm.Relation.Smaller, 1212));
    queryTest(sq11, "OR ON 12-Dec-2012 SMALLER 1212");
    auto sq12 =
        new SearchQuery()
        .or(DateTerm(DateTerm.When.On, Date(2012, 12, 12)))
        .or(SizeTerm(SizeTerm.Relation.Smaller, 1212))
        .or(UidSeqTerm([UidSeqTerm.Range(40, 10)]));
    queryTest(sq12, "OR (OR ON 12-Dec-2012 SMALLER 1212) UID 40:50");

    // NOT/AND-NOT/OR-NOT.
    auto sq20 =
        new SearchQuery()
        .not(FieldTerm(FieldTerm.Field.To, "bob"));
    queryTest(sq20, `NOT TO "bob"`);
    auto sq21 =
        new SearchQuery()
        .and(FieldTerm(FieldTerm.Field.To, "bob"))
        .andNot(FieldTerm(FieldTerm.Field.From, "carlos"));
    queryTest(sq21, `TO "bob" NOT FROM "carlos"`);
    auto sq22 =
        new SearchQuery()
        .and(FieldTerm(FieldTerm.Field.To, "bob"))
        .orNot(FieldTerm(FieldTerm.Field.From, "carlos"));
    queryTest(sq22, `OR TO "bob" NOT FROM "carlos"`);
    auto sq23 =
        new SearchQuery()
        .or(FieldTerm(FieldTerm.Field.To, "bob"))
        .orNot(FieldTerm(FieldTerm.Field.From, "carlos"));
    queryTest(sq23, `OR TO "bob" NOT FROM "carlos"`);
    auto sq24 =
        new SearchQuery()
        .not(FieldTerm(FieldTerm.Field.To, "bob"))
        .orNot(FieldTerm(FieldTerm.Field.From, "carlos"));
    queryTest(sq24, `OR NOT TO "bob" NOT FROM "carlos"`);
    assertThrown!AssertError(new SearchQuery()
            .and(FieldTerm(FieldTerm.Field.To, "bob"))
            .not(FieldTerm(FieldTerm.Field.From, "carlos")));
    version (none) {
        // This would be nice, but special casing FlagTerm in this way would require too much guff.
        auto sq25 =
            new SearchQuery()
            .not(FlagTerm(FlagTerm.Flag.Answered))
            .andNot(FlagTerm(FlagTerm.Flag.Deleted))
            .andNot(FlagTerm(FlagTerm.Flag.Draft))
            .andNot(FlagTerm(FlagTerm.Flag.Flagged))
            .andNot(FlagTerm(FlagTerm.Flag.New))
            .andNot(FlagTerm(FlagTerm.Flag.Old))
            .andNot(FlagTerm(FlagTerm.Flag.Recent))
            .andNot(FlagTerm(FlagTerm.Flag.Seen))
            .andNot(KeywordTerm("xyzzy"));
        queryTest(sq25, `UNANSWERED UNDELETED UNDRAFT UNFLAGGED NOT NEW RECENT OLD UNSEEN UNKEYWORD xyzzy`);
    }

    // DEEP NESTING.
    // a && (b || c) && d
    auto sq30_BorC =
        new SearchQuery(FlagTerm(FlagTerm.Flag.Draft))
        .or(FlagTerm(FlagTerm.Flag.Flagged));
    auto sq30 =
        new SearchQuery()
        .and(FieldTerm(FieldTerm.Field.To, "alice"))
        .and(sq30_BorC)
        .and(FieldTerm(FieldTerm.Field.Subject, "wip"));
    queryTest(sq30, `TO "alice" OR DRAFT FLAGGED SUBJECT "wip"`);
    // a || (b && c) || d
    auto sq31_BandC =
        new SearchQuery(FlagTerm(FlagTerm.Flag.Draft))
        .and(FlagTerm(FlagTerm.Flag.Flagged));
    auto sq31 =
        new SearchQuery()
        .or(FieldTerm(FieldTerm.Field.To, "alice"))
        .or(sq31_BandC)
        .or(FieldTerm(FieldTerm.Field.Subject, "wip"));
    queryTest(sq31, `OR (OR TO "alice" (DRAFT FLAGGED)) SUBJECT "wip"`);
    // a || !(b || c) || d  (Using De Morgan we *could* rewrite to a || (b && c) || d).
    auto sq32_BorC =
        new SearchQuery(FlagTerm(FlagTerm.Flag.Draft))
        .or(FlagTerm(FlagTerm.Flag.Flagged));
    auto sq32 =
        new SearchQuery()
        .or(FieldTerm(FieldTerm.Field.To, "alice"))
        .orNot(sq32_BorC)
        .or(FieldTerm(FieldTerm.Field.Subject, "wip"));
    queryTest(sq32, `OR (OR TO "alice" NOT (OR DRAFT FLAGGED)) SUBJECT "wip"`);
    // a && !(b || c) && d
    auto sq33_BorC =
        new SearchQuery(FlagTerm(FlagTerm.Flag.Draft))
        .or(FlagTerm(FlagTerm.Flag.Flagged));
    auto sq33 =
        new SearchQuery()
        .and(FieldTerm(FieldTerm.Field.To, "alice"))
        .andNot(sq33_BorC)
        .and(FieldTerm(FieldTerm.Field.Subject, "wip"));
    queryTest(sq33, `TO "alice" NOT (OR DRAFT FLAGGED) SUBJECT "wip"`);
}

// -------------------------------------------------------------------------------------------------

