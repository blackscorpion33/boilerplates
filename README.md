1) Put postinstall into directroy of choice (I use root). Add core-modules services to core-modules directory. Make a services directory, and if you make script installers for your docker files, add a modules directory.
2) chmod +x postinstall
3) run postinstall..

4) Postinstall will create directories need for the core-modules. When finished you will be presented a menu in which core modules you want installed. nftables.sh is geared toward my system, alter for your own. 
