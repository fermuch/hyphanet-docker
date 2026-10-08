#!/bin/bash
set -e

HYPHANET_HOME=${HYPHANET_HOME:-/opt/hyphanet}
HYPHANET_DATA=${HYPHANET_DATA:-/data}

SOCAT_LISTEN_PORT=8123
HYPHANET_FPROXY_PORT=8888
# How long to wait for the node's FProxy port to come up (seconds).
STARTUP_TIMEOUT=${STARTUP_TIMEOUT:-120}

echo "--- Entrypoint Start ---"
echo "DEBUG: Current User: $(whoami)"
echo "DEBUG: HYPHANET_HOME: ${HYPHANET_HOME}"
echo "DEBUG: HYPHANET_DATA: ${HYPHANET_DATA}"
echo "DEBUG: SOCAT Listen Port: ${SOCAT_LISTEN_PORT}"
echo "DEBUG: Hyphanet Fproxy Port: ${HYPHANET_FPROXY_PORT}"
echo "-------------------------"

echo "Searching for freenet.ini file..."
POTENTIAL_INI_PATHS=(
    "${HYPHANET_HOME}/freenet.ini"
    "${HYPHANET_HOME}/freenet/freenet.ini"
    "${HYPHANET_HOME}/Freenet/freenet.ini"
    "${HYPHANET_DATA}/freenet/freenet.ini"
    "${HYPHANET_DATA}/freenet.ini"
)

FREENET_INI_PATH=""
for ini_path in "${POTENTIAL_INI_PATHS[@]}"; do
    if [ -f "$ini_path" ]; then
        echo "Found freenet.ini at: $ini_path"
        FREENET_INI_PATH="$ini_path"
        break
    fi
done

if [ -z "$FREENET_INI_PATH" ]; then
    echo "WARN: Could not find freenet.ini in common locations!"
fi

PERSISTENT_ITEMS=(
    "freenet/freenet.ini"    
    "freenet.ini"
    "freenet.ini.bak" 
    "node.random" 
    "master.keys"
    "seednodes.fref" 
    "persistent-temp" 
    "downloads" 
    "plugins"
    "stats" 
    "store" 
    "wrapper.log"
)
echo "Setting up persistence links..."
mkdir -p "${HYPHANET_DATA}"
for item in "${PERSISTENT_ITEMS[@]}"; do
    src_path="${HYPHANET_HOME}/${item}"
    dest_path="${HYPHANET_DATA}/${item}"
    if [ -e "${src_path}" ] && [ ! -e "${dest_path}" ]; then
        mkdir -p "$(dirname "${dest_path}")"
        mv "${src_path}" "${dest_path}"
    fi
    if [ -e "${dest_path}" ]; then
        rm -rf "${src_path}"
        ln -sf "${dest_path}" "${src_path}"
    fi
done

if [ -z "$FREENET_INI_PATH" ]; then
    FREENET_INI_PATH="${HYPHANET_HOME}/freenet.ini"
fi
WRAPPER_LOG_PATH="${HYPHANET_DATA}/wrapper.log"
echo "Persistence setup done."

if [ "$1" = 'start' ]; then
    for ini_path in "${POTENTIAL_INI_PATHS[@]}"; do
        if [ -f "$ini_path" ]; then
            echo "Updating Fproxy configurations in $ini_path..."
                    
            sed -i -E 's#^fproxy\.bindTo[[:space:]]*=.*#fproxy.bindTo=0.0.0.0#g' "$ini_path"
            sed -i -E 's#^fproxy\.allowedHosts[[:space:]]*=.*#fproxy.allowedHosts=*#g' "$ini_path"
            sed -i -E 's#^fproxy\.allowedHostsFullAccess[[:space:]]*=.*#fproxy.allowedHostsFullAccess=*#g' "$ini_path"
                        
            grep -q "^fproxy.enabled" "$ini_path" || echo "fproxy.enabled=true" >> "$ini_path"
            grep -q "^fproxy.port" "$ini_path" || echo "fproxy.port=8888" >> "$ini_path"
                        
            grep -q "^fproxy.bindTo" "$ini_path" || echo "fproxy.bindTo=0.0.0.0" >> "$ini_path"
            grep -q "^fproxy.allowedHosts" "$ini_path" || echo "fproxy.allowedHosts=*" >> "$ini_path"
            grep -q "^fproxy.allowedHostsFullAccess" "$ini_path" || echo "fproxy.allowedHostsFullAccess=*" >> "$ini_path"
            
            echo "Updated configuration in $ini_path"
            echo "Current fproxy settings:"
            grep "fproxy" "$ini_path" || echo "No fproxy settings found!"
        fi
    done

    echo "Searching for start script..."
    declare -a potential_scripts=(
        "${HYPHANET_HOME}/run.sh" "${HYPHANET_HOME}/Hyphanet/run.sh"
        "${HYPHANET_HOME}/Freenet/run.sh" "${HYPHANET_HOME}/freenet/run.sh"
    )
    found_script=""
    for start_script in "${potential_scripts[@]}"; do
        if [ -f "$start_script" ]; then
            if [ -x "$start_script" ]; then
                found_script="$start_script"
                break
            else
                echo "Making script executable: $start_script"
                chmod +x "$start_script"
                if [ -x "$start_script" ]; then
                    found_script="$start_script"
                    break
                fi
            fi
        fi
    done

    if [ -n "$found_script" ]; then
        # The Tanuki wrapper (backend.type=PIPE) names its FIFOs after its own PID
        # (/tmp/wrapper-<pid>-1-in|-out). Container PIDs are reused across restarts,
        # so leftovers from an unclean shutdown make the next start fail with
        # "Unable to create backend pipe: File exists" and the node never comes up.
        echo "Removing stale wrapper runtime pipes..."
        rm -f "${TMPDIR:-/tmp}"/wrapper-*-in "${TMPDIR:-/tmp}"/wrapper-*-out

        echo "Attempting to start Hyphanet in background using: $found_script"        
        "$found_script" start

        echo "Waiting for Hyphanet to start and listen on port ${HYPHANET_FPROXY_PORT} (timeout: ${STARTUP_TIMEOUT}s)..."
        waited=0
        while [ "${waited}" -lt "${STARTUP_TIMEOUT}" ]; do
            if netstat -tuln | grep -qE "(127\.0\.0\.1|0\.0\.0\.0):${HYPHANET_FPROXY_PORT}"; then
                break
            fi
            sleep 2
            waited=$((waited + 2))
        done
        
        if netstat -tuln | grep -q "127.0.0.1:${HYPHANET_FPROXY_PORT}"; then
             echo "Hyphanet detected listening on 127.0.0.1:${HYPHANET_FPROXY_PORT}, starting SOCAT proxy..."

             
             echo "Starting socat to redirect 0.0.0.0:${SOCAT_LISTEN_PORT} -> 127.0.0.1:${HYPHANET_FPROXY_PORT}"
             socat TCP-LISTEN:${SOCAT_LISTEN_PORT},fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:${HYPHANET_FPROXY_PORT} &
             SOCAT_PID=$!
             echo "Proxy SOCAT IPv4 started with PID: $SOCAT_PID"
             
             if netstat -tuln | grep -q "::1:${HYPHANET_FPROXY_PORT}"; then
                 echo "Hyphanet detected listening on ::1:${HYPHANET_FPROXY_PORT}, starting SOCAT IPv6 proxy..."                 
                 echo "Starting socat to redirect [::]:${SOCAT_LISTEN_PORT} -> [::1]:${HYPHANET_FPROXY_PORT}"
                 socat TCP-LISTEN:${SOCAT_LISTEN_PORT},fork,reuseaddr,bind=:: TCP:[::1]:${HYPHANET_FPROXY_PORT} &
                 SOCAT_IPV6_PID=$!
                 echo "Proxy SOCAT IPv6 started with PID: $SOCAT_IPV6_PID"
             else
                 echo "Hyphanet not detected listening on ::1:${HYPHANET_FPROXY_PORT}, skipping IPv6 SOCAT proxy."                 
             fi
        
        elif netstat -tuln | grep -q "0.0.0.0:${HYPHANET_FPROXY_PORT}"; then
             echo "Hyphanet detected listening on 0.0.0.0:${HYPHANET_FPROXY_PORT} (but not 127.0.0.1), starting SOCAT proxy..."
             
             echo "Starting socat to redirect 0.0.0.0:${SOCAT_LISTEN_PORT} -> 0.0.0.0:${HYPHANET_FPROXY_PORT}"
             socat TCP-LISTEN:${SOCAT_LISTEN_PORT},fork,reuseaddr,bind=0.0.0.0 TCP:0.0.0.0:${HYPHANET_FPROXY_PORT} &
             SOCAT_PID=$!
             echo "Proxy SOCAT IPv4 started with PID: $SOCAT_PID"
             
             if netstat -tuln | grep -q "\[::\]:${HYPHANET_FPROXY_PORT}"; then 
                 echo "Hyphanet detected listening on [::]:${HYPHANET_FPROXY_PORT} (but not ::1), starting SOCAT IPv6 proxy..."
                 echo "Starting socat to redirect [::]:${SOCAT_LISTEN_PORT} -> [::]:${HYPHANET_FPROXY_PORT}"
                 socat TCP-LISTEN:${SOCAT_LISTEN_PORT},fork,reuseaddr,bind=:: TCP:[::]:${HYPHANET_FPROXY_PORT} &
                 SOCAT_IPV6_PID=$!
                 echo "Proxy SOCAT IPv6 started with PID: $SOCAT_IPV6_PID"
             else
                 echo "Hyphanet not detected listening on [::]:${HYPHANET_FPROXY_PORT}, skipping IPv6 SOCAT proxy."
             fi

        else
             echo "-------------------------------------------------------------"
             echo "ERROR: Hyphanet wasn't detected listening on port ${HYPHANET_FPROXY_PORT} within ${STARTUP_TIMEOUT} seconds."
             echo "Check current ports in usage:"
             netstat -tuln
             echo "Cannot start SOCAT proxy."
             echo "-------------------------------------------------------------"             
        fi


        echo "Tailing log file ($WRAPPER_LOG_PATH) to keep container running..."
        if [ ! -f "$WRAPPER_LOG_PATH" ]; then
            echo "WARN: Log file $WRAPPER_LOG_PATH not found. Creating empty file."
            touch "$WRAPPER_LOG_PATH"
        fi         
        sleep 5
        tail -f "$WRAPPER_LOG_PATH"
    else
        echo "-------------------------------------------------------------"
        echo "ERROR: Could not find a valid and executable start script!"
        echo "Searched paths:"
        printf " - %s\n" "${potential_scripts[@]}"
        echo "Final content of ${HYPHANET_HOME} (at runtime):"
        ls -lRa "${HYPHANET_HOME}" || echo "WARN: Could not list ${HYPHANET_HOME}"
        echo "-------------------------------------------------------------"
        exit 1
    fi    
else    
    exec "$@"
fi