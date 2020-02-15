#!/bin/bash
# Description: Monitor bltg core
#              1) Look for "receive" transaction and send notice
#              2) Ensure bltg process is running
#              Send Email and SMS if 1 and/or 2 generates alert
#
# Author:      Zaki Alam (zaki.alam@gmail.com)
#
# Addl Pkg:    jq, ssmtp
#
# Revisions:   v1 - Core transaction monitoring
#

# Uncomment to Debug
if [[ "$1" == "-d" ]]
then
  set -x
fi

# Parameters
if [ ! -z $HOME ]
then
    export HOME=/home/ubuntu
fi
export PATH=$HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/bltg/bin

# Set Email, Mobile and Email-to-SMS Gateway information
SENDTOEMAIL=<add-email-address>
SENDTOMOBILE=<add-mobile>
# Update Email to SMS gateway from the list
# https://www.lifewire.com/sms-gateway-from-email-to-sms-text-message-2495456
SENDTOGATEWAY=tmomail.net

# Which Timezone you want to see notices
export TZ=UTC

# Logfile
LOGFILE=$HOME/log/bltg_monitor.log

# Temp Files
TOMAILFILE=/tmp/stake_mail.txt
TOSMSFILE=/tmp/stake_sms.txt

# URLs
CMCTICKER="block-logic"
EXPLORERAPI="https://explorer.block-logic.com/api"
CMCAPI="https://api.coinmarketcap.com/v1/ticker/${CMCTICKER}/"
MNREWARD="6.4"
STAKEREWARD="1.6"

# Number of Staking Account
LISTUNSPENT=`mktemp`
bltg-cli listunspent > ${LISTUNSPENT}
#bltg-cli listunspent | jq -r '.[] .address' | sort -u > ${LISTACCT}

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

# Uncomment and add MN account
#((I++))
#ACCOUNT[${I}]="add-mn-account-number"
#ACCTYPE[${I}]="bltgMN1"

N=${I}

# Add timestamp to Log
function log {
    echo "[$(date --rfc-3339=seconds)]: $*" >> $LOGFILE
}

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

# Main Routine - Iterate through Accounts
LISTTRANS=`mktemp`
bltg-cli listtransactions > ${LISTTRANS}

I=1
until [ $I -gt $N ]
do
	RWDTXID=`cat ${LISTTRANS} | jq  -r --arg ACCOUNT "${ACCOUNT[$I]}" '.[] | select(.confirmations<10) | select(.address==$ACCOUNT) | select(.category=="receive") | select(.generated==true) .txid' | tail -1`

    if [ "x$RWDTXID" = "x" ]
    then
        log "${ACCTYPE[$I]}: No stake received"
	TXID=`cat ${LISTTRANS} | jq -r --arg ACCOUNT "${ACCOUNT[$I]}" '.[] | select(.confirmations>10) | select(.confirmations<20) | select(.address==$ACCOUNT) | select(.category=="receive") | select(.generated==true) .txid' | tail -1`
	if [ "x$TXID" != "x" ]
	then
            IMMATURENOTICE=/tmp/${TXID}.staked

	    if [ -f ${IMMATURENOTICE} ]
	    then
		log "${ACCTYPE[$I]}: Remove notification file"
		#cp $IMMATURENOTICE $IMMATURENOTICE.save
		rm $IMMATURENOTICE
	    fi
	fi

    else
        IMMATURENOTICE=/tmp/${RWDTXID}.staked
	if [ ! -f ${IMMATURENOTICE} ]
	then
	    #bltg-cli listtransactions > $IMMATURENOTICE
	    cat ${LISTTRANS} > $IMMATURENOTICE

	    BLTG_PRICE=`curl -k -s ${CMCAPI} | jq -r '.[] .price_usd'`
            STAKEAMT=`cat $IMMATURENOTICE | jq -r --arg RWDTXID "${RWDTXID}" '.[] | select(.txid==$RWDTXID) | select(.amount >= 0) .amount'`
            STAKERWD=`cat $IMMATURENOTICE | jq -r --arg ACCOUNT "${ACCOUNT[$I]}" '.[] | select(.confirmations<10) | select(.address==$ACCOUNT) | select ( .amount >= 0) | select (.category == "receive") | select(.generated==true) .amount'`
	    STAKECONF=`cat $IMMATURENOTICE | jq -r --arg RWDTXID "${RWDTXID}" '.[] | select(.txid==$RWDTXID) | select(.category == "receive") | select(.generated==true) .confirmations'`
            STAKETXID=`cat $IMMATURENOTICE | jq -r --arg ACCOUNT "${ACCOUNT[$I]}" --arg STAKECONF ${STAKECONF} '.[] | select(.confirmations==($STAKECONF | tonumber)) | select(.address==$ACCOUNT) | select ( .amount >= 0) | select (.category == "receive") | select(.generated==true) .txid' | tail -1`

            log "${ACCTYPE[$I]}: *** Stake received ***"

	    # Get average staking times for masternode and staking rewards
	    LIST_STAKE_INPUTS=''
            ALL_STAKE_INPUTS_BALANCE_COUNT=''
	    BLOCKTIME_SECONDS=60
	    NET_HASH_FACTOR=0.000001

	    NETWORKHASHPS=`bltg-cli getnetworkhashps 2>&1 | grep -Eo '[+-]?[0-9]+([.][0-9]+)?' 2>/dev/null`
	    COINS_STAKED_TOTAL_NETWORK=`echo "${NETWORKHASHPS} * ${NET_HASH_FACTOR}" | bc -l`
	    WALLETINFO=`bltg-cli getwalletinfo`
	    GETBALANCE=`echo ${WALLETINFO} | jq -r '.balance'`
	    GETTOTALBALANCE=`echo "${WALLETINFO}" | jq -r '.balance, .unconfirmed_balance, .receive_balance' | awk '{sum += $0} END {printf "%.8f", sum}'`
	    if [[ "${STAKEAMT}" = "${MNREWARD}" ]]
        then
          STAKERWD=12000
          ACCTYPE[$I]="bltgMn1"
        else
          #curl -s ${EXPLORERAPI}/tx/${RWDTXID}
          TMPBAL=`mktemp`
          curl -s ${EXPLORERAPI}/tx/${RWDTXID} | jq -r --arg ACCOUNT "${ACCOUNT[$I]}" '.carverAddressMovements[] | select(.carverAddress.label==$ACCOUNT)' > ${TMPBAL}
          AMOUNTIN=`cat ${TMPBAL} | jq '.amountIn'`
          AMOUNTOUT=`cat ${TMPBAL} | jq '.amountOut'`
          STAKEAMT=`echo "${AMOUNTIN} - ${AMOUNTOUT}" | bc -l`
          GETBALANCE=`cat ${TMPBAL} | jq '.balance'`
          GETTOTALBALANCE=`echo "${GETTOTALBALANCE} - 12000" | bc -l`
          rm ${TMPBAL}
	    fi

      echo "To: ${SENDTOEMAIL}" > $TOMAILFILE
      echo "From: ${SENDTOEMAIL}" >> $TOMAILFILE
      echo "Subject: ${ACCTYPE[$I]} - Stake received" >> $TOMAILFILE
      echo ""  >> $TOMAILFILE

      echo -ne "Time stake reward received: " >> $TOMAILFILE
      date -d @`cat $IMMATURENOTICE | jq -r --arg ACCOUNT "${ACCOUNT[$I]}" '.[] | select(.confirmations<10) | select(.address==$ACCOUNT) | select(.category == "receive") |  select(.generated==true) .timereceived'` +'%Y-%m-%d %H:%M:%S' >> $TOMAILFILE
	    echo "Staked Rwd:  ${STAKERWD}" >> $TOMAILFILE
	    echo "Staked Amt:  ${STAKEAMT}" >> $TOMAILFILE
	    echo "Staked txid: ${RWDTXID}" >> $TOMAILFILE
	    echo "BLTG Market Price: ${BLTG_PRICE}" >> $TOMAILFILE
	    echo "Network Hashrate: ${NETWORKHASHTH}" >> $TOMAILFILE
	    echo "Network Coin staked: ${COINS_STAKED_TOTAL_NETWORK}" >> $TOMAILFILE
	    #echo "Skaking ETA: ${HOURS_TO_AVERAGE_STAKE} in hr" >> $TOMAILFILE
	    #echo "Staking ETA: ${TIME_TO_STAKE}" >> $TOMAILFILE

      echo "" >> $TOMAILFILE

	    # SMS Message
      echo "To: ${SENDTOMOBILE}@${SENDTOGATEWAY}" > $TOSMSFILE
      echo "From: ${SENDTOEMAIL}" >> $TOSMSFILE
      echo "Subject:${ACCTYPE[$I]} " >> $TOSMSFILE
      echo ""  >> $TOSMSFILE

      echo -ne "Stake received at " >> $TOSMSFILE
TZ=EST5EDT date -d @`cat $IMMATURENOTICE | jq -r --arg ACCOUNT "${ACCOUNT[$I]}" '.[] | select(.confirmations<10) | select(.address==$ACCOUNT) | select(.category == "receive") | select(.generated==true) .timereceived'` +'%Y-%m-%d %H:%M:%S' >> $TOSMSFILE
      echo ""  >> $TOSMSFILE

      echo "Unspent funds:" >> $TOMAILFILE
      bltg-cli listunspent | jq '.[] | { address: .address, txid: .txid, amount: .amount, confirmations: .confirmations, spendable: .spendable } ' >> $TOMAILFILE
      echo ""  >> $TOMAILFILE

      echo "List Transaction for staked fund:" >> $TOMAILFILE
      cat $IMMATURENOTICE | jq '.[] | select(.category == "receive")' >> $TOMAILFILE
      echo ""  >> $TOMAILFILE

      # Send email
	    log "${ACCTYPE[$I]}: Send email"
      ssmtp ${SENDTOEMAIL} < $TOMAILFILE
      ssmtp ${SENDTOMOBILE}@${SENDTOGATEWAY} < $TOSMSFILE

	    # Remove temp files
	    log "${ACCTYPE[$I]}: Remove temp files"
      rm $TOMAILFILE
      rm $TOSMSFILE

    else
      log "${ACCTYPE[$I]}: Notice already sent"
    fi
  fi

# Increment Counter
((I=I+1))

done
    
# Cleanup
rm ${LISTTRANS}

# Check if Process is running
TELOSPID=`ps -ef | grep bltgd | grep -v "grep bltgd" | grep -v "grep --color=auto bltgd" | awk '{print $2}'`

if [ "x$TELOSPID" = "x" ]
then
    log "Critical: BLTG daemon is down on $HOSTNAME"
    echo "To: ${SENDTOEMAIL},${SENDTOMOBILE}@${SENDTOGATEWAY}" > $TOMAILFILE
    echo "From: ${SENDTOEMAIL}" >> $TOMAILFILE
    echo "Subject: ***BLTG daemon is down!!!***" >> $TOMAILFILE
    echo ""  >> $TOMAILFILE
    echo "There is no BLTG daemon process running on $HOSTNAME" >> $TOMAILFILE

    # Send email
    log "Critical: Notice sent via email and text"
    ssmtp ${SENDTOEMAIL},${SENDTOMOBILE}@${SENDTOGATEWAY} < $TOMAILFILE
    rm $TOMAILFILE
fi

