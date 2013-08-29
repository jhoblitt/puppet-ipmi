# == Class: ipmi
#
# === Examples
#
# include ipmi
#
# === Authors
#
# Joshua Hoblitt <jhoblitt@cpan.org>
#
# === Copyright
#
# Copyright (C) 2013 Joshua Hoblitt
#
class ipmi {
  include ipmi::install, ipmi::service
}
