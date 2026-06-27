# Repository Description for Docker Image with OpenConnect

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker Image](https://img.shields.io/docker/v/achevsmisle/openconnect-mikrotik-pi?label=Docker%20Hub)](https://hub.docker.com/r/achevsmisle/openconnect-mikrotik-pi)
[![Docker Pulls](https://img.shields.io/docker/pulls/achevsmisle/openconnect-mikrotik-pi)](https://hub.docker.com/r/achevsmisle/openconnect-mikrotik-pi)

This Docker image is designed to run `openconnect` on Mikrotik devices, single-board computers (e.g., Raspberry Pi), and includes a build for the `amd64` architecture. The entrypoint script configures a VPN connection using OpenConnect based on environment variables provided at runtime. Below is a table listing all expected environment variables with their descriptions, default values, notes, and whether they are required.

Functionality is tested against `1.6` or `latest` tag.

## Environment Variables Table

| Variable                    | Required | Description                                                    | Default Value   | Values | Notes                                         |
|-----------------------------|----------|----------------------------------------------------------------|-----------------|--------|-----------------------------------------------|
| `OC_USER`                   | it depends=) | Username for the connection                                | Not set         | string | Necessary with password auth                  |
| `OC_NO_PASSWD`              | No       | If you don't use password authentication, set to 1             | `0`             | 0,1    | I strongly advice not to use passwords        |
| `OC_PASSWORD`               | No       | Password for the connection                                    | Not set         | string | Your pass here. Unnecessary if `OC_NO_PASSWD` is set.|
| `OC_KEY`                    | No       | SSL key file name (mounted to `/certs/`)                       | Not set         | string | User SSL private key                          |
| `OC_CERT`                   | No       | Certificate file name (mounted to `/certs/`)                   | Not set         | string | User certificate                              |
| `OC_MCERT`                  | No       | Certificate file name (mounted to `/certs/`) = `--mca-cert=`   | Not set         | string | Second (or machine) certificate               |
| `OC_MKEY`                   | No       | Certificate file name (mounted to `/certs/`) = `--mca-key=`    | Not set         | string | Second (or machine) SSL private key           |
| `OC_AUTHGROUP`              | No       | Authentication group (used as `--authgroup`)                   | Not set         | string | Optional, if required                         |
| `OC_USERGROUP`              | No       | User group (used as `--usergroup`)                             | Not set         | string | Optional, if required                         |
| `OC_SERVER`                 | Yes      | Server address for the connection. Set port if it is not 443   | Not set         | string | `https://your.domain.net[:port]`              |
| `OC_IFACE_NAME`             | No       | Name of the OpenConnect interface                              | `oc-tun`        | string | Change if you want                            |
| `OC_RECONNECT_TIMEOUT`      | No       | After disconnection or Dead Peer Detection, keep trying to reconnect for SECONDS  | `30`  | integer | set the `--reconnect-timeout seconds` option   |
| `OC_PROTOCOL`               | No       | Protocol for OpenConnect                                       | `anyconnect`    | any supported proto | Look for others in `man openconnect`       |
| `OC_SNI`                    | No       | SNI (Server Name Indication) for the connection                | =`${OC_SERVER}` | any hostname| Defaults to the server address           |
| `OC_DEBUG`                  | No       | Debug mode flag (0 - off, 1 - on)                              | `0`             | 0,1    | Enables verbose mode and timestamps in logs   |
| `OC_PFS`                    | No       | Perfect Forward Secrecy flag                                   | `0`             | 0,1    | Enables the `--pfs` option for OpenConnect    |
| `OC_SERVERCERT_FINGERPRINT` | No       | Server certificate fingerprint                                 | Not set         | hash   | Optional, for server certificate verification. Look in openconnect man for `--servercert` option |
| `OC_NO_SYSTEM_TRUST`        | No       | Flag to disable trust in system certificates (0 - off, 1 - on) | Not set         | 0,1    | Enables `--no-system-trust`                   |
| `OC_CAFILE`                 | No       | Server CA absolute file path                                   | Not set         | string | Optional, if a custom CA is used              |
| `OC_NO_DTLS`                | No       | Disable DTLS (Additional UDP secure tunnel)                    | `0`             | 0,1    | Enables `--no-dtls`                           |
| `OC_DISABLE_IPV6`           | No       | Do not advertise IPv6 capability to server.  | `0` | 0,1 | *Also applies `sysctl -w net.ipv6.conf.default.forwarding=0 net.ipv6.conf.all.forwarding=0` |
| `OC_MTU`                    | No       | Set the MTU for your connection                                | `1436`          | integer | sets the `--mtu VALUE` option                |
| `OC_CAMOUFLAGE_SECRET`      | No       | Set the camouflage secret (will be appended to server address as `https://your.domain.net/?your_secret`) | Not set  | string | Any valid value |
| `OC_DEFAULT_ROUTE`          | No       | Set the default IPv4/IPv6 route to tunnel                      | `1`             | 0,1     | Must be enabled on Mikrotik devices. You can disable it on any other platform, where you control the kernel.  |
| `OC_CONTAINER_CUSTOM_ROUTE_IPV4` | No  | Space separated IPv4 subnet list in CIDR notation. Routes to them will be added via dev `OC_CONTAINER_IFACE_NAME`  | `0` | string | Use this if you need.  |
| `OC_CONTAINER_CUSTOM_ROUTE_IPV6` | No  |  Space separated IPv4 subnet list. Routes to them will be added via dev `OC_CONTAINER_IFACE_NAME`  | `0` | string | Use this if you need. |
| `OC_CONTAINER_IFACE_NAME`   | it depends=) | Container network interface name (which leads to your net). It is strongly recommended to set this variable if you use `OC_CONTAINER_CUSTOM_ROUTE_IPV4`, `OC_CONTAINER_CUSTOM_ROUTE_IPV6` or both | `auto` | sting | **Yes, it has some fallback |

> \* I like IPv6, but if you don't need it or don't know what it is, just disable it using the appropriate env variable.

>** If you add custom routes, but don't set this var, there will be simple stupid fallback. It will search for NOT `lo`(loopback) and not `OC_IFACE_NAME` interface.
>* If it finds one => routes will be set via it.
>* If it finds > 1 (or no one) - ~~violators will be shot, survivors will be shot again~~ no routes will be added.
>* Also if you set the wrong name, it will not crash the container. Just...no routes will be added.

## RouterOS

- Container establishes connection with ocserv and shutdown correctly.
- Traffic passes to server through tunnel.
- It just works. Even with NAT66. 

### Warning

> - On mikrotik devices you should set routing manually!
> - For mikrotik devices you should apply the default route to your client (mikrotik) on VPN server, or do it there globally for all clients.
> RouterOS docker  implementation forbids firewall rules addition - you can't masquerade inside the container.
> - Other firewall rules (forwarding) also should be set in RouterOS.

# Last warning

> - `entrypoint.sh` in the container doesn't validate your `string` parameters!
> Be careful when you set them or ~suffer~ happy debugging.