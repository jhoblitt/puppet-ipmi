Puppet ipmi Module
==================

[![Build Status](https://travis-ci.org/jhoblitt/puppet-ipmi.png)](https://travis-ci.org/jhoblitt/puppet-ipmi)


#### Table of Contents

1. [Overview](#overview)
2. [Description](#description)
3. [Usage](#usage)
    * [Example](#example)
    * [Classes](#classes)
4. [Limitations](#limitations)
    * [Tested Platforms](#tested-platforms)
5. [Versioning](#versioning)
6. [Support](#support)
7. [See Also](#see-also)


Overview
--------

Manages IPMI


Description
-----------

Installs the [OpemIPMI](http://openipmi.sourceforge.net/) package and enables
the `ipmi` service.  This loads the kernel drivers needed for communicating
with the BMC from user space. Moreover, two facts are made available to the system.


Usage
-----

### Example

```puppet
    include ipmi
```

### Classes

#### `ipmi`

```puppet
# defaults
class { 'ipmi':
  service_ensure         => 'running', # default is 'running'
  ipmievd_service_ensure => 'running', # default is 'stopped'
  watchdog               => true,      # default is false
}
```

##### `service_ensure`

`String` defaults to: `running`

Possible values: `running`, `stopped`

Controls the state of the `ipmi` service.

##### `ipmievd_service_ensure`

`String` defaults to: `stopped`

 Possible values: `running', `stopped`

Controls the state of the `ipmievd` service.

##### `watchdog`

`Boolean` defaults to: `false`

Controls whether the IPMI watchdog is enabled.

### Facts

This module provides the following facts:

* kmod_isloaded_ipmi_si (Boolean) `true` if kernel module is loaded, `false` otherwise
* bmc_lan_conf (Hash) returns LAN configuration of BMC. Example: `{"IP_Address"=>"192.168.1.1", "Subnet_Mask"=>"255.255.255.0", "IP_Address_Source"=>"Static", "Default_Gateway_MAC_Address"=>"00:00:00:00:00:00", "Backup_Gateway_IP_Address"=>"0.0.0.0", "Backup_Gateway_MAC_Address"=>"00:00:00:00:00:00", "MAC_Address"=>"FF:FF:FF:FF:FF:FF", "Default_Gateway_IP_Address"=>"192.168.1.254"}`

Limitations
-----------

At present, only support for `$::osfamily == 'RedHat'` has been implimented.
Adding other Linux distrubtions should be trivial.

### Tested Platforms

* el5.x
* el6.x
* el7.x


Versioning
----------

This module is versioned according to the [Semantic Versioning
2.0.0](http://semver.org/spec/v2.0.0.html) specification.


Support
-------

Please log tickets and issues at
[github](https://github.com/jhoblitt/puppet-ipmi/issues)


See Also
--------

* [OpenIPMI](http://openipmi.sourceforge.net/)
* [FreeIPMI](http://www.gnu.org/software/freeipmi/)
