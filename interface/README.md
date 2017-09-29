# MoonGen Interface
This interface is supposed to be an easier to understand, use and maintain alternative to the Lua-scripts needed to run MoonGen. Instead these scripts are replaced by configuration Files containing flows in a BibTeX-like syntax.

First, all configuration files in a directory (excluding subdirectories) are scanned. The flows can then be started by name. The following Flow is meant as a demonstration of capabilities. Look in `MoonGen/flows` for useful base flows.

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

# Command Line
This interface supports 3 commands:

## List
`mginterface list [<directory>]`

Show a tabular view of all flows available in the directory (default is `flows`). Useful to remember the name of a particular flow or find the file a flow resides in.

## Debug
`mginterface debug <flow>`

Shows hex-dumps of the packets resulting from a certain flow without sending anything. Can be used to test the results of more complicated flow configurations.

See below for sytax of `<flow>`.

## Start
`mginterface start <flow> [<flow>] ...`  
 `<flow>` -> `<name>:[<tx-ports>]:[<rx-ports>]:[<options>]:[<overwrites>]`

Start all the flows supplied as arguments. All arguments besides the name can be  `,`-separated lists. Trailing `:` can be omitted.

##### Examples

- `mginterface start "load-latency:4,5:4,5:timeLimit=1m:ip4Dst=ip'192.168.0.1'"`
- `mginterface start udp-simple:1:0`
- `mginterface start udp-load:0:1:mode=all,timestamp`
- `mginterface start "udp-load:1:::udpDst=range(100,200)"`
- `mginterface start qos-foreground:2:3 qos-background:2:3`

## Help
All commands can be invoked with a `-h` flag to show info on available options. Additionally calling `mginterface help` will list all available help texts that can be read using `mginterface help <topic>`.
