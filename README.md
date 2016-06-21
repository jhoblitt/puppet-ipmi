Puppet ipmi Module
==================

[![Build Status](https://travis-ci.org/jhoblitt/puppet-ipmi.png)](https://travis-ci.org/jhoblitt/puppet-ipmi)


#### Table of Contents

1. [Overview](#overview)
2. [Description](#description)
3. [Usage](#usage)
    * [Examples](#examples)
    * [Classes](#classes)
4. [Additional Facts](#additional-facts)
5. [Limitations](#limitations)
    * [Tested Platforms](#tested-platforms)
    * [Puppet Version Compatibility](#puppet-version-compatibility)
6. [Versioning](#versioning)
7. [Support](#support)
8. [Contributing](#contributing)
9. [See Also](#see-also)


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

### Examples

```puppet
   include ipmi
```

Create a user with admin privileges (default):
```puppet
   ipmi::user { 'newuser1':
     user     => 'newuser1',
     password => 'password1',
     user_id  => 4,
   }
```
Create a user with operator privileges:
```puppet
   ipmi::user { 'newuser2':
     user     => 'newuser2',
     password => 'password2',
     priv     => 3,
     user_id  => 5,
   }
```
Configure a static ip on IPMI lan channel 1:
```puppet
   ipmi::network { 'lan1':
     type        => 'static',
     ip          => '192.168.1.10',
     netmask     => '255.255.255.0',
     gateway     => '192.168.1.1',
   }
```

Configure IPMI lan channel 1 to DHCP:
```puppet
   ipmi::network { 'dhcp': }
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

Possible values: `running`, `stopped`

Controls the state of the `ipmievd` service.

##### `watchdog`

`Boolean` defaults to: `false`

Controls whether the IPMI watchdog is enabled.

### Defined Resources

#### `ipmi::user`

```puppet
# defaults
ipmi::user { 'newuser':
  user     => 'root',
  priv     => 4,           # Administrator
  user_id  => 3,
}
```

#### `ipmi::network`

```puppet
# defaults
ipmi::network { 'lan1':
  type        => 'dhcp',
  ip          => '0.0.0.0',
  netmask     => '255.255.255.0',
  gateway     => '0.0.0.0',
  lan_channel => 1,
}
```

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

### Puppet Version Compatibility

Versions | Puppet 2.7 | Puppet 3.x | Puppet 4.x
:--------|:----------:|:----------:|:----------:
**1.x**  | **yes**    | **yes**    | no
**2.x**  | no         | **yes**    | **yes**


Versioning
----------

This module is versioned according to the [Semantic Versioning
2.0.0](http://semver.org/spec/v2.0.0.html) specification.


Support
-------

Please log tickets and issues at
[github](https://github.com/jhoblitt/puppet-ipmi/issues)


Contributing
------------

1. Fork it on github
2. Make a local clone of your fork
3. Create a topic branch.  Eg, `feature/mousetrap`
4. Make/commit changes
    * Commit messages should be in [imperative tense](http://git-scm.com/book/ch5-2.html)
    * Check that linter warnings or errors are not introduced - `bundle exec rake lint`
    * Check that `Rspec-puppet` unit tests are not broken and coverage is added for new
      features - `bundle exec rake spec`
    * Documentation of API/features is updated as appropriate in the README
    * If present, `beaker` acceptance tests should be run and potentially
      updated - `bundle exec rake beaker`
5. When the feature is complete, rebase / squash the branch history as
   necessary to remove "fix typo", "oops", "whitespace" and other trivial commits
6. Push the topic branch to github
7. Open a Pull Request (PR) from the *topic branch* onto parent repo's `master` branch


See Also
--------

* [OpenIPMI](http://openipmi.sourceforge.net/)
