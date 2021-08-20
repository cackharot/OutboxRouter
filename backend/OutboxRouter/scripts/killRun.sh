#!/bin/bash
APP=OutboxRouter-exe
pid=`pgrep $APP`
if [ -z "$pid" ]; then
    stack exec $APP &
    sleep 0.6
    echo -e "server running with PID={`pgrep $APP`} (if that's empty, then the server is not running)"
else
    echo -e "server already with PID=$pid"
fi
