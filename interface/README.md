# MoonGen Interface
This interface is supposed to be an easier to understand, use and maintain alternative to the Lua-scripts needed to run MoonGen. Instead these scripts are replaced by configuration Files containing flows in a BibTeX-like syntax.

## How to use
`./mginterface start load-latency:0:1:rate=1000,timeLimit=10m`

Similar to `examples/l3-load-latency.lua` with rate set to 1000 mbit/s but stops automatically after 10 minutes. Will send on port `0` and receive on port `1`. Packet content is defined in `flows/examples.lua`.

For quick adjustments the packet content can also be changed from the command-line using:

`./mginterface start load-latency:0:1:rate=1000,timeLimit=10m:udpSrc=4321`

More info on options like `rate=1000`, `timeLimit=10m` and similar options can be found
using `./mginterface help options`.

### More Examples
- `./mginterface start udp-simple:0:1:rate=1000mbit/s,ratePattern=poisson`
- `./mginterface start qos-foreground:0:1 qos-background:0:1`
- `./mginterface start udp-load:0:1:rate=1gp/s,mode=all,timestamp`
- `./mginterface start "udp-load:0::rate=1000:udpDst=range(100,200)"`
- `./mginterface start "load-latency:0,1:0,1:rate=1000:ip4Dst=ip'192.168.0.1'"`

## Commands

### Start
`mginterface start <flow> [<flow>] ...`  
 `<flow>` -> `<name>:[<tx-ports>]:[<rx-ports>]:[<options>]:[<overwrites>]`

Start all the flows supplied as arguments. All arguments besides the name can be  `,`-separated lists. Trailing `:` can be omitted.

### List
`mginterface list [<entry>] ...`

Show a tabular view of all flows available in the directories or files passed (default is `flows`). Useful to remember the name of a particular flow or find the file a flow resides in.

### Debug
`mginterface debug <flow>`

Shows hex-dumps of the packets resulting from a certain flow without sending anything. Can be used to test the results of more complicated flow configurations. Will also adapt to some options and all overwrites passed.

See `start` command for syntax of `<flow>`.

## Help
All commands can be invoked with a `-h` flag to show info on available options. Additionally calling `mginterface help` will list all available help texts that can be read using `mginterface help <topic>`.

## Configuration
First, all configuration files in a directory (excluding subdirectories) are scanned. The flows can then be started by name. The following Flow is meant as a demonstration of capabilities. Look in `MoonGen/flows` for useful base flows or use `mginterface help configuration` for more information.

```lua
Flow{"example", Packet.Udp{
    ethSrc = txQueue(),
    ethDst = arp(ip"10.1.0.1"),
    ip4Src = list{
      ip"10.1.0.0", ip"10.1.1.1",
      ip"11.0.1.0", ip"11.1.0.1"
    },
    ip4Dst = ip"10.1.0.1",
    udpSrc = range(1000, 2000),
    udpDst = 1234
  },
  mode = "random",
  rate = 1234,
  timestamp = true
}
```
