#!/bin/bash

OPTIONS=''
MLX5=false
MLX4=false

while :; do
        case $1 in
                -h|--help)
                        echo "Usage: <no option> compile without Mellanox drivers; <-m|--mlx5> compile mlx5; <-n|--mlx4> compile mlx4; <-h|--help> help"
                        exit
                        ;;
                -m|--mlx5)
                        echo "Build with mlx5 driver selected"
                        OPTIONS="$OPTIONS""-DUSE_MLX5=ON "
                        MLX5=true
                        ;;
                -n|--mlx4)
                        echo "Build with mlx4 driver selected"
                        OPTIONS="$OPTIONS""-DUSE_MLX4=ON "
                        MLX4=true
                        ;;
                -?*)
                        printf 'WARN: Unknown option (abort): %s\n' "$1" >&2
                        exit
                        ;;
                *)
                        break
        esac
        shift
done

(
cd $(dirname "${BASH_SOURCE[0]}")
git submodule update --init --recursive


NUM_CPUS=$(cat /proc/cpuinfo  | grep "processor\\s: " | wc -l)

(
cd libmoon/deps/luajit
make -j $NUM_CPUS BUILDMODE=static 'CFLAGS=-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'
make install DESTDIR=$(pwd)
)

(
cd libmoon/deps/dpdk
#build DPDK with the right configuration
make config T=x86_64-native-linuxapp-gcc O=x86_64-native-linuxapp-gcc
if ${MLX5} ; then
        sed -ri 's,(MLX5_PMD=).*,\1y,' x86_64-native-linuxapp-gcc/.config
fi
if ${MLX4} ; then
        sed -ri 's,(MLX4_PMD=).*,\1y,' x86_64-native-linuxapp-gcc/.config
fi
make -j $NUM_CPUS O=x86_64-native-linuxapp-gcc
)

(
cd build
cmake ${OPTIONS}..
make -j $NUM_CPUS
)

echo Trying to bind interfaces, this will fail if you are not root
echo Try "sudo ./bind-interfaces.sh" if this step fails
./bind-interfaces.sh
)

