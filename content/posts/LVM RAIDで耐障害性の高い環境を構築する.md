---
title: "LVM RAIDで耐障害性の高い環境を構築する"
date: 2023-09-21T12:32:21+09:00
draft: false
---

マシンを長期間連続で稼働させていると、ディスクが壊れてデータが失われる可能性があります。ストレージの冗長性を確保する方法として、LinuxのLVMを用いたソフトウェアRAIDが手軽そうだったので手元の仮想環境で試してみました。

## テスト環境

- VirtualBox 7.0.10
- Windows 11 Home 22H2 (ホストOS)
- Debian 12 (ゲストOS)

## 目標とする環境

- ディスクが1つ壊れてもシステムが稼働し続けるようにしたい
- ディスク故障後や交換後も正常にブートできるようにしたい

これらを実現すべく、ブートに必要なデータはブート専用のディスクに配置し、I/Oの多いOS本体のデータはRAID1で別のディスクにもミラーリングする構成にしたいと思います。なおブート用ディスクはブート時にしか使用しないため故障しない前提で考えます。

```txt
sda
└─sda1      LVM
sdb
└─sdb1      LVM
sdc
├─sdc1      /boot/efi
└─sdc2      /boot
```

## セットアップ

### VMのセットアップ

VirtualBoxでDebianのVMを作成し、ストレージに10GBのディスクを割り当てます。EFIを使用したいので `Hardware` 画面にて `Enable EFI (special OSes only)` にチェックを入れておきます。またLVMを使用するので、Debianのインストール画面の `Partition disks` では `use entire disk and set up LVM` を選択します。

VirtualBoxのVMの `設定` -> `ストレージ` タブで、ミラー用に10GBのディスクとブート用に5GBのディスクをそれぞれ作成して割り当てます。

起動後の構成はこんな感じです。

```txt
root@debian:~# lsblk
NAME                  MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                     8:0    0   10G  0 disk
├─sda1                  8:1    0  512M  0 part /boot/efi
├─sda2                  8:2    0  488M  0 part /boot
└─sda3                  8:3    0    9G  0 part
  ├─debian--vg-root   254:0    0  8.1G  0 lvm  /
  └─debian--vg-swap_1 254:1    0  980M  0 lvm  [SWAP]
sdb                     8:16   0   10G  0 disk
sdc                     8:32   0    5G  0 disk
sr0                    11:0    1 1024M  0 rom
```

### スワップパーティションの削除

スワップパーティションは使わない予定なので削除します。fstabのマウント設定もコメントアウトしておきます。

```txt
root@debian:~# swapoff -a

root@debian:~# lvremove debian-vg/swap_1
Do you really want to remove active logical volume debian-vg/swap_1? [y/n]: y
  Logical volume "swap_1" successfully removed.

root@debian:~# vi /etc/fstab
#/dev/mapper/debian--vg-swap_1 none            swap    sw              0       0
```

### ミラー用ディスクの設定

LVM用のパーティションを作成します。

```txt
root@debian:~# fdisk /dev/sdb

Welcome to fdisk (util-linux 2.38.1).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.

Device does not contain a recognized partition table.
Created a new DOS (MBR) disklabel with disk identifier 0xe2fbe83b.

Command (m for help): n
Partition type
   p   primary (0 primary, 0 extended, 4 free)
   e   extended (container for logical partitions)
Select (default p):
Partition number (1-4, default 1):
First sector (2048-20971519, default 2048):
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-20971519, default 20971519):

Created a new partition 1 of type 'Linux' and of size 10 GiB.

Command (m for help): t
Selected partition 1
Hex code or alias (type L to list all): 8e
Changed type of partition 'Linux' to 'Linux LVM'.

Command (m for help): p
Disk /dev/sdb: 10 GiB, 10737418240 bytes, 20971520 sectors
Disk model: VBOX HARDDISK
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0xe2fbe83b

Device     Boot Start      End  Sectors Size Id Type
/dev/sdb1        2048 20971519 20969472  10G 8e Linux LVM

Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.

```

PVを作成し、VGに追加します。

```txt
root@debian:~# pvcreate /dev/sdb1
  Physical volume "/dev/sdb1" successfully created.

root@debian:~# vgextend debian-vg /dev/sdb1
  Volume group "debian-vg" successfully extended

root@debian:~# pvs
  PV         VG        Fmt  Attr PSize   PFree
  /dev/sda3  debian-vg lvm2 a--   <9.02g      0
  /dev/sdb1  debian-vg lvm2 a--  <10.00g <10.00g
```

### ブート用ディスクの設定

EFIシステムパーティションを作りたいのでディスクのパーティションテーブルをGPT形式にします。

```txt
root@debian:~# gdisk /dev/sdc
GPT fdisk (gdisk) version 1.0.9

Partition table scan:
  MBR: not present
  BSD: not present
  APM: not present
  GPT: not present

Creating new GPT entries in memory.

Command (? for help): w

Final checks complete. About to write GPT data. THIS WILL OVERWRITE EXISTING
PARTITIONS!!

Do you want to proceed? (Y/N): y
OK; writing new GUID partition table (GPT) to /dev/sdc.
The operation has completed successfully.
```

`/boot/efi` と `/boot` 用にそれぞれパーティションを作成します。

```txt
root@debian:~# fdisk /dev/sdc

Welcome to fdisk (util-linux 2.38.1).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.


Command (m for help): n
Partition number (1-128, default 1):
First sector (34-10485726, default 2048):
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-10485726, default 10483711): +200M

Created a new partition 1 of type 'Linux filesystem' and of size 200 MiB.

Command (m for help): t
Selected partition 1
Partition type or alias (type L to list all): 1
Changed type of partition 'Linux filesystem' to 'EFI System'.

Command (m for help): n
Partition number (2-128, default 2):
First sector (411648-10485726, default 411648):
Last sector, +/-sectors or +/-size{K,M,G,T,P} (411648-10485726, default 10483711): +500M

Created a new partition 2 of type 'Linux filesystem' and of size 500 MiB.

Command (m for help): p
Disk /dev/sdc: 5 GiB, 5368709120 bytes, 10485760 sectors
Disk model: VBOX HARDDISK
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 0557C8E1-7528-4658-B2FC-14464F190345

Device      Start     End Sectors  Size Type
/dev/sdc1    2048  411647  409600  200M EFI System
/dev/sdc2  411648 1435647 1024000  500M Linux filesystem

Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.
```

それぞれのパーティションをフォーマットします。

```txt
root@debian:~# mkfs.vfat /dev/sdc1
mkfs.fat 4.2 (2021-01-31)

root@debian:~# mkfs.ext2 /dev/sdc2
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 512000 1k blocks and 128016 inodes
Filesystem UUID: 61901504-35b9-4d88-bf4d-95142719ec91
Superblock backups stored on blocks:
        8193, 24577, 40961, 57345, 73729, 204801, 221185, 401409

Allocating group tables: done
Writing inode tables: done
Writing superblocks and filesystem accounting information: done
```

`/dev/sdc1` にGRUBをインストールします。

```txt
root@debian:~# umount /boot/efi

root@debian:~# mount /dev/sdc1 /boot/efi

root@debian:~# grub-install --efi-directory=/boot/efi
Installing for x86_64-efi platform.
Installation finished. No error reported.

root@debian:~# update-grub
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.1.0-12-amd64
Found initrd image: /boot/initrd.img-6.1.0-12-amd64
Found linux image: /boot/vmlinuz-6.1.0-10-amd64
Found initrd image: /boot/initrd.img-6.1.0-10-amd64
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done
```

`/dev/sdc2` に現在の `/boot` 配下の内容をコピーします。

```txt
root@debian:~# mkdir /mnt/boot

root@debian:~# mount /dev/sdc2 /mnt/boot

root@debian:~# cp -r /boot/* /mnt/boot
```

これでブート用ディスクのセットアップができました。次回からこのディスクでブートできるようにfstabのUUIDを修正します。

```txt
root@debian:~# blkid /dev/sdc1
/dev/sdc1: SEC_TYPE="msdos" UUID="E559-D6C3" BLOCK_SIZE="512" TYPE="vfat" PARTUUID="6a744d6a-90ce-4742-baca-a9f134f14247"

root@debian:~# blkid /dev/sdc2
/dev/sdc2: UUID="61901504-35b9-4d88-bf4d-95142719ec91" BLOCK_SIZE="1024" TYPE="ext2" PARTUUID="ccee7610-5edc-854c-9fef-46870659b11d"

root@debian:~# vi /etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# systemd generates mount units based on this file, see systemd.mount(5).
# Please run 'systemctl daemon-reload' after making changes here.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/mapper/debian--vg-root /               ext4    errors=remount-ro 0       1
# /boot was on /dev/sdc2 during installation
UUID=61901504-35b9-4d88-bf4d-95142719ec91 /boot           ext2    defaults        0       2
# /boot/efi was on /dev/sdc1 during installation
UUID=E559-D6C3  /boot/efi       vfat    umask=0077      0       1
#/dev/mapper/debian--vg-swap_1 none            swap    sw              0       0
/dev/sr0        /media/cdrom0   udf,iso9660 user,noauto     0       0
```

一度VMを再起動してみて、正常に起動するか確認します。

```txt
root@debian:~# reboot
```

### RAIDのメタデータ用の領域を確保

RAID1のボリュームを作成するに当たって、イメージが配置されるPVにはメタデータボリュームが作成されるため、その分の空き領域を確保しておく必要があります。今回は `/dev/sda3` の使用率が100%なので、LVを縮小して空き領域を作ります。

```txt
root@debian:~# pvs
  PV         VG        Fmt  Attr PSize   PFree
  /dev/sda3  debian-vg lvm2 a--  <9.00g    0

# 1エクステント分縮小
root@debian:~# lvreduce --resizefs --extents -1 debian-vg/root
resize2fs 1.47.0 (5-Feb-2023)
Filesystem at /dev/mapper/debian--vg-root is mounted on /; on-line resizing required
old_desc_blocks = 2, new_desc_blocks = 2
The filesystem on /dev/mapper/debian--vg-root is now 2619392 (4k) blocks long.

  Size of logical volume debian-vg/root changed from <9.00 GiB (2304 extents) to 8.99 GiB (2303 extents).
  Logical volume debian-vg/root successfully resized.

root@debian:~# pvs
  PV         VG        Fmt  Attr PSize   PFree
  /dev/sda3  debian-vg lvm2 a--  <9.00g 4.00m
```

### RAID1でミラーリング

`-m1` でミラーの数を1に指定してRAID1ボリュームを作成します。

```txt
root@debian:~# lvconvert --type raid1 -m1 debian-vg/root
Are you sure you want to convert linear LV debian-vg/root to raid1 with 2 images enhancing resilience? [y/n]: y
  Logical volume debian-vg/root successfully converted.

root@debian:~# lvs -a -o name,copy_percent,devices debian-vg
  LV              Cpy%Sync Devices
  root            38.19    root_rimage_0(0),root_rimage_1(0)
  [root_rimage_0]          /dev/sda3(0)
  [root_rimage_1]          /dev/sdb1(1)
  [root_rmeta_0]           /dev/sda3(2303)
  [root_rmeta_1]           /dev/sdb1(0)
```

これで目標としていた構成の完成です。

```txt
root@debian:~# lsblk
NAME                         MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                            8:0    0   10G  0 disk
├─sda1                         8:1    0  512M  0 part
├─sda2                         8:2    0  488M  0 part
└─sda3                         8:3    0    9G  0 part
  ├─debian--vg-root_rmeta_0  254:1    0    4M  0 lvm
  │ └─debian--vg-root        254:0    0    9G  0 lvm  /
  └─debian--vg-root_rimage_0 254:2    0    9G  0 lvm
    └─debian--vg-root        254:0    0    9G  0 lvm  /
sdb                            8:16   0   10G  0 disk
└─sdb1                         8:17   0   10G  0 part
  ├─debian--vg-root_rmeta_1  254:3    0    4M  0 lvm
  │ └─debian--vg-root        254:0    0    9G  0 lvm  /
  └─debian--vg-root_rimage_1 254:4    0    9G  0 lvm
    └─debian--vg-root        254:0    0    9G  0 lvm  /
sdc                            8:32   0    5G  0 disk
├─sdc1                         8:33   0  200M  0 part /boot/efi
└─sdc2                         8:34   0  500M  0 part /boot
sr0                           11:0    1 1024M  0 rom
```

## テスト

実際にディスクを取り外し・交換したいケースを想定して色々いじってみます。

### ディスクが故障しそうなとき

完全には壊れていないが、S.M.A.R.T.などの出力から故障が近いと考えられる場合です。RAID1ボリュームをリニアボリュームに変換してもう片方のPVに残し、対象のPVを無効化します。ここでは `/dev/sda` を交換したい対象とします。

```txt
root@debian:~# lvconvert -m0 debian-vg/root /dev/sda3
Are you sure you want to convert raid1 LV debian-vg/root to type linear losing all resilience? [y/n]: y
  Logical volume debian-vg/root successfully converted.

root@debian:~# lvs -a -o name,copy_percent,devices debian-vg
  LV   Cpy%Sync Devices
  root          /dev/sdb1(1)

root@debian:~# vgreduce debian-vg /dev/sda3
  Removed "/dev/sda3" from volume group "debian-vg"

root@debian:~# pvremove /dev/sda3
  Labels on physical volume "/dev/sda3" successfully wiped.
```

これでディスクを取り外してもシステムは正常に動作します。

また、ミラーに使用していない別のPVがある場合はすぐに置き換えることも可能です。

```txt
root@debian:~# lvconvert --replace /dev/sda1 debian-vg/root /dev/sdd1

root@debian:~# lvs -a -o name,copy_percent,devices debian-vg
LV              Cpy%Sync Devices
  root            48.54    root_rimage_0(0),root_rimage_1(0)
  [root_rimage_0]          /dev/sdb1(1)
  [root_rimage_1]          /dev/sdd1(1)
  [root_rmeta_0]           /dev/sdb1(0)
  [root_rmeta_1]           /dev/sdd1(0)
```

### ディスクが故障したとき

完全に壊れてディスクとして機能しなくなった場合です。実際にシステム稼働中にディスクを取り外してテストしてみます。VirtualBoxでVMが電源オフの状態で、VMの `設定` -> `ストレージ` タブにてディスクを選択すると `ホットプラグ可能` という欄があるのでこれにチェックをいれます。

故障する想定のディスク (`/dev/sda`) をホットプラグ可能にして、システム稼働中にこのディスクを取り外してみます。

```txt
root@debian:~# lvs -a -o name,copy_percent,devices debian-vg
  WARNING: Couldn't find device with uuid bXBHE0-PzXh-gv9Z-Rdlm-K3pQ-bdW0-vcQujE.
  WARNING: VG debian-vg is missing PV bXBHE0-PzXh-gv9Z-Rdlm-K3pQ-bdW0-vcQujE (last written to /dev/sda3).
  WARNING: Couldn't find all devices for LV debian-vg/root_rmeta_1 while checking used and assumed devices.
  WARNING: Couldn't find all devices for LV debian-vg/root_rimage_1 while checking used and assumed devices.
  LV              Cpy%Sync Devices
  root            0.00     root_rimage_0(0),root_rimage_1(0)
  [root_rimage_0]          /dev/sdb1(1)
  [root_rimage_1]          [unknown](1)
  [root_rmeta_0]           /dev/sdb1(0)
  [root_rmeta_1]           [unknown](0)
```

PVが認識不可能となってしまったのでVGから取り除きます。

```txt
root@debian:~# vgreduce --removemissing debian-vg --force
  WARNING: Couldn't find device with uuid bXBHE0-PzXh-gv9Z-Rdlm-K3pQ-bdW0-vcQujE.
  WARNING: VG debian-vg is missing PV bXBHE0-PzXh-gv9Z-Rdlm-K3pQ-bdW0-vcQujE (last written to /dev/sda3).
  WARNING: Couldn't find device with uuid bXBHE0-PzXh-gv9Z-Rdlm-K3pQ-bdW0-vcQujE.
  WARNING: Couldn't find device with uuid bXBHE0-PzXh-gv9Z-Rdlm-K3pQ-bdW0-vcQujE.
  Wrote out consistent volume group debian-vg.

root@debian:~# lvs -a -o name,copy_percent,devices debian-vg
  LV              Cpy%Sync Devices
  root            100.00   root_rimage_0(0),root_rimage_1(0)
  [root_rimage_0]          /dev/sdb1(1)
  [root_rimage_1]
  [root_rmeta_0]           /dev/sdb1(0)
  [root_rmeta_1]
```

この後、前のケースと同様にリニアボリュームに変換することもできますが、新しいディスクに交換してRAID1の状態を復旧させることも可能です。

```txt
# パーティションを作成
root@debian:~# fdisk /dev/sda

root@debian:~# pvcreate /dev/sda1
  Physical volume "/dev/sda1" successfully created.

root@debian:~# vgextend debian-vg /dev/sda1
  Volume group "debian-vg" successfully extended

root@debian:~# lvconvert --repair debian-vg/root
Attempt to replace failed RAID images (requires full device resync)? [y/n]: y
  Faulty devices in debian-vg/root successfully replaced.

root@debian:~# lvs -a -o name,copy_percent,devices debian-vg
  LV              Cpy%Sync Devices
  root            19.10    root_rimage_0(0),root_rimage_1(0)
  [root_rimage_0]          /dev/sdb1(1)
  [root_rimage_1]          /dev/sda1(1)
  [root_rmeta_0]           /dev/sdb1(0)
  [root_rmeta_1]           /dev/sda1(0)
```

## まとめ

ディスクの故障に強く、復旧も簡単な環境がLVMだけで作れてしまうのは凄いですね。今回は仮想環境での実験となりましたが、近いうちに自宅のマシンにもセットアップしていきたいと思います。

## 参考

- [第6章 RAID 論理ボリュームの設定 Red Hat Enterprise Linux 9 | Red Hat Customer Portal](https://access.redhat.com/documentation/ja-jp/red_hat_enterprise_linux/9/html/configuring_and_managing_logical_volumes/configuring-raid-logical-volumes_configuring-and-managing-logical-volumes)
- [Create Mirrored Logical Volume in Linux [Step-by-Step] | GoLinuxCloud](https://www.golinuxcloud.com/create-mirrored-logical-volume-in-linux/)

