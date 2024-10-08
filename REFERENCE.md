# Reference

<!-- DO NOT EDIT: This document was generated by Puppet Strings -->

## Table of Contents

### Classes

#### Public Classes

* [`ipmi`](#ipmi): Manages OpenIPMI

#### Private Classes

* `ipmi::config`
* `ipmi::install`
* `ipmi::service::ipmi`
* `ipmi::service::ipmievd`

### Defined types

* [`ipmi::network`](#ipmi--network): Manage BMC network configuration
* [`ipmi::snmp`](#ipmi--snmp): Manage SNMP community strings
* [`ipmi::user`](#ipmi--user): Manage BMC users

## Classes

### <a name="ipmi"></a>`ipmi`

Manages OpenIPMI

#### Parameters

The following parameters are available in the `ipmi` class:

* [`packages`](#-ipmi--packages)
* [`config_file`](#-ipmi--config_file)
* [`service_name`](#-ipmi--service_name)
* [`service_ensure`](#-ipmi--service_ensure)
* [`ipmievd_service_name`](#-ipmi--ipmievd_service_name)
* [`ipmievd_service_ensure`](#-ipmi--ipmievd_service_ensure)
* [`watchdog`](#-ipmi--watchdog)
* [`snmps`](#-ipmi--snmps)
* [`users`](#-ipmi--users)
* [`networks`](#-ipmi--networks)
* [`default_channel`](#-ipmi--default_channel)

##### <a name="-ipmi--packages"></a>`packages`

Data type: `Array[String]`

List of packages to install.

##### <a name="-ipmi--config_file"></a>`config_file`

Data type: `Stdlib::Absolutepath`

Absolute path to the ipmi service config file.

##### <a name="-ipmi--service_name"></a>`service_name`

Data type: `String`

Name of IPMI service.

##### <a name="-ipmi--service_ensure"></a>`service_ensure`

Data type: `Stdlib::Ensure::Service`

Controls the state of the `ipmi` service. Possible values: `running`, `stopped`

##### <a name="-ipmi--ipmievd_service_name"></a>`ipmievd_service_name`

Data type: `String`

Name of ipmievd service.

##### <a name="-ipmi--ipmievd_service_ensure"></a>`ipmievd_service_ensure`

Data type: `Stdlib::Ensure::Service`

Controls the state of the `ipmievd` service. Possible values: `running`, `stopped`

##### <a name="-ipmi--watchdog"></a>`watchdog`

Data type: `Boolean`

Controls whether the IPMI watchdog is enabled.

##### <a name="-ipmi--snmps"></a>`snmps`

Data type: `Optional[Hash]`

`ipmi::snmp` resources to create.

##### <a name="-ipmi--users"></a>`users`

Data type: `Optional[Hash]`

`ipmi::user` resources to create.

##### <a name="-ipmi--networks"></a>`networks`

Data type: `Optional[Hash]`

`ipmi::network` resources to create.

##### <a name="-ipmi--default_channel"></a>`default_channel`

Data type: `Integer[0]`

Default channel to use for IPMI commands.

Default value: `Integer(fact('ipmi.default.channel') or 1)`

## Defined types

### <a name="ipmi--network"></a>`ipmi::network`

Manage BMC network configuration

#### Parameters

The following parameters are available in the `ipmi::network` defined type:

* [`ip`](#-ipmi--network--ip)
* [`netmask`](#-ipmi--network--netmask)
* [`gateway`](#-ipmi--network--gateway)
* [`type`](#-ipmi--network--type)
* [`lan_channel`](#-ipmi--network--lan_channel)

##### <a name="-ipmi--network--ip"></a>`ip`

Data type: `Stdlib::IP::Address`

Controls the IP of the IPMI network.

Default value: `'0.0.0.0'`

##### <a name="-ipmi--network--netmask"></a>`netmask`

Data type: `Stdlib::IP::Address`

Controls the subnet mask of the IPMI network.

Default value: `'255.255.255.0'`

##### <a name="-ipmi--network--gateway"></a>`gateway`

Data type: `Stdlib::IP::Address`

Controls the gateway of the IPMI network.

Default value: `'0.0.0.0'`

##### <a name="-ipmi--network--type"></a>`type`

Data type: `Enum['dhcp', 'static']`

Controls the if IP will be from DHCP or Static.

Default value: `'dhcp'`

##### <a name="-ipmi--network--lan_channel"></a>`lan_channel`

Data type: `Optional[Integer]`

Controls the lan channel of the IPMI network to be configured.
Defaults to the first detected lan channel, starting at 1 ending at 11

Default value: `undef`

### <a name="ipmi--snmp"></a>`ipmi::snmp`

Manage SNMP community strings

#### Parameters

The following parameters are available in the `ipmi::snmp` defined type:

* [`snmp`](#-ipmi--snmp--snmp)
* [`lan_channel`](#-ipmi--snmp--lan_channel)

##### <a name="-ipmi--snmp--snmp"></a>`snmp`

Data type: `String`

Controls the snmp string of the IPMI network interface.

Default value: `'public'`

##### <a name="-ipmi--snmp--lan_channel"></a>`lan_channel`

Data type: `Optional[Integer]`

Controls the lan channel of the IPMI network on which snmp is to be configured.
Defaults to the first detected lan channel, starting at 1 ending at 11

Default value: `undef`

### <a name="ipmi--user"></a>`ipmi::user`

Manage BMC users

#### Parameters

The following parameters are available in the `ipmi::user` defined type:

* [`user`](#-ipmi--user--user)
* [`priv`](#-ipmi--user--priv)
* [`enable`](#-ipmi--user--enable)
* [`user_id`](#-ipmi--user--user_id)
* [`password`](#-ipmi--user--password)
* [`channel`](#-ipmi--user--channel)

##### <a name="-ipmi--user--user"></a>`user`

Data type: `String`

Controls the username of the user to be created.

Default value: `'root'`

##### <a name="-ipmi--user--priv"></a>`priv`

Data type: `Integer`

Possible values:
`4` - ADMINISTRATOR,
`3` - OPERATOR,
`2` - USER,
`1` - CALLBACK

Controls the rights of the user to be created.

Default value: `4`

##### <a name="-ipmi--user--enable"></a>`enable`

Data type: `Boolean`

Should this user be enabled?

Default value: `true`

##### <a name="-ipmi--user--user_id"></a>`user_id`

Data type: `Integer`

The user id of the user to be created. Should be unique from existing users.
On SuperMicro IPMI, user id 2 is reserved for the 'ADMIN' username.
On ASUS IPMI, user id 2 is reserved for the 'admin' username.

Default value: `3`

##### <a name="-ipmi--user--password"></a>`password`

Data type: `Optional[Variant[Sensitive[String[1]], String[1]]]`

Controls the password of the user to be created.

Default value: `undef`

##### <a name="-ipmi--user--channel"></a>`channel`

Data type: `Optional[Integer]`

Controls the channel of the IPMI user to be configured.
Defaults to the first detected lan channel, starting at 1 ending at 11

Default value: `undef`

