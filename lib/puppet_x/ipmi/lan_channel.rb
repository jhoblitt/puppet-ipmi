# frozen_string_literal: true

require 'puppet_x/ipmi'

# Shared LAN channel parameter for IPMI network resources.
#
# This mixin is used by the `ipmi_network` and `ipmi_snmp` native types so
# that both share identical `lan_channel` behavior, validation, and default
# derivation.  Keeping the definition in one place avoids duplicated code
# between the two types.
#
# Why `puppet_x`: `Puppet::Type` is a class, so it cannot be used as a
# namespace, and reopening `Puppet::Util` risks collisions with Puppet.
#
# Derives the channel from the resource title when it is an integer,
# otherwise uses 1. Node fact defaults are injected by the ipmi class during
# catalog compilation; a native type must not consult the compiler's facts.
module PuppetX::Ipmi::LanChannel
  # Resolve the standalone resource default without local Facter calls.
  def self.default_channel(title)
    return title.to_i if title.to_s =~ %r{\A\d+\z}

    1
  end

  # Validate and munge a channel number parameter: an integer from 1 to 15.
  # Shared by `lan_channel` and `ipmi_user`'s `channel`.
  #
  # @param param [Class] the parameter class, from inside `newparam`
  # @param name [String] the parameter's name, for the error message
  # @return [void]
  def self.channel_number(param, name)
    param.validate do |value|
      raise Puppet::Error, "#{name} must be an integer between 1 and 15" unless value.to_s =~ %r{\A(?:[1-9]|1[0-5])\z}
    end
    param.munge(&:to_i)
  end

  # Declares the shared `lan_channel` parameter on the including type.
  #
  # @param base [Class] the native type that includes this module
  # @return [void]
  def self.included(base)
    base.newparam(:lan_channel) do
      desc <<-DESC
        The IPMI LAN channel number to configure.
        Derived from the title when the title is an integer.

        Defaults to 1 otherwise. The ipmi class can inject a default
        from the node's ipmi.default.channel fact.
      DESC

      defaultto do
        PuppetX::Ipmi::LanChannel.default_channel(resource[:name])
      end

      PuppetX::Ipmi::LanChannel.channel_number(self, 'lan_channel')
    end
  end

  # Reject catalogs where two resources of the same type target the same
  # LAN channel.  Without this check, free-form titles let multiple
  # resources manage the same channel, causing them to flip-flop on every
  # run.
  #
  # Defined here (not duplicated per type) so every type that includes
  # this mixin gets identical duplicate-channel protection.
  def pre_run_check
    return unless catalog

    channel = self[:lan_channel]
    duplicates = catalog.resources.select do |r|
      r.is_a?(self.class) && r.name != name && r[:lan_channel] == channel
    end
    return if duplicates.empty?

    type_name = self.class.name.to_s.split('::').last.downcase
    names = ([self] + duplicates).map(&:name).sort.join(', ')
    raise Puppet::Error, "Multiple #{type_name} resources target channel #{channel}: #{names}"
  end
end
