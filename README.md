Puppet ipmi Module
=========================

[![Build Status](https://travis-ci.org/jhoblitt/puppet-ipmi.png)](https://travis-ci.org/jhoblitt/puppet-ipmi)


#### Table of Contents

1. [Overview](#overview)
2. [Description](#description)
3. [Usage](#usage)
4. [Limitations](#limitations)
    * [Tested Platforms](#tested-platforms)
5. [Support](#support)


Overview
--------

Manages the OpenIPMI package


Description
-----------

Installs the [OpemIPMI](http://openipmi.sourceforge.net/) package and enables
the `ipmi` service.  This loads the kernel drivers needed for communicating
with the BMC from user space.


Usage
-----

### Basic

```puppet
    include ipmi
```

### Parameters

* `service_ensure`

String.  Possible values: 'running', 'stopped'

Controls the state of the `ipmi` service.

Default: 'running'

* `ipmievd_service_ensure`

String.  Possible values: 'running', 'stopped'

Controls the state of the `ipmievd` service.

Default: 'stopped'

```puppet
    class { 'ipmi':
      service_ensure         => 'running', # default is 'running'
      ipmievd_service_ensure => 'running', # default is 'stopped'
    }
```


Limitations
-----------

At present, only support for `$::osfamily == 'RedHat'` has been implimented.
Adding other Linux distrubtions should be trivial.

### Tested Platforms

* el5.x
* el6.x
* el7.x


Support
-------

Please log tickets and issues at
[github](https://github.com/jhoblitt/puppet-ipmi/issues)


