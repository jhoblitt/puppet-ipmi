# == Class: ipmi::install
#
# This class should be considered private.
#
# === Authors
#
# Joshua Hoblitt <jhoblitt@cpan.org>
#
# === Copyright
#
# Copyright (C) 2013 Joshua Hoblitt
#
class ipmi::install {
  package { $ipmi::params::ipmi_package:
    ensure => present,
  }
}
