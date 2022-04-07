#
# @api private
#
class ipmi::install {
  assert_private()

  ensure_packages($ipmi::packages)
}
