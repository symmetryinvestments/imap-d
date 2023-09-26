module jmap.resolv;

/+

*******************************************************************
 * Test DNS SRV lookups
 * copyright Gerald Carter <jerry@samba.org>  2006
 *
 * For some bizarre reason the ns_initparse(), et. al. routines
 * are not available in the shared version of libresolv.so.
 *
 * To compile, run
 *    dmd dnstest -L-lresolv
 *
 *******************************************************************/

/* standard system headers */

import std.stdio;
import std.string;
import core.sys.posix.netinet.in_;
import std.exception : enforce;
import std.experimental.logger : tracef;
import core.stdc.string : strerror;
import core.stdc.errno : errno;

enum ns_s_max = 4;
extern(C) struct dst_key;

/* resolver headers */
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/nameser.h>
#include <resolv.h>

#include <netdb.h>
alias fromCString = fromStringz;

struct RecordSRV
{
    string name;
    string address;
}


void main(string[] args)
{
    auto records = getRecordsSRV(args[1]);
    foreach(record;records)
        writeln(record);
}

RecordSRV[] getRecordsSRV(string hostname)
{
    ns_msg h;
    ns_rr rr;

    RecordSRV[] records;

    char[NS_PACKETSZ] buffer;
    // send the request

    int resp_len = res_query(cast(char*) hostname.toStringz, NSClass.in_, NSType.srv, buffer.ptr, buffer.sizeof);
    enforce(resp_len >=0, format!"Query for %s failed"(hostname));
    writefln("resp = %s",buffer);
    // now do the parsing
    auto result = ns_initparse( cast(const(char)*) buffer.ptr, resp_len, &h );
    enforce (!result, "Failed to parse response buffer");

    int numAnswerRecords = ns_msg_count(h, NSSect.an);
    writefln("num an Records = %s",numAnswerRecords);

    foreach(recordNum; 0 .. numAnswerRecords)
    {
        result = ns_parserr( &h, NSSect.an, recordNum, &rr );
        if(result)
        {
            stderr.writefln("ns_parserr: %s, %s" ,result,strerror(errno).fromStringz);
            continue;
        }

        if ( ns_rr_type(rr) == NSType.srv ) {
            char[4096] name;
            in_addr ip;

            //int ret = dn_expand( cast(const(char)*) ns_msg_base(h), cast(const(char)*) ns_msg_end(h), cast(const(char)*) ns_rr_rdata(rr)+6, name.ptr, name.sizeof);
            int ret = dn_expand( cast(char*) ns_msg_base(h), cast(char*) ns_msg_end(h), cast(char*) ns_rr_rdata(rr)+6, name.ptr, name.sizeof);
            enforce(ret >=0, format!"Failed to uncompress name (%s)"(ret));
            tracef("%s",name);
            records ~= RecordSRV(name.ptr.fromStringz.idup,"");
        }
    }

    numAnswerRecords = ns_msg_count(h, NSSect.ar);
    writefln("num ar Records = %s",numAnswerRecords);

    foreach(recordNum; 0 .. numAnswerRecords)
    {
        writefln("%s",ns_rr_type(rr));
        result = ns_parserr( &h, NSSect.ar, recordNum, &rr );
        if(result)
        {
            stderr.writefln("ns_parserr: %s" ,strerror(errno).fromStringz);
            continue;
        }

        if ( ns_rr_type(rr) == NSType.a ) {
            import std.conv : to;
            char*[1024] name;
            in_addr ip;
            //const(char)** p = ns_rr_rdata(rr);
            auto p = ns_rr_rdata(rr);
            writeln("%s",p);
            ip.s_addr = (p[3].to!int << 24) | (p[2].to!int << 16) | (p[1].to!int << 8) | p[0].to!int;
            records ~= RecordSRV(ns_rr_name(rr).idup, inet_ntoa(ip).fromStringz.idup);
        }
    }

    return records;
}

extern(C) @system:

/*
 * Copyright (c) 1983, 1987, 1989
 *    The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * Portions Copyright (c) 1996-1999 by Internet Software Consortium.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND INTERNET SOFTWARE CONSORTIUM DISCLAIMS
 * ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL INTERNET SOFTWARE
 * CONSORTIUM BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
 * DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
 * PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
 * ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
 * SOFTWARE.
 */

/*
 *  @(#)resolv.h    8.1 (Berkeley) 6/2/93
 *  $BINDId: resolv.h,v 8.31 2000/03/30 20:16:50 vixie Exp $
 */

/+
#include <sys/cdefs.h>
#include <sys/param.h>
#include <sys/types.h>
#include <stdio.h>
#include <netinet/in.h>
#include <arpa/nameser.h>
#include <bits/types/res_state.h>
+/
/*
 * Global defines and variables for resolver stub.
 */
enum LOCALDOMAINPARTS   = 2;    /* min levels in name that is "local" */

enum ResolverCode
{
    timeout = 5,                // min. seconds between retries
    maxNDots = 15,              // should reflect bit field size
    maxRetrans = 30,            // only for resolv.conf/RES_OPTIONS
    maxRetry = 5,               // only for resolv.conf/RES_OPTIONS
    defaultTries = 2,           // Default tries
    maxTime = 65535,            // Infinity, in milliseconds
}


//alias nsaddr = nsaddr_list[0];        /* for backward compatibility */

/*
 * Revision information.  This is the release date in YYYYMMDD format.
 * It can change every day so the right thing to do with it is use it
 * in preprocessor commands such as "#if (__RES > 19931104)".  Do not
 * compare for equality; rather, use it to determine whether your resolver
 * is new enough to contain a certain feature.
 */

enum __RES  = 19991006;

/*
 * Resolver configuration file.
 * Normally not present, but may contain the address of the
 * initial name server(s) to query and the domain search list.
 */

enum _PATH_RESCONF = "/etc/resolv.conf";

struct res_sym
{
    int number;     /* Identifying number, like T_MX */
    char** name;        /* Its symbolic name, like "MX" */
    char** humanname;   /* Its fun name, like "mail exchanger" */
}

/*
 * Resolver options (keep these in synch with res_debug.c, please)
 */
enum ResolverOption
{
    init = 0x00000001,          // address initialized
    debugMessages = 0x00000002, // print debug messages
    aaOnly = 0x00000004,
    useVirtualCircuit = 0x00000008,     // use virtual circuit
    primary = 0x00000010,
    ignoreTruncationErrors = 0x00000020,    // ignore trucation errors
    recurse = 0x00000040,                   // recursion desired
    defaultDomainName = 0x00000080,         // use default domain name
    keepTCPSocketOPen = 0x00000100,         // Keep TCP socket open
    searchUpLocalDomainTree = 0x00000200,   // search up local domain tree
    shutOffHostAliases = 0x00001000,        // shuts off HOSTALIASES feature
    rotateNSListAfterEachQuery = 0x00004000, // rotate ns list after each query
    noCheckName =  0x00008000,
    keepTSig = 0x00010000,
    blast = 0x00020000,
    useEDNS0 = 0x00100000,                  // Use EDNS0.
    singleKUp = 0x00200000,                 // one outstanding request at a time
    singleKUpReop = 0x00400000,             //  -"-, but open new socket for each request
    useDNSSEC =  0x00800000,                // use DNSSEC using OK bit in OPT
    notLDQuery = 0x01000000,                //  Do not look up unqualified name as a TLD
    noReload = 0x02000000,                  // No automatic configuration reload
    trustAD = 0x04000000,                   // Request AD bit, keep it in responses
    default_ = ResolverOption.recurse | ResolverOption.defaultDomainName | ResolverOption.searchUpLocalDomainTree,
}

/*
 * Resolver "pfcode" values.  Used by dig.
 */
enum PfCode
{
 stats = 0x00000001,
 update = 0x00000002,
 class_ = 0x00000004,
 cmd = 0x00000008,
 ques = 0x00000010,
 ans = 0x00000020,
 auth = 0x00000040,
 add = 0x00000080,
 head1 = 0x00000100,
 head2 = 0x00000200,
 ttlID = 0x00000400,
 headx = 0x00000800,
 query = 0x00001000,
 reply = 0x00002000,
 init = 0x00004000,
/*          0x00008000  */
}

/* Things involving an internal (static) resolver context. */
//__res_state* __res_state(); //

void        fp_nquery (const(char)* *, int, FILE *);
void        fp_query (const(char)* *, FILE *);
const(char* )*  hostalias (const(char* )* );
void        p_query (const(char)* *);
void        res_close();
int     res_init();
int     res_isourserver (const sockaddr_in *);
int     res_mkquery (int, const(char* )* , int, int, const(char)* *, int, const(char)* *, char* *, int);
//int res_query(char*, int, int, char*, int);
int __res_query(char*, int, int, char*, int);
alias res_query = __res_query;
//extern(C) int     res_query (const(char)* , int, int, char*, int) ;
int     res_querydomain (const(char* )* , const(char* )* , int, int, char* *, int);
int     res_search (const(char* )* , int, int, char* *, int) ;
int     res_send (const(char)* *, int, char* *, int) ;


int     res_hnok (const(char* )* );
int     res_ownok (const(char* )* );
int     res_mailok (const(char* )* );
int     res_dnok (const(char* )* );
int     sym_ston (const res_sym *, const(char* )* , int *);
const(char* )*  sym_ntos (const res_sym *, int, int *);
const(char* )*  sym_ntop (const res_sym *, int, int *);
int     b64_ntop (const(char)* *, size_t, char* *, size_t);
int     b64_pton (char**, char**, size_t);
int     loc_aton (const(char* )* __ascii, char** __binary);
const(char* )*  loc_ntoa (const(char)* *__binary, char* *__ascii);
int     dn_skipname (const(char)* *, const(char)* *) ;
void putlong(uint, char**);
void putshort (ushort, char* *);
const(char* )*  p_class (int);
const(char* )*  p_time (ushort);
const(char* )*  p_type (int);
const(char* )*  p_rcode (int);
const(char)** p_cdnname (const(char)* *, const(char)* *, int, FILE *);
const(char)** p_cdname (const(char)* *, const(char)* *, FILE *);
const(char)** p_fqnname (const(char)* *__cp, const(char)* *__msg, int, char* *, int);
const(char)** p_fqname (const(char)* *, const(char)* *, FILE *);
const(char)** p_option (ulong __option);
int     dn_count_labels (const(char* )* );
int     dn_comp (const(char* )* , char* *, int, char* **, char* **);
// int  dn_expand(const(char)* msg, const(char)* eomorig, const(char)* comp_dn, char* exp_dn, int length);
//int   dn_expand(char* msg, char* eomorig, char* comp_dn, char* exp_dn, int length);
int __dn_expand(char* msg, char* eomorig, char* comp_dn, char* exp_dn, int length);
alias dn_expand = __dn_expand;
uint    res_randomid();
int     res_nameinquery (const(char* )* , int, int, const(char)* *, const(char)* *);
int     res_queriesmatch (const(char)* *, const(char)* *, const(char)* *, const(char)* *);
/* Things involving a resolver context. */
int     res_ninit (res_state);
void        fp_resstat (const res_state, FILE *);
const(char* )*  res_hostalias (const res_state, const(char* )* , char* *, size_t);
int res_nquery (res_state, const(char* )* , int, int, char* *, int);
int res_nsearch (res_state, const(char* )* , int, int, char* *, int);
int res_nquerydomain (res_state, const(char* )* , const(char* )* , int, int, char* *, int);
int res_nmkquery (res_state, int, const(char* )* , int, int, const(char)* *, int, const(char)* *, char* *, int);
int res_nsend (res_state, const(char)* *, int, char* *, int);
void    res_nclose (res_state);

// #include <sys/types.h>
// #include <netinet/in.h>

/* res_state: the global state used by the resolver stub.  */
enum MAXNS          =3; /* max # name servers we'll track */
enum MAXDFLSRCH     =3; /* # default domain levels to try */
enum MAXDNSRCH  =   6;  /* max # domains in search path */
enum MAXRESOLVSORT=     10; /* number of net to sort on */

struct res_state
{
    import std.bitmanip : bitfields;
    int retrans;        /* retransmition time interval */
    int retry;          /* number of times to retransmit */
    ulong options;      /* option flags - see below. */
    int nscount;        /* number of name servers */
    sockaddr_in[MAXNS] nsaddr_list; /* address of name server */
    ushort id;      /* current message id */
    /* 2 byte hole here.  */
    char*[MAXDNSRCH+1] dnsrch;  /* components of domain to search */
    char[256]   defdname;       /* default domain (deprecated) */
    ulong pfcode;       /* RES_PRF_ flags - see below. */

    mixin(bitfields!(
                uint, "ndots", 4,       // threshold for initial abs. query
                uint, "nsort", 4,       // number of elements in sort_list[]
                uint,"ipv6_unavail",1, // connecting to IPv6 server failed
                uint, "unused",23,
    ));
    struct SortListEntry
    {
        in_addr addr;
        uint mask;
    }
    SortListEntry [MAXRESOLVSORT] sort_list;
    /* 4 byte hole here on 64-bit architectures.  */
    void * __glibc_unused_qhook;
    void * __glibc_unused_rhook;
    int res_h_errno;        /* last one set for this context */
    int _vcsock;        /* PRIVATE: for res_send VC i/o */
    uint _flags;        /* PRIVATE: see below */
    /* 4 byte hole here on 64-bit architectures.  */
    union U
    {
        char[52] pad;   /* On an i386 this means 512b total. */
        struct Ext
        {
            ushort nscount;
            ushort[MAXNS] nsmap;
            int[MAXNS] nssocks;
            ushort nscount6;
            ushort nsinit;
            sockaddr_in6*[MAXNS] nsaddrs;
            uint[2] __glibc_reserved;
        }
       Ext _ext;
    }
   U _u;
};

/*
 * Copyright (c) 1983, 1989, 1993
 *    The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * Copyright (c) 2004 by Internet Systems Consortium, Inc. ("ISC")
 * Copyright (c) 1996-1999 by Internet Software Consortium.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND INTERNET SOFTWARE CONSORTIUM DISCLAIMS
 * ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL INTERNET SOFTWARE
 * CONSORTIUM BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
 * DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
 * PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
 * ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
 * SOFTWARE.
 */

/+
#include <sys/param.h>
#include <sys/types.h>
#include <stdint.h>
+/
/*
 * Define constants based on RFC 883, RFC 1034, RFC 1035
 */
enum NS_PACKETSZ    =512;   /*%< default UDP packet size */
enum NS_MAXDNAME    =1025;  /*%< maximum domain name */
enum NS_MAXMSG  =65535;     // %< maximum message size
enum NS_MAXCDNAME   =255;   // %< maximum compressed domain name */
enum NS_MAXLABEL    =63;        //  %< maximum length of domain label */
enum NS_HFIXEDSZ    =12;        //  /*%< #/bytes of fixed data in header */
enum NS_QFIXEDSZ    =4;     //  /*%< #/bytes of fixed data in query */
enum NS_RRFIXEDSZ   =10;    /*%< #/bytes of fixed data in r record */
enum NS_INT32SZ =4; /*%< #/bytes of data in a uint32_t */
enum NS_INT16SZ =2; /*%< #/bytes of data in a uint16_t */
enum NS_INT8SZ  =1; /*%< #/bytes of data in a uint8_t */
enum NS_INADDRSZ    =4; /*%< IPv4 T_A */
enum NS_IN6ADDRSZ   =16;    /*%< IPv6 T_AAAA */
enum NS_CMPRSFLGS   =0xc0;  /*%< Flag bits indicating name compression. */
enum NS_DEFAULTPORT =53;    /*%< For both TCP and UDP. */
/*
 * These can be expanded with synonyms, just keep ns_parse.c:ns_parserecord()
 * in synch with it.
 */
enum NSSect
{
    qd = 0,     /*%< Query: Question. */
    zn = 0,     /*%< Update: Zone. */
    an = 1,     /*%< Query: Answer. */
    pr = 1,     /*%< Update: Prerequisites. */
    ns = 2,     /*%< Query: Name servers. */
    ud = 2,     /*%< Update: Update. */
    ar = 3,     /*%< Query|Update: Additional records. */
    max = 4,
}

alias ns_sect = NSSect;
/*%
 * This is a message handle.  It is caller allocated and has no dynamic data.
 * This structure is intended to be opaque to all but ns_parse.c, thus the
 * leading _'s on the member names.  Use the accessor functions, not the _'s.
 */
struct ns_msg
{
    const(char)* _msg;
    const(char)* _eom;
    ushort _id;
    ushort _flags;
    ushort[ns_s_max] _counts;
    const(char)[ns_s_max]* _sections;
    ns_sect _sect;
    int _rrnum;
    const(char) *_msg_ptr;
}

/* Private data structure - do not use from outside library. */
//struct _ns_flagdata {  int mask, shift;  };
//extern const struct _ns_flagdata _ns_flagdata[];

/* Accessor macros - this is part of the public interface. */
auto ns_msg_id(ns_msg handle)
{
    return handle._id;
}

auto ns_msg_base(ns_msg handle)
{
    return  handle._msg;
}

auto ns_msg_end(ns_msg handle)
{
    return handle._eom;
}

auto ns_msg_size(ns_msg handle)
{
    return handle._eom - handle._msg;
}

auto ns_msg_count(Section)(ns_msg handle, Section section)
{
    return handle._counts[section];
}

/*%
 * This is a parsed record.  It is caller allocated and has no dynamic data.
 */
struct ns_rr
{
    char[NS_MAXDNAME] name;
    ushort type;
    ushort rr_class;
    uint ttl;
    ushort rdlength;
    const(char) *   rdata;
}

/* Accessor macros - this is part of the public interface. */
string ns_rr_name(ns_rr rr)
{
    return (rr.name[0] != '\0') ? rr.name.ptr.fromStringz.idup: ".";
}

auto ns_rr_type(ns_rr rr)
{
    return cast(NSType)rr.type;
}

auto ns_rr_class(ns_rr rr)
{
    return cast(NSClass) rr.rr_class;
}

auto ns_rr_ttl(ns_rr rr)
{
    return rr.ttl;
}

auto ns_rr_rdlen(ns_rr rr)
{
    return rr.rdlength;
}

char[] ns_rr_rdata(ns_rr rr)
{
    return rr.rdata[0.. rr.rdlength].dup;
}

/*%
 * These don't have to be in the same order as in the packet flags word,
 * and they can even overlap in some cases, but they will need to be kept
 * in synch with ns_parse.c:ns_flagdata[].
 */
enum FlagCode
{
    qr,     /*%< Question/Response. */
    opcode,     /*%< Operation code. */
    aa,     /*%< Authoritative Answer. */
    tc,     /*%< Truncation occurred. */
    rd,     /*%< Recursion Desired. */
    ra,     /*%< Recursion Available. */
    z,          /*%< MBZ. */
    ad,     /*%< Authentic Data (DNSSEC). */
    cd,     /*%< Checking Disabled (DNSSEC). */
    rcode,      /*%< Response code. */
    max
}

/*%
 * Currently defined opcodes.
 */
enum OpCode
{
    query = 0,      /*%< Standard query. */
    iquery = 1, /*%< Inverse query (deprecated/unsupported). */
    status = 2, /*%< Name server status query (unsupported). */
                /* Opcode 3 is undefined/reserved. */
    notify = 4, /*%< Zone change notification. */
    update = 5, /*%< Zone update message. */
    max = 6
}

/*%
 * Currently defined response codes.
 */
enum ResponseCode
{
    noerror = 0,    /*%< No error occurred. */
    formerr = 1,    /*%< Format error. */
    servfail = 2,   /*%< Server failure. */
    nxdomain = 3,   /*%< Name error. */
    notimpl = 4,    /*%< Unimplemented. */
    refused = 5,    /*%< Operation refused. */
    /* these are for BIND_UPDATE */
    yxdomain = 6,   /*%< Name exists */
    yxrrset = 7,    /*%< RRset exists */
    nxrrset = 8,    /*%< RRset does not exist */
    notauth = 9,    /*%< Not authoritative for zone */
    notzone = 10,   /*%< Zone of record different from zone section */
    _max = 11,
    /* The following are EDNS extended rcodes */
    badvers = 16,
    /* The following are TSIG errors */
    badsig = 16,
    badkey = 17,
    badtime = 18
}

/* BIND_UPDATE */
enum BindUpdateOperation
{
    delete_ = 0,
    add = 1,
    max = 2
}

/*%
 * This structure is used for TSIG authenticated messages
 */
struct ns_tsig_key
{
        char[NS_MAXDNAME] name;
        char[NS_MAXDNAME] alg;
        char *data;
        int len;
}

/*%
 * This structure is used for TSIG authenticated TCP messages
 */
struct ns_tcp_tsig_state
{
    int counter;
    dst_key *key;
    void *ctx;
    char[NS_PACKETSZ] sig;
    int siglen;
}

enum NS_TSIG_FUDGE = 300;
enum NS_TSIG_TCP_COUNT = 100;
enum NS_TSIG_ALG_HMAC_MD5 = "HMAC-MD5.SIG-ALG.REG.INT";

enum NS_TSIG_ERROR_NO_TSIG = -10;
enum NS_TSIG_ERROR_NO_SPACE = -11;
enum NS_TSIG_ERROR_FORMERR = -12;

/*%
 * Currently defined type values for resources and queries.
 */
enum NSType
{
    invalid = 0,
    a = 1,
    ns = 2,
    md = 3,
    mf = 4,
    cname = 5,
    soa = 6,
    mb = 7,
    mg = 8,
    mr = 9,
    null_ = 10,
    wks = 11,
    ptr = 12,
    hinfo = 13,
    minfo = 14,
    mx = 15,
    txt = 16,
    rp = 17,
    afsdb = 18,
    x25 = 19,
    isdn = 20,
    rt = 21,
    nsap = 22,
    nsap_ptr = 23,
    sig = 24,
    key = 25,
    px = 26,
    gpos = 27,
    aaaa = 28,
    loc = 29,
    nxt = 30,
    eid = 31,
    nimloc = 32,
    srv = 33,
    atma = 34,
    naptr = 35,
    kx = 36,
    cert = 37,
    a6 = 38,
    dname = 39,
    sink = 40,
    opt = 41,
    apl = 42,
    ds = 43,
    sshfp = 44,
    ipseckey = 45,
    rrsig = 46,
    nsec = 47,
    dnskey = 48,
    dhcid = 49,
    nsec3 = 50,
    nsec3param = 51,
    tlsa = 52,
    smimea = 53,
    hip = 55,
    ninfo = 56,
    rkey = 57,
    talink = 58,
    cds = 59,
    cdnskey = 60,
    openpgpkey = 61,
    csync = 62,
    spf = 99,
    uinfo = 100,
    uid = 101,
    gid = 102,
    unspec = 103,
    nid = 104,
    l32 = 105,
    l64 = 106,
    lp = 107,
    eui48 = 108,
    eui64 = 109,
    tkey = 249,
    tsig = 250,
    ixfr = 251,
    axfr = 252,
    mailb = 253,
    maila = 254,
    any = 255,
    uri = 256,
    caa = 257,
    avc = 258,
    ta = 32768,
    dlv = 32769,

    max = 65536
 }

/*%
 * Values for class field
 */
enum NSClass
{
    invalid = 0,    /*%< Cookie. */
    in_ = 1,        /*%< Internet. */
    ns_c_2 = 2,     /*%< unallocated/unsupported. */
    chaos = 3,      /*%< MIT Chaos-net. */
    hesiod  = 4,        /*%< MIT Hesiod. */
    /* Query class values which do not appear in resource records */
    none = 254, /*%< for prereq. sections in update requests */
    any = 255,      /*%< Wildcard match. */
    max = 65536
}

/* Certificate type values in CERT resource records.  */
enum NSCertType
{
    pkix = 1,   /*%< PKIX (X.509v3) */
    spki = 2,   /*%< SPKI */
    pgp  = 3,   /*%< PGP */
    url  = 253, /*%< URL private type */
    oid  = 254  /*%< OID private type */
}

/*%
 * EDNS0 extended flags and option codes, host order.
 */
enum NS_OPT_DNSSEC_OK        =0x8000U;
enum NS_OPT_NSID        =3;
/+

/*%
 * Inline versions of get/put short/long.  Pointer is advanced.
 */
enum NS_GET16(s, cp) do { \
    const(char) *t_cp = (const(char) *)(cp); \
    (s) = ((uint16_t)t_cp[0] << 8) \
        | ((uint16_t)t_cp[1]) \
        ; \
    (cp) += NS_INT16SZ; \
} while (0)

enum NS_GET32(l, cp) do { \
    const(char) *t_cp = (const(char) *)(cp); \
    (l) = ((uint32_t)t_cp[0] << 24) \
        | ((uint32_t)t_cp[1] << 16) \
        | ((uint32_t)t_cp[2] << 8) \
        | ((uint32_t)t_cp[3]) \
        ; \
    (cp) += NS_INT32SZ; \
} while (0)

enum NS_PUT16(s, cp) do { \
    uint16_t t_s = (uint16_t)(s); \
    char *t_cp = (char *)(cp); \
    *t_cp++ = t_s >> 8; \
    *t_cp   = t_s; \
    (cp) += NS_INT16SZ; \
} while (0)

enum NS_PUT32(l, cp) do { \
    uint32_t t_l = (uint32_t)(l); \
    char *t_cp = (char *)(cp); \
    *t_cp++ = t_l >> 24; \
    *t_cp++ = t_l >> 16; \
    *t_cp++ = t_l >> 8; \
    *t_cp   = t_l; \
    (cp) += NS_INT32SZ; \
} while (0)
+/
int     ns_msg_getflag (ns_msg, int);
uint    ns_get16 (const(char) *);
ulong   ns_get32 (const(char) *);
void        ns_put16 (uint, char *);
void        ns_put32 (ulong, char *);
int     ns_initparse (const(char) *, int, ns_msg *);
int     ns_skiprr (const(char) *, const(char) *, ns_sect, int);
int     ns_parserr (ns_msg*, ns_sect, int, ns_rr *);
int     ns_sprintrr (const ns_msg *, const ns_rr *, const(char) *, const(char) *, char *, size_t)
    ;
int     ns_sprintrrf (const(char) *, size_t, const(char) *, NSClass, NSType, ulong, const(char) *, size_t, const(char) *, const(char) *, char *, size_t);
int     ns_format_ttl (ulong, char *, size_t);
int     ns_parse_ttl (const(char) *, ulong *);
uint32_t    ns_datetosecs (const(char) *, int *);
int     ns_name_ntol (const(char) *, char *, size_t)
    ;
int     ns_name_ntop (const(char) *, char *, size_t);
int     ns_name_pton (const(char) *, char *, size_t);
int     ns_name_unpack (const(char) *, const(char) *,
                const(char) *, char *, size_t)
    ;
int     ns_name_pack (const(char) *, char *, int,
                  const(char) **, const(char) **)
    ;
int     ns_name_uncompress (const(char) *,
                    const(char) *,
                    const(char) *,
                    char *, size_t);
int     ns_name_compress (const(char) *, char *, size_t,
                  const(char) **,
                  const(char) **);
int     ns_name_skip (const(char) **, const(char) *)
    ;
void        ns_name_rollback (const(char) *,
                  const(char) **,
                  const(char) **);
int     ns_samedomain (const(char) *, const(char) *);
int     ns_subdomain (const(char) *, const(char) *);
int     ns_makecanon (const(char) *, char *, size_t);
int     ns_samename (const(char) *, const(char) *);
//__END_DECLS

// #include <arpa/nameser_compat.h>
+/
