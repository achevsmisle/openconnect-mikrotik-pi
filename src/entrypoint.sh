#!/bin/sh
# set error handling
set -o errexit
set -o pipefail

# defaults
: "${OC_PIDFILE:=/var/run/openconnect.pid}"
: "${OC_IFACE_NAME:=oc-tun}"
: "${OC_RECONNECT_TIMEOUT:=30}"
: "${OC_PROTOCOL:=anyconnect}"
: "${OC_SNI:=$(printf '%s' "$OC_SERVER" | sed 's|^.*://||; s|[:/?#].*||')}"
: "${OC_RUN_USER:=1004}" # we wont be root
: "${OC_DEBUG:=0}" # keep calm by default
: "${OC_PFS:=0}"
: "${OC_NO_PASSWD:=0}"
: "${OC_NO_DTLS:=0}"
: "${OC_MTU:=1436}"
: "${OC_DEFAULT_ROUTE:=1}"
: "${OC_CONTAINER_CUSTOM_ROUTE_IPV4:=0}"
: "${OC_CONTAINER_CUSTOM_ROUTE_IPV6:=0}"
: "${OC_CONTAINER_IFACE_NAME:=auto}"
: "${OC_DISABLE_IPV6:=0}"
# apply container kernel opts
sysctl -p >/dev/null

# Params check & formatting
check_params() {
    [ -n "${OC_SERVER}" ] || { echo 'OC_SERVER env variable is empty or not set!'; return 1; }
    [ "${OC_DEBUG}" = "0" ] && LOGLEVEL='--quiet' || LOGLEVEL='--verbose --timestamp'
    [ "${OC_PFS}" = "1" ] && OC_PFS='--pfs' || OC_PFS=""
    [ -n "${OC_USER}" ] && OC_USER="--user=${OC_USER}" || OC_USER=""
    [ -n "${OC_CERT}" ] && OC_CERT="--certificate=/certs/${OC_CERT}" || OC_CERT=""
    [ -n "${OC_KEY}" ] && OC_KEY="--sslkey=/certs/${OC_KEY}" || OC_KEY=""
    [ -n "${OC_MCERT}" ] && OC_MCERT="--mca-certificate=/certs/${OC_MCERT}" || OC_MCERT=""
    [ -n "${OC_MKEY}" ] && OC_MKEY="--mca-key=/certs/${OC_MKEY}" || OC_MKEY=""
    [ -n "${OC_AUTHGROUP}" ] && OC_AUTHGROUP="--authgroup=${OC_AUTHGROUP}" || OC_AUTHGROUP=""
    [ -n "${OC_USERGROUP}" ] && OC_USERGROUP="--usergroup=${OC_USERGROUP}" || OC_USERGROUP=""
    [ -n "${OC_SERVERCERT_FINGERPRINT}" ] && OC_SERVERCERT_FINGERPRINT="--servercert=${OC_SERVERCERT_FINGERPRINT}" || OC_SERVERCERT_FINGERPRINT=""
    [ "${OC_NO_SYSTEM_TRUST}" = "1" ] && OC_NO_SYSTEM_TRUST='--no-system-trust' || OC_NO_SYSTEM_TRUST=""
    [ -n "${OC_CAFILE}" ] && OC_CAFILE="--cafile=${OC_CAFILE}" || OC_CAFILE=""
    [ "${OC_NO_DTLS}" = "1" ] && OC_NO_DTLS='--no-dtls' || OC_NO_DTLS=""
    [ -n "${OC_MTU}" ] && OC_MTU="--mtu=${OC_MTU}"
    [ -n "${OC_BASE_MTU}" ] && OC_BASE_MTU="--mtu=${OC_BASE_MTU}"
    [ "${OC_DISABLE_IPV6}" = "1" ] && OC_DISABLE_IPV6_OPT='--disable-ipv6' || OC_DISABLE_IPV6_OPT=""
    [ -n "${OC_CAMOUFLAGE_SECRET}" ] && OC_CAMOUFLAGE_SECRET="/?${OC_CAMOUFLAGE_SECRET}" || OC_CAMOUFLAGE_SECRET=""
    if [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV4}" != "0" ] || [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV6}" != "0" ]; then
        if [ "${OC_CONTAINER_IFACE_NAME}" = "auto" ]; then
            echo "[Openconnect container notice] OC_CONTAINER_IFACE_NAME was empty, fallback to 'auto'"
        fi
    fi
}

# make params
conc_params() {
    COMMON_OPTS="\
        --background \
        --pid-file=${OC_PIDFILE} \
        --setuid=${OC_RUN_USER} \
        --non-inter \
        --cert-expire-warning=30 \
        --no-external-auth \
        -i ${OC_IFACE_NAME} \
        --reconnect-timeout=${OC_RECONNECT_TIMEOUT} \
        --sni=${OC_SNI} \
        ${OC_USER} \
        ${OC_CERT} \
        ${OC_KEY} \
        ${OC_MCERT} \
        ${OC_MKEY} \
        ${OC_AUTHGROUP} \
        ${OC_USERGROUP} \
        ${OC_SERVERCERT_FINGERPRINT} \
        ${OC_NO_SYSTEM_TRUST} \
        ${OC_CAFILE} \
        ${OC_NO_DTLS} \
        ${OC_DISABLE_IPV6_OPT} \
        ${OC_MTU} \
        ${OC_BASE_MTU} \
        ${LOGLEVEL} \
        ${OC_PFS} \
        ${OC_SERVER}${OC_CAMOUFLAGE_SECRET}"
}

# iptables setup 
iptables_setup() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    ip6tables -P INPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    ip6tables -P OUTPUT ACCEPT
    echo "iptables all ACCEPT is set"
}

# IPv6 forwarding setup
ipv6_forwarding_switch() {
    if [ "${OC_DISABLE_IPV6}" = "1" ]; then
        sysctl -w net.ipv6.conf.default.forwarding=0 net.ipv6.conf.all.forwarding=0
    else
        :
    fi
}

start_openconnect() {
    rm -f "${OC_PIDFILE}"
    if [ -n "${OC_PASSWORD}" ] && [ "${OC_NO_PASSWD}" != "1" ]; then
        # read password from stdin
        env -u OC_PASSWORD openconnect --passwd-on-stdin ${COMMON_OPTS} <<EOF
${OC_PASSWORD}
EOF
    else
        # No password check
        env -u OC_PASSWORD openconnect --no-passwd ${COMMON_OPTS}
    fi
}

load_openconnect_pid() {
    pid_timeout="${PIDFILE_TIMEOUT:-30}"

    while [ "${pid_timeout}" -gt 0 ]; do
        if [ -s "${OC_PIDFILE}" ]; then
            OC_PID="$(cat "${OC_PIDFILE}")"
            if kill -0 "${OC_PID}" 2>/dev/null; then
                echo "OpenConnect PID ${OC_PID} is running"
                return 0
            fi
        fi
        sleep 1
        pid_timeout=$((pid_timeout - 1))
    done

    echo "OpenConnect PID file ${OC_PIDFILE} was not created or process is not running"
    return 1
}

wait_for_ips() {
    getip_timeout="${OC_GET_IP_TIMEOUT:-5}"
    tun_ipv4=""
    tun_ipv6=""

    while [ "${getip_timeout}" -gt 0 ]; do
        if grep -q '^1$' "/sys/class/net/${OC_IFACE_NAME}/carrier" 2>/dev/null; then
            tun_ipv4=$(ip -4 addr sh "${OC_IFACE_NAME}" 2>/dev/null | awk -F"[ /]+" '/scope (global|link)/{print $3; exit}' | tr -d '[:space:]') || true
            if [ "${OC_DISABLE_IPV6}" != "1" ]; then
                tun_ipv6=$(ip -6 addr sh "${OC_IFACE_NAME}" 2>/dev/null | awk -F"[ /]+" '/scope (global|link)/{print $3; exit}' | tr -d '[:space:]') || true
            fi
        fi

        if [ "${OC_DISABLE_IPV6}" = "1" ] && [ -n "${tun_ipv4}" ]; then
            echo "IPv4 acquired"
            return 0
        elif [ "${OC_DISABLE_IPV6}" != "1" ] && [ -n "${tun_ipv4}" ] && [ -n "${tun_ipv6}" ]; then
            printf "IPv4 acquired\nIPv6 acquired\n"
            return 0
        fi

        sleep 1
        getip_timeout=$((getip_timeout - 1))
    done

    if [ "${OC_DISABLE_IPV6}" = "1" ] && [ -z "${tun_ipv4}" ]; then
        echo "No IPv4 address acquired for ${OC_GET_IP_TIMEOUT:-5}s"
        return 1
    elif [ "${OC_DISABLE_IPV6}" != "1" ] && [ -z "${tun_ipv4}" ] && [ -z "${tun_ipv6}" ]; then
        echo "No IP addresses acquired for ${OC_GET_IP_TIMEOUT:-5}s"
        return 1
    fi

    [ -n "${tun_ipv4}" ] && echo "IPv4 acquired"
    [ -n "${tun_ipv6}" ] && echo "IPv6 acquired"
    return 0
}

add_custom_routes() {
    if [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV4}" = "0" ] && [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV6}" = "0" ]; then
        return 0
    fi
    if [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV4}" != "0" ] && [ -z "${OC_CONTAINER_CUSTOM_ROUTE_IPV4_NEXTHOP}" ]; then
        printf "Next hop for IPv4 routes is not set in OC_CONTAINER_CUSTOM_ROUTE_IPV4_NEXTHOP.\nNo custom IPv4 routes will be added.\n"
        return 0
    fi
    if [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV6}" != "0" ] && [ -z "${OC_CONTAINER_CUSTOM_ROUTE_IPV6_NEXTHOP}" ]; then
        printf "Next hop for IPv6 routes is not set in OC_CONTAINER_CUSTOM_ROUTE_IPV6_NEXTHOP.\nNo custom IPv6 routes will be added.\n"
        return 0
    fi
    if [ "${OC_CONTAINER_IFACE_NAME}" = "auto" ]; then
        _ifaces=$(ip -br link | awk '{print $1}' | grep -Ev "lo|${OC_IFACE_NAME}") || true
        _iface_count=$(echo "$_ifaces" | grep -c '^')
        if [ "$_iface_count" -gt 1 ]; then
            printf "Auto interface search found > 1 local interfaces.\nNo custom routes will be added.\n"
            return 0
        elif [ "$_iface_count" -eq 0 ]; then
            printf "Auto interface search found no valid local interfaces.\nNo custom routes will be added.\n"
            return 0
        fi
        local_iface="${_ifaces%%@*}"
    else
        local_iface=$(ip -br link | grep -w "${OC_CONTAINER_IFACE_NAME}" | awk '{print $1}') || true
        if [ -z "${local_iface}" ]; then
            printf "Interface specified in OC_CONTAINER_IFACE_NAME variable does not exist.\nNo custom routes will be added.\n"
            return 0
        else
            local_iface="${local_iface%%@*}"
        fi
    fi

    if [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV4}" != "0" ]; then
        _ipv4_added=""
        for prefix in $OC_CONTAINER_CUSTOM_ROUTE_IPV4; do
            if ip -4 route add "${prefix}" via "${OC_CONTAINER_CUSTOM_ROUTE_IPV4_NEXTHOP}" dev "${local_iface}"; then
                _ipv4_added="${_ipv4_added} ${prefix}"
            else
                printf "Failed to add IPv4 route %s via %s dev %s.\n" "${prefix}" "${OC_CONTAINER_CUSTOM_ROUTE_IPV4_NEXTHOP}" "${local_iface}"
            fi
        done
        printf "Added IPv4 routes for dev %s:\n" "${local_iface}"
        printf '%s\n' "$_ipv4_added"
    fi

    if [ "${OC_CONTAINER_CUSTOM_ROUTE_IPV6}" != "0" ]; then
        _ipv6_added=""
        for prefix in $OC_CONTAINER_CUSTOM_ROUTE_IPV6; do
            if ip -6 route add "${prefix}" via "${OC_CONTAINER_CUSTOM_ROUTE_IPV6_NEXTHOP}" dev "${local_iface}"; then
                _ipv6_added="${_ipv6_added} ${prefix}"
            else
                printf "Failed to add IPv6 route %s via %s dev %s.\n" "${prefix}" "${OC_CONTAINER_CUSTOM_ROUTE_IPV6_NEXTHOP}" "${local_iface}"
            fi
        done
        printf "Added IPv6 routes for dev %s:\n" "${local_iface}"
        printf '%s\n' "$_ipv6_added"
    fi
    return 0
}

add_default_routes () {
    if [ "${OC_DEFAULT_ROUTE}" = "1" ]; then
        if [ -n "${tun_ipv4}" ]; then
            ip -4 route replace default dev "${OC_IFACE_NAME}" scope global || printf "Failed to replace IPv4 default route via %s.\n" "${OC_IFACE_NAME}"
        fi
        if [ -n "${tun_ipv6}" ]; then
            v6_raw=$(ip -6 -br route show dev "${OC_IFACE_NAME}" | awk '!/^fe80/ && /\// && !/\/128/ {print $1; exit}')
            v6_nomask="${v6_raw%%/*}"
            
            case "$v6_nomask" in
                *::)
                    # "fd00:1::" => "fd00:1::1"
                    v6_gateway="${v6_nomask%}1"
                    ;;
                *::*)
                    # "::" inside (fd00:1::100) => cut last octet after "::"
                    v6_gateway="${v6_nomask%:*}:1"
                    ;;
                *)
                    # full addr (/64)
                    v6_prefix=$(echo "${v6_nomask}" | cut -d: -f1-4)
                    v6_gateway="${v6_prefix}::1"
                    ;;
            esac
            ip -6 route delete default || true
            ip -6 route add default via "${v6_gateway}" dev "${OC_IFACE_NAME}" metric 100 || printf "Failed to add IPv6 default route via %s.\n" "${OC_IFACE_NAME}"
            return 0
        fi
    fi
    return 0
}

post_tunnel_setup() {
    # Operations that require an established tunnel live here.
    wait_for_ips
    add_default_routes
    add_custom_routes
    return 0
}

cleanup() {
    trap - EXIT INT TERM HUP QUIT

    if [ -s "${OC_PIDFILE}" ]; then
        OC_PID="$(cat "${OC_PIDFILE}")"
        if kill -0 "${OC_PID}" 2>/dev/null; then
            echo "Stopping OpenConnect PID ${OC_PID}"
            kill "${OC_PID}" 2>/dev/null || true

            stop_timeout="${OC_STOP_TIMEOUT:-10}"
            while [ "${stop_timeout}" -gt 0 ] && kill -0 "${OC_PID}" 2>/dev/null; do
                sleep 1
                stop_timeout=$((stop_timeout - 1))
            done

            if kill -0 "${OC_PID}" 2>/dev/null; then
                echo "OpenConnect PID ${OC_PID} did not stop gracefully, killing"
                kill -KILL "${OC_PID}" 2>/dev/null || true
            fi
        fi
    fi

    rm -f "${OC_PIDFILE}"
}

shutdown() {
    cleanup
    exit 0
}

wait_forever() {
    while kill -0 "${OC_PID}" 2>/dev/null; do
        sleep 1
    done

    echo "OpenConnect PID ${OC_PID} exited"
    return 1
}

# main logic
if [ "${1:-}" = "--supervise-openconnect" ]; then
    trap cleanup EXIT
    trap shutdown INT TERM HUP QUIT
    load_openconnect_pid
    post_tunnel_setup
    wait_forever || exit $?
    exit 0
fi

check_params
conc_params
iptables_setup || echo "iptables rules setup error!"
ipv6_forwarding_switch
trap cleanup EXIT
trap shutdown INT TERM HUP QUIT
start_openconnect
load_openconnect_pid
trap - EXIT INT TERM HUP QUIT
exec env -u OC_PASSWORD /bin/sh "$0" --supervise-openconnect
