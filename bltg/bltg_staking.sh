#!/bin/bash

case $1 in
        start)
                DAEMONSTAT=FALSE
                while [ "$DAEMONSTAT" != "true" ]
                do
                        DAEMONSTAT=`bltg-cli getstakingstatus | jq .mnsync`
                        echo "bltg mnsync status is: $DAEMONSTAT"
                        sleep 2
                done
                echo "  ...starting staking"
                umask 0077
                read -s -p "Enter wallet password: " WALLETPASS
                bltg-cli walletpassphrase $WALLETPASS 999999999 true
                ;;

        stop)
                echo "Stop staking..."
                bltg-cli stop
                ;;

        syncstat)
                bltg-cli mnsync status
                ;;

        stakestat)
                bltg-cli getstakingstatus
                ;;

        liststakeinputs)
                bltg-cli liststakeinputs
                ;;

        getwalletinfo)
                bltg-cli getwalletinfo
                ;;

        addtowallet)
                grep AddToWallet $HOME/.bltg/debug.log
                ;;

        networkcoins)
                echo -ne "number of coins being staking right now: "
                bltg-cli getnetworkhashps
                ;;

        *)
                echo "Syntax: $0 start|stop|syncstat|stakestat"
                ;;

esac


