Puppet ipmi Module
=========================

[![Build Status](https://travis-ci.org/jhoblitt/puppet-ipmi.png)](https://travis-ci.org/jhoblitt/puppet-ipmi)


Description
-----------

Installs the [OpemIPMI](http://openipmi.sourceforge.net/) package and enables
the `ipmi` service.  This loads the kernel drivers needed for communicating
with the BMC from user space.

### Tested on:

* el5.x
* el6.x
 
Examples
--------

    include ipmi

Support
-------

Please log tickets and issues at [github](https://github.com/jhoblitt/puppet-ipmi/issues)


Copyright
---------

Copyright (C) 2013 Joshua Hoblitt <jhoblitt@cpan.org>

