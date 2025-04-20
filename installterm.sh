#!/bin/bash
## Termbin installer
## By marduk191
## email: marduk191@gmail.com

printf "%s\n" "Checking dependencies"

if ! dpkg-query -W netcat | grep . 
then printf "%s\n" "netcat isn't installed. Setting up netcat." 
     gksudo apt-get install netcat 
else printf "%s\n" "netcat is already installed!"
fi

if ! dpkg-query -W xclip | grep . 
then printf "%s\n" "xclip isn't installed. Setting up xclip." 
     gksudo apt-get install xclip 
else printf "%s\n" "xclip is already installed!"
fi

#Save some lines: modify if you are using POSIX without bash style echo
echo 'alias termbin="netcat virtualhacker.net 9999"' >> ~/.bashrc
echo 'alias copy="xclip -selection c"' >> ~/.bashrc

sleep 1

source ~/.bashrc

clear 

printf "%s\n" "Usage: input | termbin | copy. Then paste the link from your X clipboard"
