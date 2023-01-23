#
# @api private
#
class ipmi::install {
  assert_private()

  include ipmi

  ensure_packages($ipmi::packages)
}
