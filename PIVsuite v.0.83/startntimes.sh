#!/bin/bash
umask 0
for (( i=1; i<=$2; i++ ))
   do
      matlab -nojvm -r $1 > ../output$i.txt &
      echo "Matlab no. $i started"
      sleep 1s
   done
  