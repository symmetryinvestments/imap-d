#!/usr/bin/env bash

set -euo pipefail

scriptfile=
if [[ $# != 2 ]] ; then
  echo "use: $(basename ${BASH_SOURCE}) <sil-binary> <server-ip>"
  exit 1
fi

silbin="$1"
server="$2"

if [[ ! -x "${silbin}" ]] ; then
  echo "Bad SIL binary: ${silbin}"
  exit 1
fi

# --------------------------------------------------------------------------------------------------

do_test() {
  script="$1"
  marker="$2"

  echo "${marker}:"
  if diff -uw \
    <(${silbin} "${script}" -- --user siluser --pass=secret123 --host=10.252.193.32 --port=993) \
    <(sed -n "/${marker}_START/,/${marker}_END/p" ${BASH_SOURCE} | grep -v 'START\|END')
  then
    echo '- passed.'
  else
    echo '- failed.'
  fi
}


# --------------------------------------------------------------------------------------------------

do_test biff.sil BIFF
do_test headers.sil HEADERS
do_test list_mailboxes.sil MAILBOXES
do_test search.sil SEARCH

exit 0

# --------------------------------------------------------------------------------------------------
: "

BIFF_START
INBOX: 2 new, 4 total.
BIFF_END

HEADERS_START
INBOX:
  Sat,  6 Apr 2019 21:30:13 +0800 (HKT)    | bob <bob@example.com>                    | I have an idea.
  Fri, 20 Mar 2020 06:53:33 +0800 (HKT)    | carlos <carlos@example.com>              | Re: Have you seen Bob?
  Tue, 31 Mar 2020 20:40:13 +0800 (HKT)    | carlos <carlos@example.com>              | Re: Have you seen Bob?
  Tue,  9 Dec 2031 12:47:28 +0800 (HKT)    | bob <bob@example.com>                    | Greetings from the future!

HEADERS_END

MAILBOXES_START
Mailboxes:
  + archive
    archive.personal
    archive.work
    spam
    support
    INBOX

MAILBOXES_END

SEARCH_START

UNRESOLVED ISSUES FROM THE PAST 10 DAYS:

Issue: 125
  Date: Thu, 14 May 2020 03:13:20 +0400 (SCT)
  Summary: We have developed an unhealthy co-dependency.
Issue: 129
  Date: Mon, 18 May 2020 15:33:20 +0400 (SCT)
  Summary: Process 332 (perl) crashed.
Issue: 130
  Date: Tue, 19 May 2020 11:00:00 +0400 (SCT)
  Summary: Maurice's locker is ticking.

SEARCH_END

"
# --------------------------------------------------------------------------------------------------
