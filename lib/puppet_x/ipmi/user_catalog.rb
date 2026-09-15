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
  # @return [Array<Puppet::Type>] every ipmi_user in the catalog, on any
  #   channel, including the resource itself: user slots are BMC-wide
  def self.bmc_peers(resource)
    return [resource] unless resource.catalog

    resource.catalog.resources.grep(resource.class)
  end

  # Build one `ensure => absent` resource per slot that duplicates this
  # resource's username outside the slots the catalog manages.
  #
  # Puppet calls this before it applies any resource, so on a fresh node
  # the IPMI tool may not be installed yet, and the BMC may not answer.
  # Neither fails the run here: the purge is left to a later run, and a BMC
  # that cannot be read fails the resource itself when it is prefetched.
  #
  # @param resource [Puppet::Type] an ipmi_user
  # @return [Array<Puppet::Type>]
  def self.duplicate_resources(resource)
    return [] unless resource[:purge_duplicates] && resource[:ensure] == :present

    stray_slots(resource).map do |entry|
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

  # @return [Array<Hash>] stray slots, or none when the BMC cannot be read
  def self.stray_slots(resource)
    provider_class = resource.provider&.class
    unless provider_class&.suitable?
      resource.notice('purge_duplicates is deferred to a later run: no usable ipmitool or bmc-config yet')
      return []
    end

    provider_class.stray_slots(resource, bmc_peers(resource))
  rescue Puppet::Error => e
    resource.warning("purge_duplicates is skipped this run: could not read the BMC user table: #{e.message}")
    []
  end
  private_class_method :stray_slots

  # Reject catalogs where two live resources would fight over a slot on
  # every run: the same username twice on one channel, one explicit slot for
  # different usernames, one username in different explicit slots, one
  # username enabled on one channel and disabled on another or with two
  # passwords, or an absent resource that would remove the slot a live one
  # manages.  User slots and names are BMC-wide, so the rest apply across
  # channels; the same username on several channels is one account with
  # access on each, in one slot.  Free-form titles make these easy to write
  # by accident.  The check runs from each live resource.
  #
  # An absent resource can also hit the slot an explicit id takes over from
  # its username, which depends on the BMC's user table; the allocator fails
  # that resource when the run reads the table.
  #
  # @param resource [Puppet::Type] an ipmi_user
  # @raise [Puppet::Error] on a conflict
  # @return [void]
  def self.check_unique!(resource)
    return unless resource.catalog
    return if resource[:ensure] == :absent

    present, absent = bmc_peers(resource).reject { |r| r.name == resource.name }.partition { |r| r[:ensure] != :absent }
    check_username!(resource, present.select { |r| r[:channel] == resource[:channel] })
    check_absent_peers!(resource, absent)
    check_slot_owner!(resource, present)
    check_username_slot!(resource, present)
    check_account!(resource, present)
  end

  # @return [void]
  def self.check_username!(resource, peers)
    clashing = peers.select { |r| r[:username] == resource[:username] }
    return if clashing.empty?

    names = ([resource] + clashing).map(&:name).sort.join(', ')
    raise Puppet::Error, "Multiple ipmi_user resources manage username #{resource[:username]} on channel #{resource[:channel]}: #{names}"
  end
  private_class_method :check_username!

  # An absent resource for the same username removes this resource's slot
  # when it is `auto` (it targets the lowest slot holding the username) or
  # names this resource's explicit slot.  One that names another slot, like
  # the resources purge_duplicates generates for stray slots, is allowed.
  #
  # @return [void]
  def self.check_absent_peers!(resource, absent)
    clashing = absent.select do |r|
      r[:username] == resource[:username] &&
        (r[:user_id] == :auto || (resource[:user_id] != :auto && r[:user_id] == resource[:user_id]))
    end
    return if clashing.empty?

    names = clashing.map(&:name).sort.join(', ')
    raise Puppet::Error, "Conflicting ipmi_user resources: #{names} (ensure => absent) would remove the slot that " \
                         "#{resource.name} manages for username #{resource[:username]}; user slots are shared by every channel"
  end
  private_class_method :check_absent_peers!

  # @return [void]
  def self.check_slot_owner!(resource, present)
    return if resource[:user_id] == :auto

    clashing = present.select { |r| r[:user_id] == resource[:user_id] && r[:username] != resource[:username] }
    return if clashing.empty?

    names = ([resource] + clashing).map(&:name).sort.join(', ')
    raise Puppet::Error, "Multiple ipmi_user resources claim user_id #{resource[:user_id]} for different usernames: #{names}; " \
                         'user slots are shared by every channel'
  end
  private_class_method :check_slot_owner!

  # @return [void]
  def self.check_username_slot!(resource, present)
    return if resource[:user_id] == :auto

    clashing = present.select { |r| r[:username] == resource[:username] && ![:auto, resource[:user_id]].include?(r[:user_id]) }
    return if clashing.empty?

    names = ([resource] + clashing).map(&:name).sort.join(', ')
    raise Puppet::Error, "Multiple ipmi_user resources put username #{resource[:username]} in different user_id slots: #{names}; " \
                         'one username gets one slot, shared by every channel'
  end
  private_class_method :check_username_slot!

  # A username's enabled state and password are its account's, shared by
  # every channel, so its resources must agree on them; only the privilege
  # is per channel.  A password one of them leaves out is not a
  # disagreement.
  #
  # @return [void]
  def self.check_account!(resource, present)
    present.select { |r| r[:username] == resource[:username] }.each do |peer|
      property = account_conflict(resource, peer)
      next if property.nil?

      names = [resource, peer].map(&:name).sort.join(', ')
      raise Puppet::Error, "ipmi_user resources #{names} manage username #{resource[:username]} but disagree on #{property}; " \
                           "a user's #{property} is shared by every channel"
    end
  end
  private_class_method :check_account!

  # @return [String, nil] the account property two resources disagree on
  def self.account_conflict(resource, peer)
    return 'enable' unless resource[:enable] == peer[:enable]

    passwords = [resource, peer].map { |r| PuppetX::Ipmi.unwrap(r[:password]) }
    'password' unless passwords.include?(nil) || passwords.uniq.one?
  end
  private_class_method :account_conflict
end
