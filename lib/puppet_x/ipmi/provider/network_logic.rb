# frozen_string_literal: true

require 'puppet_x/ipmi/provider/base'

# Backend-independent behaviour of the `ipmi_network` providers.
#
# Design rationale: the property surface (`type`, `ip`, `netmask`, `gateway`)
# and the "re-apply the static address after switching to static" rule are
# policy, not tool syntax.  They live here once so the ipmitool and freeipmi
# providers cannot drift apart.  A provider includes this module and supplies
# two instance-level primitives, each a thin wrapper around its command line
# tool.
#
# Backend primitives (field is one of `:source`, `:ip`, `:netmask`, `:gateway`):
#
# * `lan_get(field)` -> String or nil.  For `:source` the raw tool text; a
#   value containing "DHCP" (case-insensitive) means DHCP, one containing
#   "static" means static, anything else (BIOS assigned, unspecified, other)
#   is reported as `:other` so it never satisfies a managed `type`.
# * `lan_set(field, value)` -> void.  For `:source` the value is `:dhcp` or
#   `:static`.  The primitive owns any cache invalidation after the write.
module PuppetX::Ipmi::Provider::NetworkLogic
  # @return [Symbol, nil] :dhcp, :static, or :other for any other source
  def type
    source = lan_get(:source)
    return nil if source.nil?
    return :dhcp if source.match?(%r{DHCP}i)
    return :static if source.match?(%r{static}i)

    :other
  end

  # @param val [Symbol] :dhcp or :static
  # @return [void]
  def type=(val)
    lan_set(:source, val.to_sym)
    return if val.to_s == 'dhcp'

    # Puppet judged ip/netmask/gateway against values read before this switch.
    # Some BMCs load a stored static config when the source changes to static,
    # so re-evaluate and set them now if they still differ from the desired
    # value.
    %i[ip netmask gateway].each do |field|
      wanted = resource[field]
      next unless wanted

      lan_set(field, wanted.to_s) if lan_get(field) != wanted
      settled_by_type[field] = wanted.to_s
    end
  end

  # @return [String, nil] current IP address
  def ip
    lan_get(:ip)
  end

  # @param val [String] IP address to set
  # @return [void]
  def ip=(val)
    lan_set_unless_settled(:ip, val)
  end

  # @return [String, nil] current subnet mask
  def netmask
    lan_get(:netmask)
  end

  # @param val [String] subnet mask to set
  # @return [void]
  def netmask=(val)
    lan_set_unless_settled(:netmask, val)
  end

  # @return [String, nil] current default gateway
  def gateway
    lan_get(:gateway)
  end

  # @param val [String] default gateway to set
  # @return [void]
  def gateway=(val)
    lan_set_unless_settled(:gateway, val)
  end

  private

  # @return [Hash<Symbol, String>] field => value `type=` left on the BMC
  def settled_by_type
    @settled_by_type ||= {}
  end

  # Puppet still calls the ip/netmask/gateway setters after `type=`, because
  # it compares them with the values read before the switch.
  #
  # @param field [Symbol] :ip, :netmask or :gateway
  # @param val [String] value to set
  # @return [void]
  def lan_set_unless_settled(field, val)
    lan_set(field, val.to_s) unless settled_by_type[field] == val.to_s
  end
end
