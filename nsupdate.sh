#!/bin/bash

help () {
	cat <<-EOF
	$0 to add or delete host entries to local dns server
	also takes care of reverse record
	add a host entry to dns service
	   $0 [-v][-r|R] [-t TTL] -a host ip
	remove a host entry
	   $0 [-v][-r|R] -d host
	help info:
	   $0 -h
	Option:
	   -d delete entries
	   -a add entries
	   -r do add or delete reverse record (default)
	   -R do not add or delete reverse record (default if * in hostname)
	   -t TTL overwrite the default TTL of 300 seconds with your own value

	   -v verbose
	   -V highly verbose
	   -n non active aka dry run
	EOF
	# not implelented yet:
	## OPTIONAL: define different domain
	## -D domain
}

reverseIP() {
    echo $1 | sed -Ee 's/([0-9]*)[.]([0-9]*)[.]([0-9]*)[.]([0-9]*)/\4.\3.\2.\1/'
}

fqhn() {
    if echo $1 | grep -qE '[.]$' ;  then 
       echo $1
    else
       echo $1.${DOMAIN}.
    fi
}

rev_or_not() {
   DOREVERSE=false 
   DONTREVERSE=false 
   $FORCE_DOREVERSE && DOREVERSE=true && return
   $FORCE_DONTREVERSE && DONTREVERSE=true && return
   if echo $1 | grep -qE '^[*]' ;  then 
     DONTREVERSE=true 
   else
     DOREVERSE=true 
   fi
}
        
rev_add_cmd() {
	REVADDCMD=""
	$DOREVERSE && REVADDCMD="update add $REVIP.in-addr.arpa. 300 PTR $HOSTNAME"
}

add_cmd() {
    NSUPDATE=$(cat <<-EOF
	update add $HOSTNAME 300 A $IP
	$REVADDCMD
	send
	EOF
    )
}

rev_del_cmd() {
	REVDELCMD=""
	$DOREVERSE && REVDELCMD="update del $REVIP.in-addr.arpa. PTR"
}
del_cmd() {
    NSUPDATE=$(cat <<-EOF
	update del $HOSTNAME A 
	$REVDELCMD
	send
	EOF
    )
}

## MAIN

DOMAIN=rh.hpecic.net
CMD="nsupdate  -k /etc/named.key"
NSUPDATE=""

OPTSTRING=":adrRhvVnt:"
ADD=false
DEL=false
FORCE_DONTREVERSE=false
FORCE_DOREVERSE=false
VERBOSE=false
HIGHLYVERBOSE=false
ARMED=true
TTL=300

while getopts ${OPTSTRING} opt; do
  case ${opt} in
    a)
      ADD=true
      ;;
    d)
      DEL=true
      ;;
    v)
      VERBOSE=true
      ;;
    V)
      HIGHLYVERBOSE=true
      VERBOSE=true
      ;;
    n)
      ARMED=false
      VERBOSE=true
      ;;
    t)
      [[ "$OPTARG" =~ ^[0123456789]+$ ]] || (
        echo "TTL needs to be integer value"
        exit 3
      )
      TTL=$OPTARG
      ;;
    r)
      $FORCE_DONTREVERSE && (
        echo "-r and -R are mutual exclusive"
        exit 2
      )
      FORCE_DOREVERSE=true
      ;;
    R)
      $FORCE_DOREVERSE && (
        echo "-r and -R are mutual exclusive"
        exit 2
      )
      FORCE_DONTREVERSE=true
      ;;
    h)
      help
      exit 0
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      exit 3
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done
$HIGHLYVERBOSE && echo OPTIND=$OPTIND
shift $((OPTIND - 1))
$HIGHLYVERBOSE && echo ARG#=$#


if $ADD && [ $# != 2 ] ; then
      echo "invalid number of arguments." 
      exit 1
fi
if $DEL && [ $# != 1 ] ; then
      echo "invalid number of arguments." 
      exit 1
fi

HOSTNAME=$(fqhn $1)
$ADD && IP=$2
$DEL && IP=$(dig +short $HOSTNAME)
REVIP=$(reverseIP $IP)

rev_or_not $HOSTNAME

$HIGHLYVERBOSE && { 
    HOSTNAME=$HOSTNAME
    echo IP=$IP
    echo REVIP=$REVIP
    echo DOREVERSE=$DOREVERSE
    echo DONTREVERSE=$DONTREVERSE
}


$ADD && add_cmd
$DEL && del_cmd

$VERBOSE && echo -e "CMD is:\n$CMD <<-EOF\n$NSUPDATE\nEOF"
$ARMED && {
	$CMD <<-EOF
	$NSUPDATE
	EOF
}
