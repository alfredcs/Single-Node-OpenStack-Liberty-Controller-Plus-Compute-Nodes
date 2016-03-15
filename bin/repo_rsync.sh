## Mirror Synchronization Script /usr/local/bin/ubuntu-mirror-sync.sh
## Version 1.01 Updated 13 Feb 2007 by Peter Noble

## Point our log file to somewhere and setup our admin email
log=/var/log/mirrorsync.log

## Setup the server to mirror
remote=rsync://archive.ubuntu.com/ubuntu/ubuntu

## Setup the local directory / Our mirror
local=/local_repo/mirror/archive.ubuntu.com/ubuntu

## Initialize some other variables
complete="false"
failures=0
status=1
pid=$$

echo "`date +%x-%R` - $pid - Started Ubuntu Mirror Sync" >> $log
while [[ "$complete" != "true" ]]; do

        if [[ $failures -gt 0 ]]; then
                ## Sleep for 5 minutes for sanity's sake
                ## The most common reason for a failure at this point
                ##  is that the rsync server is handling too many concurrent connections.
                sleep 5m
        fi

        if [[ $1 == "debug" ]]; then
                echo "Working on attempt number $failures"
                rsync -a --delete-after --progress $remote $local
                status=$?
        else
                echo rsync -a --delete-after $remote $local >> $log
                status=$?
        fi
        
        if [[ $status -ne "0" ]]; then
                complete="false"
                (( failures += 1 ))
        else
                echo "`date +%x-%R` - $pid - Finished Ubuntu Mirror Sync" >> $log
        	complete="true"
        fi
done

exit 0
