#
# @api private
#
class ipmi::config {
  assert_private()

  contain ipmi::watchdog
}
