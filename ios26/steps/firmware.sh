mkdir -p cloud fw
ipsw img4 im4p extract cloudos/Firmware/all_flash/DeviceTree.vphone600ap.im4p -o cloud/vphone600ap.adt
bash $S/kdec.sh
bash $S/unwrap-fw.sh
