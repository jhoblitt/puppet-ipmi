# @summary ipmi_watchdog module parameters
#
# They are written to modprobe.d or to the OpenIPMI service's
# IPMI_WATCHDOG_OPTIONS, which its helper script sources and expands unquoted
# on the modprobe command line, so values are limited to characters that need
# no quoting.
type Ipmi::Watchdog::ModuleOptions = Hash[
  Pattern[/\A[a-z][a-z0-9_]*\z/],
  Variant[Integer, Float, Boolean, Pattern[/\A[\w.,:+-]+\z/]],
]
