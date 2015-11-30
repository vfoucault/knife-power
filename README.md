# knife plugin to manage PowerVM Hypervisor
This knife module relies on the powervmtools gem.
As the powervmtool, this support only the Hitachi Storage Arrays
Will add the following set of knife sub commands : 

* ```knife power mapping get``` : Get a listing of all the partition storage mappings, vscsi & npiv
* ```knife power config create``` :Create a json formated configuration file for creating a lpar via the `lpar create` subcommand
* ```knife power config get``` : Get a listing of the configuration settings for all or the specified lpar
* ```knife power lpar find``` : Find the phyical host for the specified lpar
* ```knife power lpar create``` : Create a lpar from the configuration file generated with the `config create`

### Module configuration file : `~/knife-power-config.yml`

This file helps defining common configuration settings : 

```yaml
### HMC Part
#
:hmc:
  :host: 'hmchost'
  :port: '22'
  :user: 'hscroot'
  :password: 'abc123'
## NIM Part
:nim:
  :host: 'nimhost'
  :port: '22'
  :user: 'root'
  :password: 'rootroot'
  :nimobjects: 
    - 'group=master_713'
    - 'resolv_conf=fr_RESOLV'
    - 'file_res=FR_DC_FR'
## Misc Part
#
:misc: 
  :reportdir: '~/knife-power-reports/'
  :configdir: '~/knife-power-configs/'
## Array Friendly names part
#
:friendlynames:
  :storagearray: 
    13C89:  'SA_DC1'
    12A6B:  'SA_DC2'
```

### knife config get

Will fetch lpar configuration on Hmc : 

Fetch all the configuration of all the lpars from all the managed systems with the help of the configuration file:
```bash
$ knife power config get -a
```
will produce the following output : 

```bash
$ knife power config get -a
WARNING: No knife configuration file found
Loading configuration file ~/knife-power-config.yml
Will fetch all partitions from all managed hosts on hmc hmc1
Managed system : p770_1
Partition ID  Partition     State  Profile           CPU Type  CPU Mode  CPU Weight  SharedProcPool  Desired VP  Max VP  Desired EC  Max EC  Desired Memory  Max Memory  AME Factor
1             p770_1_vio1         default           shared    uncap     254         DefaultPool     4           8       2.0         8.0     6.0             16.0        0.0
2             p770_1_vio2         default           shared    uncap     254         DefaultPool     4           8       2.0         8.0     6.0             16.0        0.0
4             lpartest_1          default           shared    uncap     128         DefaultPool     1           2       0.1         1.0     4.0             16.0        1.2
3             lpartest_2          default           shared    uncap     128         DefaultPool     2           4       0.2         0.4     3.5             16.0        1.2

Managed system : p770_2
Partition ID  Partition     State  Profile           CPU Type  CPU Mode  CPU Weight  SharedProcPool  Desired VP  Max VP  Desired EC  Max EC  Desired Memory  Max Memory  AME Factor
1             p770_2_vio1         default           shared    uncap     254         DefaultPool     4           8       2.0         8.0     6.0             16.0        0.0
2             p770_2_vio2         default           shared    uncap     254         DefaultPool     4           8       2.0         8.0     6.0             16.0        0.0
3             lpar1              default            shared    uncap     128         DefaultPool     2           4       0.2         4.0     4.0             16.0        1.2
4             lpar2              default            shared    uncap     128         DefaultPool     1           2       0.1         2.0     4.0             16.0        1.2
```

Fetch the configuration of lpar `lpar_name` from managed system `managed_system_name` with the HMC settings specified : 
```bash
knife power config get --hmc 1.2.3.4 --hmc-user hscroot --hmc-passwd passwd -m manged_system_name -n lpar_name
````

### knife config create

Used to generate partition configuration file.
It's an interactive shell which prompt for questions 

```bash
knife power create lpar
```
``` bash
vfoucault@ubuntu:~$ knife power config create
Loading configuration file /home/vfoucault/knife-power-config.yml
LPAR Json configuration creator
-------------------------------
Managed systems available on this HMC
-------------------------------------
a - p770_1
b - p770_2

Please choose the hosting managed system : b

LPAR Settings :
---------------
LPAR Name ? lpar1
Number of Virtual processors ? 4
Quantity of Memory (Gb) ? 16
---------------
a - yes
b - no
Use VSCSI Adapters ? a
Ldev devices to use in order : rootvg,othervg...
----------------------------------------------------
enter them in the following form : ARRAYSN:LDEVID;ARRAYSN:LDEVID (eg.: 15EF5:0256;15EF5:02A8)
LDEVs to use : 15EF5:0256;15EF5:02A8

 Entered ldevs list :
=> 15EF5:0256
=> 15EF5:02A8
1 - yes
2 - no
Is the input correct ?
1
---------------
a - yes
b - no
Use VFC Adapters ? a
Networks :
----------
How much network interface to create ? 1
VLAN ID for interface no. 1? 1899
NetBoot :
---------
a - yes
b - no
Setup IP for netboot ? : a
IP for netboot for vnet 1899 ? 10.18.18.156
Netmask for IP 10.18.18.156 ? 255.255.255.0
gateway for IP 10.18.18.156 ? 10.18.18.1
Sysref :
--------
a - AIX713_SP4
b - AIX713_SP2
c - AIX619_SP4


Which LPP_source to use ? : a
Successfully saved file /home/vfoucault/knife-power-configs/lpar1.json
vfoucault@ubuntu:~$
```
The produced file is a json formated file : 

``` 
vfoucault@ubuntu:~$ cat /home/vfoucault/knife-power-configs/lpar1c.json
{"managedsys":"p770_2",
 "lparname":"uxit204c",
 "vp":4,
 "mem":16,
 "ame":1.2,
 "vdevs":{
   "vscsi":{
     "vio1":[20,22],
     "vio2":[21,23]},
     "vfc":{
       "vio1":[30,"fcs0"],
       "vio2":[31,"fcs3"]},
     "vnet":[1899]},
     "ldevs":["15EF5:0256","15EF5:02A8"],
     "netboot":{
       "vlan":1899,        
       "ip":"10.18.18.156",
       "netmask":"255.255.255.0",
       "nimnetname":"N/A",
       "sysref":"AIX710_SP4"}}
vfoucault@ubuntu:~$  
```
### knife power mapping get
Extract a map of all the storage related mappings (both vscsi & vfc)
```bash
knife power mapping get -m framename -n partition 
```
``` bash
vfoucault@ubuntu:~$ knife power mapping get -n uxit190c -m p770-1
WARNING: No knife configuration file found
Loading configuration file ~/knife-power-config.yml
Will fetch partition lpar1 from managed host p770-1 on hmc hmc1.domain
Managed system : p770_1       Partition : lpar1
ViosID  SrvAdapID  vhost   CltAdapID  device           lun   vtd      pvid              ArraySN  DevID  Size
1       10         vhost0  20         lpar1dsadc102E4  0x81  hdisk72  00c9c37775dc3f63  SA_DC1   02E4   65536
                                      lpar1dsadc102E5  0x82  hdisk73  none              SA_DC1   02E5   32768
                                      lpar1dsadc102E6  0x83  hdisk74  none              SA_DC1   02E6   32768
                                      lpar1dsadc102E7  0x84  hdisk75  none              SA_DC1   02E7   1024
                                      lpar1dsadc102E8  0x85  hdisk76  none              SA_DC1   02E8   32768
                                      lpar1dsadc101FE  0x86  hdisk77  none              SA_DC1   01FE   32768
2       10         vhost0  21         lpar1dsadc102E4  0x81  hdisk72  00c9c37775dc3f63  SA_DC1   02E4   65536
                                      lpar1dsadc102E5  0x82  hdisk73  none              SA_DC1   02E5   32768
                                      lpar1dsadc102E6  0x83  hdisk74  none              SA_DC1   02E6   32768
                                      lpar1dsadc102E7  0x84  hdisk75  none              SA_DC1   02E7   1024
                                      lpar1dsadc102E8  0x85  hdisk76  none              SA_DC1   02E8   32768
                                      lpar1dsadc101FE  0x86  hdisk77  none              SA_DC1   01FE   32768
1       11         vhost1  22
2       11         vhost1  23

ViosID  SrvAdapID  vfchost   CltAdapID  PhysLoc                     VioDev  ClntDev  WWN1              WWN2              Status         flags  Ports LoggedIn
1       15         vfchost0  30         U2C4E.001.XXXXXXX-P2-C4-T1  fcs0             xxxxxxxxxxxxxxxx  xxxxxxxxxxxxxxxx  NOT_LOGGED_IN  4      0
2       15         vfchost0  31         U2C4E.001.XXXXXXX-P2-C5-T2  fcs3             xxxxxxxxxxxxxxxx  xxxxxxxxxxxxxxxx  NOT_LOGGED_IN  4      0

vfoucault@ubuntu:~$

```
Output settings : 
```bash
    -o FORMAT dump the output un csv (format => csv)
```
### knife power lpar create
Will create the lpar from the specified lpar configuration file
```bash
knife power lpar create  -e lparconfig.json
```
``` 
exhibit
```


