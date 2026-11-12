# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi'

# Catalog-wide policy for `ipmi_user` resources.
#
# Design rationale: these rules look at more than one resource, so they do not
# belong in the declarative type body.  The type's `generate` and
# `pre_run_check` hooks delegate here, which keeps the type file a description
# of the resource and lets the rules be tested on their own.
module PuppetX::Ipmi::UserCatalog
  # @param resource [Puppet::Type] an ipmi_user
  # @return [Array<Puppet::Type>] every ipmi_user on the same channel,
  #   including the resource itself
  def self.channel_peers(resource)
    return [resource] unless resource.catalog

    resource.catalog.resources.select { |r| r.is_a?(resource.class) && r[:channel] == resource[:channel] }
  end

  # Build one `ensure => absent` resource per slot that duplicates this
  # resource's username outside the slots the catalog manages.
  #
  # @param resource [Puppet::Type] an ipmi_user
  # @return [Array<Puppet::Type>]
  def self.duplicate_resources(resource)
    return [] unless resource[:purge_duplicates] && resource[:ensure] == :present

    resource.provider.class.stray_slots(resource, channel_peers(resource)).map do |entry|
      resource.class.new(
        name: "#{resource[:name]} (duplicate in slot #{entry[:id]})",
        ensure: :absent,
        username: resource[:username],
        user_id: entry[:id],
        channel: resource[:channel],
        provider: resource[:provider],
      )
    end
  end

  # Reject catalogs where two live resources claim the same username or the
  # same explicit slot on one channel.  Free-form titles make this easy to do
  # by accident, and the resources would otherwise fight over the slot on
  # every run.  Resources with `ensure => absent` are exempt.
  #
  # @param resource [Puppet::Type] an ipmi_user
  # @raise [Puppet::Error] on a conflict
  # @return [void]
  def self.check_unique!(resource)
    return unless resource.catalog
    return if resource[:ensure] == :absent

    peers = channel_peers(resource).reject { |r| r.name == resource.name || r[:ensure] == :absent }
    check_same!(resource, peers, :username, 'manage username')
    return if resource[:user_id] == :auto

    check_same!(resource, peers, :user_id, 'claim user_id')
  end

  # @return [void]
  def self.check_same!(resource, peers, key, verb)
    clashing = peers.select { |r| r[key] == resource[key] }
    return if clashing.empty?

    names = ([resource] + clashing).map(&:name).sort.join(', ')
    raise Puppet::Error, "Multiple ipmi_user resources #{verb} #{resource[key]} on channel #{resource[:channel]}: #{names}"
  end
  private_class_method :check_same!
end
