# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/base'
require 'puppet_x/ipmi/lan_channel'
require 'puppet_x/ipmi/provider/user_allocator'

# Backend-independent behaviour of the `ipmi_user` providers.
#
# Design rationale: the ordering of steps (name, password, privilege, access),
# the "never touch a slot we do not own" guard and the purge sequence are
# policy, not tool syntax.  They live here once so the ipmitool and freeipmi
# providers cannot drift apart.  A provider includes this module and supplies
# only the class-level primitives below; each is a thin wrapper around its
# command line tool.
#
# Backend primitives (class methods, all take the IPMI user channel):
#
# * `read_users(channel)` -> Array of `{ id:, name:, priv:, enabled: }`.
#   `name` is `''` for an empty slot, `priv` is an Integer (1-4, 15 for NO
#   ACCESS, 0 when unknown) and `enabled` is true or false.
# * `write_name(channel, id, name)`
# * `write_password(channel, id, password)`
# * `password_matches?(channel, id, password)` -> Boolean
# * `write_priv(channel, id, priv)` change the privilege of a live user.
# * `write_access(channel, id, enabled, priv)` enable or disable the slot's
#   channel and SOL access in the order the backend requires.
module PuppetX::Ipmi::Provider::UserLogic
  NO_ACCESS_PRIV = 15

  # @param name [String, nil]
  # @return [Boolean] true when a slot name marks the slot as unused
  def self.free_name?(name)
    name.to_s.empty? || name.to_s.start_with?('DISABLED_')
  end

  # @return [String] the placeholder name given to a purged slot
  def self.disabled_name(id)
    "DISABLED_#{id}"
  end

  # Find the slot that already belongs to a user.  Pure function of the BMC
  # table so it can be shared by prefetch and any other caller.
  #
  # With an explicit id the slot must hold the username.  With `:auto` the
  # lowest id holding the username wins; slot 1 is the anonymous slot and is
  # never matched.
  #
  # @param table [Array<Hash>] BMC user table
  # @param username [String]
  # @param requested_id [Integer, Symbol] explicit id or :auto
  # @return [Hash, nil]
  def self.existing_slot(table, username, requested_id)
    return table.find { |u| u[:id] != 1 && u[:name] == username } if requested_id == :auto

    table.find { |u| u[:id] == requested_id && u[:name] == username }
  end

  # Find slots that hold a username but are not the slot any resource in the
  # catalog manages.  Slot 1 (anonymous) is never reported.
  #
  # @param table [Array<Hash>] BMC user table
  # @param username [String]
  # @param claimed_ids [Array<Integer>] slots assigned to catalog resources
  # @return [Array<Hash>]
  def self.stray_slots(table, username, claimed_ids)
    table.select do |u|
      u[:id] != 1 && u[:name] == username && !claimed_ids.include?(u[:id])
    end
  end

  # Translate a table entry to the property hash a provider instance carries.
  #
  # @param entry [Hash, nil] table entry, nil when the user does not exist
  # @param channel [Integer]
  # @return [Hash]
  def self.property_hash_for(entry, channel)
    return { ensure: :absent } if entry.nil?

    enable = :false
    enable = :true if entry[:enabled] && entry[:priv] != NO_ACCESS_PRIV

    { ensure: :present, name: entry[:name], user_id: entry[:id], priv: entry[:priv], enable: enable, channel: channel }
  end

  # Class-level behaviour mixed into each provider class.
  module ClassMethods
    # Enumerate every named user slot on the default channel, so that
    # `puppet resource ipmi_user` works.
    #
    # @return [Array<Puppet::Provider>]
    def instances
      channel = PuppetX::Ipmi::LanChannel.default_channel(nil)
      read_users(channel).reject { |u| PuppetX::Ipmi::Provider::UserLogic.free_name?(u[:name]) }.map do |entry|
        new(PuppetX::Ipmi::Provider::UserLogic.property_hash_for(entry, channel).merge(name: entry[:name]))
      end
    end

    # Slots that duplicate a resource's username outside the slots the
    # catalog manages.  Used by the type's `generate` to purge them.
    #
    # @param resource [Puppet::Type, Hash]
    # @param peers [Array<Puppet::Type>] every ipmi_user on the same channel,
    #   including the resource itself
    # @return [Array<Hash>] table entries to purge
    def stray_slots(resource, peers)
      table = read_users(resource[:channel])
      results = PuppetX::Ipmi::Provider::UserAllocator.allocate(table, peers.map { |r| allocation_request(r) })
      return [] if results.fetch(resource[:name]).key?(:error)

      claimed = results.values.filter_map { |r| r[:id] }
      PuppetX::Ipmi::Provider::UserLogic.stray_slots(table, resource[:username] || resource[:name], claimed)
    end

    # Describe a resource to the allocator.
    #
    # @param resource [Puppet::Type, Hash]
    # @return [Hash]
    def allocation_request(resource)
      {
        title: resource[:name],
        username: resource[:username] || resource[:name],
        user_id: resource[:user_id],
        present: resource[:ensure] != :absent,
      }
    end

    # Build the provider for one resource from an already-read BMC table.
    #
    # @param resource [Puppet::Type, Hash]
    # @param table [Array<Hash>]
    # @param allocation [Hash, nil] this resource's entry from
    #   UserAllocator.allocate; computed for the resource alone when omitted
    # @return [Puppet::Provider]
    def provider_for(resource, table, allocation = nil)
      allocation ||= PuppetX::Ipmi::Provider::UserAllocator.allocate(table, [allocation_request(resource)]).fetch(resource[:name])
      username = resource[:username] || resource[:name]
      entry = PuppetX::Ipmi::Provider::UserLogic.existing_slot(table, username, resource[:user_id])
      provider = new(PuppetX::Ipmi::Provider::UserLogic.property_hash_for(entry, resource[:channel]))
      provider.resource = resource
      provider.slots = table
      provider.allocation = allocation
      provider
    end

    # Read each channel's user table once, allocate slots for every resource
    # on that channel together, and hand each resource a provider bound to
    # the snapshot.
    #
    # @param resources [Hash<String, Puppet::Type>]
    # @return [void]
    def prefetch(resources)
      resources.values.group_by { |r| r[:channel] }.each do |channel, group|
        table = read_users(channel)
        allocations = PuppetX::Ipmi::Provider::UserAllocator.allocate(table, group.map { |r| allocation_request(r) })
        group.each { |resource| resource.provider = provider_for(resource, table, allocations.fetch(resource[:name])) }
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  # @param value [Hash] this resource's entry from UserAllocator.allocate
  attr_writer :allocation

  # The slot this resource manages.  Raises when the allocator found no free
  # slot, so only the affected resource fails.
  #
  # @return [Integer, nil] nil only for an absent user that has no slot
  def resolved_user_id
    @allocation ||= PuppetX::Ipmi::Provider::UserAllocator.allocate(slots, [self.class.allocation_request(@resource)]).fetch(@resource[:name])
    raise Puppet::Error, @allocation[:error] if @allocation.key?(:error)

    @allocation[:id]
  end

  # @return [String] target username from the resource
  def user_name
    @resource[:username] || @resource[:name]
  end

  def real_password
    pw = @resource[:password].respond_to?(:unwrap) ? @resource[:password].unwrap : @resource[:password]
    return nil if pw.nil?

    pw.to_s
  end

  # @return [Array<Hash>] cached BMC user table for the resource's channel
  def slots
    @slots ||= self.class.read_users(channel)
  end

  # @param value [Array<Hash>] snapshot read by prefetch
  attr_writer :slots

  # Drop the cached user table after a write.
  #
  # @return [void]
  def refresh_slots!
    @slots = nil
  end

  # @return [Hash, nil] the table entry for the resolved slot
  def slot_entry
    slots.find { |u| u[:id] == resolved_user_id }
  end

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  # @return [Boolean] true when the BMC holds a slot for the target user
  def exists?
    @property_hash[:ensure] == :present
  end

  # Create (or fully converge) the user in one step.  Puppet skips the other
  # properties on the run that changes `ensure`, so everything is applied here.
  #
  # @return [void]
  def create
    if @resource[:enable] == :false
      disable_user!
    else
      enable_user!
    end
  end

  # IPMI cannot delete a slot.  Absent means: named DISABLED_<id> with no
  # channel or SOL access, which the allocator treats as free.
  #
  # Permissions cannot be adjusted on a disabled account, so access is revoked
  # only while the account is still enabled, and always before the rename so a
  # failure never leaves a "free" slot that still has access.
  #
  # @return [void]
  def destroy
    id = @property_hash[:user_id]
    entry = slots.find { |u| u[:id] == id }
    if entry && entry[:enabled]
      self.class.write_access(channel, id, false, NO_ACCESS_PRIV)
    else
      Puppet.debug("ipmi_user #{user_name}: slot #{id} is already disabled, leaving its permissions alone")
    end
    self.class.write_name(channel, id, PuppetX::Ipmi::Provider::UserLogic.disabled_name(id))
    refresh_slots!
  end

  # Passwords cannot be read back from the BMC.
  #
  # @return [Symbol] :absent
  def password
    :absent
  end

  # Test the current BMC password against the desired value.
  #
  # @return [Boolean]
  def password_insync?
    return true if @resource[:enable] == :false

    pw = real_password
    return true if pw.nil? || pw.empty?

    self.class.password_matches?(channel, resolved_user_id, pw)
  rescue StandardError => e
    # Log at warning: a silently failing check causes a password rewrite on
    # every run, which should be visible in reports.
    Puppet.warning("ipmi_user #{user_name}: password check failed: #{e.class}: #{e.message}")
    false
  end

  # @param _val [String] ignored; password is read from the resource
  # @return [void]
  def password=(_val)
    return if @resource[:enable] == :false

    pw = real_password
    return if pw.nil? || pw.empty?

    assert_slot_owned!
    self.class.write_password(channel, resolved_user_id, pw)
    refresh_slots!
  end

  # @return [Symbol] :true if the slot grants access, :false otherwise
  def enable
    @property_hash.fetch(:enable, :false)
  end

  # A disabled resource is only converged once the slot has NO ACCESS, which
  # is stricter than the enabled flag alone.
  #
  # Most BMCs refuse permission changes on a disabled account, so a slot
  # that is already disabled but still holds a privilege is drift we cannot
  # fix.  Note once per evaluation and treat it as converged rather than
  # attempting a write that fails (or silently no-ops) on every run.
  #
  # Only meaningful for a resource that wants the user disabled; when the
  # resource wants the slot enabled, leftover privilege is real drift that
  # the normal property setters can and should fix.
  #
  # @return [Boolean]
  def access_revoked?
    return true if @property_hash[:priv] == NO_ACCESS_PRIV
    return false unless @property_hash[:enable] == :false && @resource[:enable] == :false

    Puppet.info("ipmi_user #{user_name}: slot is disabled with priv #{@property_hash[:priv]}; " \
                'BMCs do not allow permission changes on disabled accounts, treating as converged')
    true
  end

  # @param val [Symbol] :true to enable, :false to disable
  # @return [void]
  def enable=(val)
    if [:true, true].include?(val)
      enable_user!
    else
      disable_user!
    end
  end

  # @return [Integer, nil] numeric privilege level of the slot
  def priv
    @property_hash[:priv]
  end

  # @param val [Integer] privilege level to set
  # @return [void]
  def priv=(val)
    assert_slot_owned!
    self.class.write_priv(channel, resolved_user_id, val)
    refresh_slots!
  end

  private

  # Refuse to modify password or privilege unless the resolved slot is owned
  # by the target user.  If a previous name write failed (e.g. the BMC
  # rejected a duplicate name), this prevents the wrong slot from receiving
  # this resource's password or privilege.
  def assert_slot_owned!
    entry = slot_entry
    actual = nil
    actual = entry[:name] unless entry.nil?
    return if actual == user_name

    raise Puppet::Error, "Refusing to modify slot #{resolved_user_id}: expected user '#{user_name}' but slot contains #{actual.inspect}"
  end

  # Enable the resolved slot with the configured username, password,
  # privilege and channel access.  The name write is skipped when the slot
  # already holds the target name: some firmwares invalidate sessions on
  # rename even when the value is unchanged.
  #
  # @return [void]
  def enable_user!
    id = resolved_user_id
    entry = slot_entry
    current = nil
    current = entry[:name] unless entry.nil?
    self.class.write_name(channel, id, user_name) unless current == user_name

    pw = real_password
    self.class.write_password(channel, id, pw) if pw && !pw.empty?

    self.class.write_access(channel, id, true, @resource[:priv] || 4)
    refresh_slots!
  end

  # Disable the resolved slot by removing privileges and channel access.  An
  # empty slot is named first so the disabled resource still reserves the
  # requested username.
  #
  # @return [void]
  def disable_user!
    id = resolved_user_id
    entry = slot_entry
    current = nil
    current = entry[:name] unless entry.nil?
    Puppet.debug("ipmi_user disable slot #{id}: current_name=#{current.inspect}, desired_name=#{user_name.inspect}")
    self.class.write_name(channel, id, user_name.to_s) if current.to_s.strip.empty? && !user_name.to_s.strip.empty?

    # Access is revoked only while the account is still enabled; BMCs do not
    # allow permission changes on a disabled account, so an already disabled
    # slot that still holds a privilege is left alone with a notice.  Any
    # other slot gets the revoke write (harmless when it is a no-op).
    if entry && !entry[:enabled] && entry[:priv] != NO_ACCESS_PRIV
      Puppet.info("ipmi_user #{user_name}: slot #{id} is already disabled with priv #{entry[:priv]}; " \
                  'BMCs do not allow permission changes on disabled accounts, leaving its permissions alone')
    else
      self.class.write_access(channel, id, false, NO_ACCESS_PRIV)
    end
    refresh_slots!
  end
end
