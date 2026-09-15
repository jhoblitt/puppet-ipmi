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
# * `lan_get(field)` -> String or nil.  For `:source` the raw tool text; any
#   value containing "DHCP" (case-insensitive) means DHCP, everything else
#   means static.
# * `lan_set(field, value)` -> void.  For `:source` the value is `:dhcp` or
#   `:static`.  The primitive owns any cache invalidation after the write.
module PuppetX::Ipmi::Provider::NetworkLogic
  # @return [Symbol, nil] :dhcp or :static depending on the BMC configuration
  def type
    source = lan_get(:source)
    return nil if source.nil?
    return :dhcp if source.match?(%r{DHCP}i)

    :static
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
      lan_set(field, wanted.to_s) if wanted && lan_get(field) != wanted
    end
  end

  # @return [String, nil] current IP address
  def ip
    lan_get(:ip)
  end

  # @param val [String] IP address to set
  # @return [void]
  def ip=(val)
    lan_set(:ip, val.to_s)
  end

  # @return [String, nil] current subnet mask
  def netmask
    lan_get(:netmask)
  end

  # @param val [String] subnet mask to set
  # @return [void]
  def netmask=(val)
    lan_set(:netmask, val.to_s)
  end

  # @return [String, nil] current default gateway
  def gateway
    lan_get(:gateway)
  end

  # @param val [String] default gateway to set
  # @return [void]
  def gateway=(val)
    lan_set(:gateway, val.to_s)
  end
end
