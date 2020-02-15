#!/bin/bash
#set -x

BLUE=`tput setaf 4`
RED=`tput setaf 1`
NC=`tput sgr0`

# Number of Staking Account
LISTUNSPENT=`mktemp`
bltg-cli listunspent > ${LISTUNSPENT}

I=0
for ADDRESS in `cat ${LISTUNSPENT} | jq -r '.[] .address' | sort -u`
do
  BALANCE=`cat ${LISTUNSPENT} | jq -r --arg ADDRESS "${ADDRESS}" '.[] | select (.address == $ADDRESS) .amount' | awk '{sum += $0} END {printf "%.8f", sum}'`
  if [[ $(echo "${BALANCE} > 0" | bc -l ) -eq 1 ]] && [[ $(echo "${BALANCE} < 12000" | bc -l ) -eq 1 ]]
  then
    ((I++))
    ACCOUNT[${I}]=${ADDRESS}
    ACCTYPE[${I}]="bltgStake${I}"
    ACCTTOT[${I}]=${BALANCE}
    #bltg-cli setaccount "${ACCOUNT[${I}]}" "${ACCTYPE[${I}]}"
  fi
done
rm ${LISTUNSPENT}

((I++))
ACCOUNT[${I}]="GgQgfBkgHdNSgdTvJ35rgr2auLkB7oQnGN"
ACCTYPE[${I}]="bltgMN1"

N=${I}

# Convert seconds to days, hours, minutes, seconds.
DISPLAYTIME () {
  # Round up the time.
  local T=0
  T=$( printf '%.*f\n' 0 "${1}" )
  local D=$(( T/60/60/24 ))
  local H=$(( T/60/60%24 ))
  local M=$(( T/60%60 ))
  local S=$(( T%60 ))
  (( D > 0 )) && printf '%d days ' "${D}"
  (( H > 0 )) && printf '%d hours ' "${H}"
  (( M > 0 )) && printf '%d minutes ' "${M}"
  (( S > 0 )) && printf '%d seconds ' "${S}"
}

clear

#bltg-cli mnsync status
#bltg-cli getblockchaininfo | grep blocks
#echo -ne "Staking State:      "; bltg-cli getstakingstatus | grep staking | awk -F: '{print $2}'
WALBLKCOUNT=`bltg-cli getblockcount`
NETBLKCOUNT=`curl -s https://explorer.block-logic.com/api/getblockcount`
DIFBLKCOUNT=$(( NETBLKCOUNT - WALBLKCOUNT ))

printf "%-20s%s\n" "${RED}Staking State:${NC}      " "`bltg-cli getstakingstatus | jq '."staking status"'`"
printf "%-20s%s\n" "${RED}Block Count:${NC}        " "$WALBLKCOUNT"
printf "%-20s%s\n" "${RED}Block Count Network:${NC}" "$NETBLKCOUNT"
printf "%-20s%s\n" "${RED}Diff in Blk Count:${NC}  " "$DIFBLKCOUNT"
printf "%-20s%s\n" "${RED}Keys Left:${NC}          " "`bltg-cli getwalletinfo | jq .keypoolsize`"
printf "%-20s%s\n" "${RED}Network Hashrate:${NC}   " "`bltg-cli getnetworkhashps`"
printf "%-20s%s\n" "${RED}Network Difficulty:${NC} " "`bltg-cli getdifficulty`"
#printf "%-20s%s\n" "${RED}Stake Input Amount:${NC} " "`bltg-cli liststakeinputs | jq '.[] .amount'`"

I=1
until [ $I -gt $N ]
do
  #bltg-cli listtransactions | jq '.[] | select(.address=="GZ6H3Rhgy98No8qZz4BTSxMeCrNhAp5W9P") | select(.category=="receive")'

  ACCT_BAL=`bltg-cli listunspent | jq --arg ACCOUNT "${ACCOUNT[$I]}" '.[] | select(.address==$ACCOUNT) | .amount'`
  #ACCT_BAL=`bltg-cli listtransactions | jq -r --arg ACCOUNT "${ACCOUNT[$I]}" '.[] | select(.address==$ACCOUNT) | select(.category=="receive") .amount'`
  if [ "${ACCT_BAL}" > 0 ]
  then
    echo "${BLUE}${ACCTYPE[$I]}:${NC}"
    printf "%-20s%s\n" "  ${RED}Stake Input Amt:${NC}  " "${ACCT_BAL}"
  fi

  # Increment Counter
  ((I=I+1))
  #bltg-cli getwalletinfo
done

echo

