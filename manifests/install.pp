#
# @api private
#
class ipmi::install {
  assert_private()

  include ipmi

  stdlib::ensure_packages($ipmi::packages)
}
