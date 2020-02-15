#!/bin/bash

SAVEDIR=/home/ubuntu/etc
TODAY=`date +%Y%m%d`
PEERLIST=peers_${TODAY}.txt

echo -ne "Number of Connections: "
bltg-cli getconnectioncount
echo -ne "External IP: "
dig +short myip.opendns.com @resolver1.opendns.com
echo
#bltg-cli getpeerinfo | jq '.[] | .addr' | sed 's/"//g' | awk -F\: '{print $1}' >> $SAVEDIR/$PEERLIST
#bltg-cli getpeerinfo | jq -r '.[] | "\(.addr)  \t \(.inbound) \t \(.subver)" ' > $SAVEDIR/$PEERLIST
bltg-cli getpeerinfo | jq -r '.[] | "\(.addr)  \t \(.inbound) \t \(.subver) \t \(.pingtime*1000)" '
