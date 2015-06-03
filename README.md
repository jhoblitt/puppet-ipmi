Puppet ipmi Module
==================

[![Build Status](https://travis-ci.org/jhoblitt/puppet-ipmi.png)](https://travis-ci.org/jhoblitt/puppet-ipmi)


#### Table of Contents

1. [Overview](#overview)
2. [Description](#description)
3. [Usage](#usage)
    * [Example](#example)
    * [Classes](#classes)
4. [Additional Facts](#additional-facts)
5. [Limitations](#limitations)
    * [Tested Platforms](#tested-platforms)
6. [Versioning](#versioning)
7. [Support](#support)
8. [See Also](#see-also)


Overview
--------

Manages the OpenIPMI package


Description
-----------

Installs the [OpemIPMI](http://openipmi.sourceforge.net/) package,
provides IPMI facts in a format compatible with
[The Foreman](www.theforeman.org)'s
[BMC features](www.theforeman.org/manuals/latest/index.html#4.3.3BMC)
and enables the `ipmi` service. The latter loads the kernel drivers
needed for communicating with the BMC from user space.

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

Additional Facts
----------------

This module provides additional facts for Facter with the following
format:

```
ipmi1_gateway => 192.168.10.1
ipmi1_ipaddress => 192.168.10.201
ipmi1_ipaddress_source => Static Address
ipmi1_macaddress => 00:30:48:c9:64:2a
ipmi1_subnet_mask => 255.255.255.0
```

where the 1 in `ipmi1` corresponds to the channel according to
`ipmitool lan print`.

Additionally for compatibility with The Foreman, the first IPMI
interface (i.e. the one from `ipmi lan print 1`) gets all facts
repeated as just `ipmi_foo`:

```
ipmi_gateway => 192.168.10.1
ipmi_ipaddress => 192.168.10.201
ipmi_ipaddress_source => Static Address
ipmi_macaddress => 00:30:48:c9:64:2a
ipmi_subnet_mask => 255.255.255.0
```

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
