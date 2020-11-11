///
module imap.searchquery;

import imap.defines;
import imap.socket;
import imap.session : Session;
import imap.sildoc : SILdoc;

import core.time : Duration;
import std.datetime : Date;

struct SearchQuery {
    @SILdoc("not flag if applied inverts the whole query")
    @("NOT")
    bool not;

    ImapFlag[] flags;

    @("FROM")
    string fromContains;

    @("CC")
    string ccContains;

    @("BCC")
    string bccContains;

    @("TO")
    string toContains;

    @("SUBJECT")
    string subjectContains;

    @("BODY")
    string bodyContains;

    @("TEXT")
    string textContains;

    @("BEFORE")
    Date beforeDate;

    @("HEADER")
    string[string] headerFieldContains;

    @("KEYWORD")
    string[] hasKeyword;

    @("SMALLER")
    ulong smallerThanBytes;

    @("LARGER")
    ulong largerThanBytes;

    @("NEW")
    bool isNew;

    @("OLD")
    bool isOld;

    @("ON")
    Date onDate;

    @("SENTBEFORE")
    Date sentBefore;

    @("SENTON")
    Date sentOn;

    @("SENTSINCE")
    Date sentSince;

    @("SINCE")
    Date since;

    @("UID")
    ulong[] uniqueIdentifiers;

    @("UID")
    UidRange[] uniqueIdentifierRanges;

    string applyNot(string s) {
        import std.string : join;

        return not ? ("NOT " ~ s) : s;
    }

    template isSILdoc(alias T) {
        enum isSILdoc = is(typeof(T) == SILdoc);
    }

    void toString(scope void delegate(const(char)[]) sink) {
        import std.range : dropOne;
        import std.string : toUpper;
        import std.conv : to;
        import std.meta : Filter, templateNot;
        import std.traits : isFunction;
        foreach (flag; flags) {
            sink(applyNot(flag.to!string.dropOne.toUpper));
        }
        static foreach (M; Filter!(templateNot!isFunction, __traits(allMembers, typeof(this)))) {
            {
                enum udas = Filter!(templateNot!isSILdoc, __traits(getAttributes, __traits(getMember, this, M)));
                static if (udas.length > 0) {
                    alias T = typeof(__traits(getMember, this, M));
                    enum name = udas[0].to!string;
                    auto v = __traits(getMember, this, M);
                    static if (is(T == string)) {
                        if (v.length > 0) {
                            sink(applyNot(name));
                            sink(" \"");
                            sink(v);
                            sink("\" ");
                        }
                    } else static if (is(T == Date)) {
                        if (v != Date.init) {
                            sink(applyNot(name));
                            sink(" ");
                            sink(__traits(getMember, this, M).rfcDate);
                            sink(" ");
                        }
                    } else static if (is(T == bool) && (name != "NOT")) {
                        if (v) {
                            sink(applyNot(name));
                            sink(" ");
                        }
                    } else static if (is(T == string[string])) {
                        foreach (entry; __traits(getMember, this, M).byKeyValue) {
                            sink(applyNot(name));
                            sink(" ");
                            sink(entry.key);
                            sink(" \"");
                            sink(entry.value);
                            sink("\" ");
                        }
                    } else static if (is(T == string[])) {
                        foreach (entry; __traits(getMember, this, M)) {
                            sink(applyNot(name));
                            sink(" \"");
                            sink(entry);
                            sink("\" ");
                        }
                    } else static if (is(T == ulong[])) {
                        if (v.length > 0) {
                            sink(applyNot(name));
                            sink(" ");
                            auto len = __traits(getMember, this, M).length;
                            foreach (i, entry; __traits(getMember, this, M)) {
                                sink(entry.to!string);
                                if (i != len - 1)
                                    sink(",");
                            }
                            static if (name == "UID") {
                                if (len > 0 && uniqueIdentifierRanges.length > 0)
                                    sink(",");
                                len = uniqueIdentifierRanges.length;
                                foreach (i, entry; uniqueIdentifierRanges) {
                                    sink(entry.to!string);
                                    if (i != len - 1)
                                        sink(",");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

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

@SILdoc("Convert a SIL date to an RFC-2822 / IMAP Date string")
string rfcDate(Date date) {
    import std.format : format;
    import std.conv : to;
    import std.string : capitalize;
    return format!"%02d-%s-%04d"(date.day, date.month.to!string.capitalize, date.year);
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
