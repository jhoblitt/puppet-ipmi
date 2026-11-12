# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/base'
require 'puppet_x/ipmi/lan_channel'
require 'puppet_x/ipmi/provider/user_allocator'
require 'puppet_x/ipmi/user_catalog'

# Backend-independent behaviour of the `ipmi_user` providers.
#
# Design rationale: the ordering of steps (name, password, privilege, access),
# the "never touch a slot we do not own" guard and the purge sequence are
# policy, not tool syntax.  They live here once so the ipmitool and freeipmi
# providers cannot drift apart.  A provider includes this module and supplies
# only the class-level primitives below; each is a thin wrapper around its
# command line tool.
#
# A user slot is BMC-wide: its name, password and enabled state are shared
# by every channel.  Only its privilege and access are per channel.  So the
# BMC is read as one table, with each slot's privilege on every LAN channel
# and on every channel a resource names.
#
# Backend primitives (class methods; the writers take the IPMI user channel):
#
# * `lan_channels` -> Array of the BMC's LAN channel numbers.
# * `read_table(channels)` -> Array of `{ id:, name:, status:, privs: }`.
#   `name` is `''` for an empty slot, `status` is `:enabled`, `:disabled`
#   or `:unknown` for the account as a whole, and `privs` maps each of
#   `channels` to the slot's privilege there, an Integer (1-5, 15 for NO
#   ACCESS, 0 for none), or nil when it could not be read.
# * `check_name(channel, id, name)` and `check_password(channel, id,
#   password)` raise Puppet::Error, without echoing the value, when the
#   backend cannot write it.  The writers below apply the same checks.
# * `write_name(channel, id, name)`
# * `write_password(channel, id, password)`
# * `password_matches?(channel, id, password)` -> Boolean
# * `write_priv(channel, id, priv)` change the privilege of a live user.
# * `grant_access(channel, id, priv)` enable the account with the privilege,
#   channel and SOL access on `channel`, through `enable_failing_closed`.
# * `revoke_access(channels, id, already_disabled: false)` remove the
#   privilege, channel and SOL access on each of `channels`, then disable
#   the account, through `disable_failing_closed`.
module PuppetX::Ipmi::Provider::UserLogic
  NO_ACCESS_PRIV = 15

  # Privilege limits under which no session can be established: NO ACCESS,
  # and 0, which is no privilege level at all (ipmitool prints it as
  # `Unknown (0x00)`, bmc-config as an empty value).
  NO_PRIVILEGE = [0, NO_ACCESS_PRIV].freeze

  # The BMC user tables read while a catalog is applied, so that `generate`,
  # which runs once per purge_duplicates resource, and prefetch share one
  # read per provider.  Prefetch is the last reader before any write: it
  # takes the tables and empties the cache.  A write empties it too.  The
  # BMC's LAN channels do not change with its users, so they are kept until
  # the transaction ends.  A different catalog empties both.
  module TableCache
    @catalog = nil
    @tables = {}
    @lan_channels = {}

    # @param catalog [Puppet::Resource::Catalog, nil] nil reads uncached
    # @param key [Array] provider class and channels
    # @yieldreturn [Array<Hash>] the table, read from the BMC
    # @return [Array<Hash>]
    def self.read(catalog, key)
      return yield if catalog.nil?

      use(catalog)
      @tables.fetch(key) { @tables[key] = yield }
    end

    # @param catalog [Puppet::Resource::Catalog, nil] nil probes uncached
    # @param key [Class] provider class
    # @yieldreturn [Array<Integer>] the LAN channels, probed on the BMC
    # @return [Array<Integer>]
    def self.lan_channels(catalog, key)
      return yield if catalog.nil?

      use(catalog)
      @lan_channels.fetch(key) { @lan_channels[key] = yield }
    end

    # @return [void]
    def self.use(catalog)
      clear unless catalog.equal?(@catalog)
      @catalog = catalog
    end

    # @return [void]
    def self.clear_tables
      @tables = {}
    end

    # @return [void]
    def self.clear
      @catalog = nil
      @tables = {}
      @lan_channels = {}
    end
  end

  # @param name [String, nil]
  # @return [Boolean] true when a slot name marks the slot as unused
  def self.free_name?(name)
    name.to_s.empty? || name.to_s.start_with?('DISABLED_')
  end

  # @param priv [Integer, nil] a privilege limit; nil when it was not read
  # @return [Boolean] true unless the limit admits no session
  def self.grants?(priv)
    !NO_PRIVILEGE.include?(priv)
  end

  # @param entry [Hash] table entry
  # @return [Boolean] true when any channel read grants the slot a privilege
  def self.grants_anywhere?(entry)
    entry[:privs].each_value.any? { |priv| grants?(priv) }
  end

  # A slot the allocator may hand out: not the anonymous slot, named as
  # unused, not reported enabled, and granted nothing on any channel read.
  #
  # @param entry [Hash] table entry
  # @return [Boolean]
  def self.free_slot?(entry)
    entry[:id] >= 2 && free_name?(entry[:name]) && entry[:status] != :enabled && !grants_anywhere?(entry)
  end

  # Merge per-channel user lists into one table.
  #
  # @param lists [Hash{Integer => Array<Hash>}] per channel, entries with
  #   `:id`, `:name` and `:priv`
  # @param statuses [Hash{Integer => Symbol}] each slot's status
  # @return [Array<Hash>] table entries, sorted by id
  def self.merge(lists, statuses)
    ids = lists.each_value.flat_map { |list| list.map { |u| u[:id] } }.uniq.sort
    ids.map do |id|
      slots = lists.transform_values { |list| list.find { |u| u[:id] == id } }
      name = slots.each_value.find { |u| u }[:name]
      { id: id, name: name, status: statuses.fetch(id, :unknown), privs: slots.transform_values { |u| u&.fetch(:priv) } }
    end
  end

  # @return [String] the placeholder name given to a purged slot
  def self.disabled_name(id)
    "DISABLED_#{id}"
  end

  # Find the slot that already belongs to a user.  Pure function of the BMC
  # table so it can be shared by the allocator and any other caller.
  #
  # With an explicit id the slot must hold the username.  With `:auto` the
  # lowest id holding the username wins, ignoring the ids in `skip`; slot 1
  # is the anonymous slot and is never matched.
  #
  # @param table [Array<Hash>] BMC user table
  # @param username [String]
  # @param requested_id [Integer, Symbol] explicit id or :auto
  # @param skip [Array<Integer>] ids an `:auto` lookup must not return
  # @return [Hash, nil]
  def self.existing_slot(table, username, requested_id, skip: [])
    return table.find { |u| u[:id] != 1 && u[:name] == username && !skip.include?(u[:id]) } if requested_id == :auto

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

    priv = entry[:privs][channel]
    enable = :false
    enable = :true if entry[:status] != :disabled && priv && grants?(priv)

    { ensure: :present, name: entry[:name], user_id: entry[:id], priv: priv, enable: enable, channel: channel }
  end

  # Whether a slot must be revoked before it is renamed or left disabled:
  # unless the BMC reports it disabled and no channel grants it a
  # privilege.  An unknown status is never taken as disabled.
  #
  # @param entry [Hash, nil] table entry, nil when the table has no such slot
  # @return [Boolean]
  def self.needs_revoke?(entry)
    entry.nil? || entry[:status] != :disabled || grants_anywhere?(entry)
  end

  # Class-level behaviour mixed into each provider class.
  module ClassMethods
    # Enumerate every named user slot on the default channel, so that
    # `puppet resource ipmi_user` works.
    #
    # @return [Array<Puppet::Provider>]
    def instances
      channel = PuppetX::Ipmi::LanChannel.default_channel(nil)
      bmc_table(nil, [channel]).reject { |u| PuppetX::Ipmi::Provider::UserLogic.free_name?(u[:name]) }.map do |entry|
        new(PuppetX::Ipmi::Provider::UserLogic.property_hash_for(entry, channel).merge(name: entry[:name]))
      end
    end

    # Slots that duplicate a resource's username outside the slots the
    # catalog manages.  Used by the type's `generate` to purge them.
    #
    # @param resource [Puppet::Type, Hash]
    # @param peers [Array<Puppet::Type>] every ipmi_user in the catalog, on
    #   any channel, including the resource itself; prefetch allocates them
    #   together, from the same table, so this must too
    # @return [Array<Hash>] table entries to purge
    def stray_slots(resource, peers)
      table = bmc_table(catalog_of(resource), peers.map { |r| r[:channel] })
      results = PuppetX::Ipmi::Provider::UserAllocator.allocate(table, peers.map { |r| allocation_request(r) })
      return [] if results.fetch(resource[:name]).key?(:error)

      claimed = results.values.filter_map { |r| r[:id] }
      PuppetX::Ipmi::Provider::UserLogic.stray_slots(table, resource[:username] || resource[:name], claimed)
    end

    # The BMC's user table across its LAN channels and the channels
    # resources name, read once for the catalog.
    #
    # @param catalog [Puppet::Resource::Catalog, nil]
    # @param channels [Array<Integer>] channels resources name
    # @return [Array<Hash>]
    # @param cached [Boolean] false reads the table again, still using the
    #   LAN channels found for the catalog
    def bmc_table(catalog, channels, cached: true)
      cache = PuppetX::Ipmi::Provider::UserLogic::TableCache
      all = (cache.lan_channels(catalog, self) { lan_channels } + channels).uniq.sort
      return read_table(all) unless cached

      cache.read(catalog, [self, all]) { read_table(all) }
    end

    # @param resource [Puppet::Type, Hash]
    # @return [Array<Integer>] the channels of every ipmi_user in the
    #   resource's catalog, or the resource's own without one
    def peer_channels(resource)
      peers = catalog_of(resource) ? PuppetX::Ipmi::UserCatalog.bmc_peers(resource) : [resource]
      peers.map { |r| r[:channel] }
    end

    # @return [Puppet::Resource::Catalog, nil]
    def catalog_of(resource)
      resource.catalog if resource.respond_to?(:catalog)
    end

    # Puppet calls this once the transaction has evaluated this provider's
    # resources.
    #
    # @return [void]
    def post_resource_eval
      PuppetX::Ipmi::Provider::UserLogic::TableCache.clear
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
    # The observed state comes from the slot the allocator assigned, which
    # is the slot every write goes to.  When that slot does not hold the
    # username the user is absent there, even if another slot holds it.
    #
    # @param resource [Puppet::Type, Hash]
    # @param table [Array<Hash>] covering the resource's channel
    # @param allocation [Hash, nil] this resource's entry from
    #   UserAllocator.allocate; computed for the resource alone when omitted
    # @return [Puppet::Provider]
    def provider_for(resource, table, allocation = nil)
      allocation ||= PuppetX::Ipmi::Provider::UserAllocator.allocate(table, [allocation_request(resource)]).fetch(resource[:name])
      username = resource[:username] || resource[:name]
      entry = table.find { |u| u[:id] == allocation[:id] && u[:name] == username }
      provider = new(PuppetX::Ipmi::Provider::UserLogic.property_hash_for(entry, resource[:channel]))
      provider.resource = resource
      provider.slots = table
      provider.allocation = allocation
      provider
    end

    # Enable a slot so that it fails closed; providers call this from
    # `grant_access`.  The target privilege is written while the slot is
    # still disabled, so the account never comes up with the privilege it
    # had before.  Some BMCs refuse permission changes on a disabled
    # account, so that refusal is tolerated and the privilege is written
    # again once the account is enabled.  If that write or a later one
    # raises, the account is disabled again before the error propagates, so
    # it never stays enabled with stale or partial access.
    #
    # @param id [Integer] the slot, for log messages
    # @param set_priv [#call] writes the target privilege
    # @param set_enabled [#call] called with true to enable the account and
    #   false to disable it
    # @yield writes the SOL and channel access
    # @return [void]
    def enable_failing_closed(id, set_priv:, set_enabled:)
      begin
        set_priv.call
      rescue Puppet::ExecutionFailure => e
        Puppet.debug("ipmi_user: slot #{id} refused a privilege change while disabled, writing it again once enabled: #{e.message}")
      end
      set_enabled.call(true)
      begin
        set_priv.call
        yield
      rescue StandardError => e
        disable_after_failed_enable(id, set_enabled)
        raise e
      end
    end

    # @return [void]
    def disable_after_failed_enable(id, set_enabled)
      set_enabled.call(false)
    rescue StandardError => e
      Puppet.err("ipmi_user: slot #{id} may be left enabled: disabling it after a failed enable also failed: #{e.message}")
    end

    # Disable a slot so that it fails closed; providers call this from
    # `revoke_access`.  Privilege, channel and SOL access are revoked before
    # the account is disabled, because BMCs do not allow permission changes
    # on a disabled account.  Every revoke is attempted even after one
    # fails, and the account is disabled regardless, so a failure never
    # leaves it enabled; the first error is raised afterwards.
    #
    # An account that is already disabled may refuse the permission
    # changes, so with `already_disabled` those refusals are only logged.
    # Disabling it must still succeed.
    #
    # @param id [Integer] the slot, for log messages
    # @param revokes [Array<#call>] each removes some of the slot's access
    # @param set_enabled [#call] called with false to disable the account
    # @param already_disabled [Boolean]
    # @return [void]
    def disable_failing_closed(id, revokes:, set_enabled:, already_disabled:)
      failure = nil
      revokes.each do |revoke|
        revoke.call
      rescue StandardError => e
        if already_disabled && e.is_a?(Puppet::ExecutionFailure)
          Puppet.debug("ipmi_user: slot #{id} is disabled and refused a permission change: #{e.message}")
        else
          failure ||= e
        end
      end
      disable_after_failed_revoke(id, set_enabled, failure)
    end

    # @return [void]
    def disable_after_failed_revoke(id, set_enabled, failure)
      begin
        set_enabled.call(false)
      rescue StandardError => e
        raise e if failure.nil?

        Puppet.err("ipmi_user: slot #{id} may be left enabled: disabling it after a failed revoke also failed: #{e.message}")
      end
      raise failure if failure
    end

    # Read the BMC's user table once, allocate slots for every ipmi_user in
    # the catalog together, and hand each of this provider's resources a
    # provider bound to that snapshot.  Puppet prefetches each provider on
    # its own, but the slots are the BMC's, so resources of other providers
    # are allocated too, exactly as `generate` allocates them.  The table
    # covers the same channels as the one `generate` reads, so that one is
    # used, not read again.
    #
    # @param resources [Hash<String, Puppet::Type>]
    # @return [void]
    def prefetch(resources)
      first = resources.values.first
      peers = catalog_of(first) ? PuppetX::Ipmi::UserCatalog.bmc_peers(first) : resources.values
      table = bmc_table(catalog_of(first), peers.map { |r| r[:channel] })
      PuppetX::Ipmi::Provider::UserLogic::TableCache.clear_tables
      allocations = PuppetX::Ipmi::Provider::UserAllocator.allocate(table, peers.map { |r| allocation_request(r) })
      resources.each_value do |resource|
        resource.provider = provider_for(resource, table, allocations.fetch(resource[:name]))
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
    pw = PuppetX::Ipmi.unwrap(@resource[:password])
    return nil if pw.nil?

    pw.to_s
  end

  # The BMC user table this provider works from: prefetch's snapshot, which
  # it shares with the catalog's other resources, or its own read, which
  # bypasses the catalog's table cache.  Writes update it in place (see
  # wrote), so it is read again only by refresh_slots!.
  #
  # @return [Array<Hash>] covering the resource's channel
  def slots
    @slots ||= read_slots
  end

  # @param value [Array<Hash>] snapshot read by prefetch
  attr_writer :slots

  # Read the table again, into the snapshot, so every resource sharing it
  # sees the BMC's current state.
  #
  # @return [void]
  def refresh_slots!
    PuppetX::Ipmi::Provider::UserLogic::TableCache.clear_tables
    fresh = read_slots
    @slots ? @slots.replace(fresh) : @slots = fresh
  end

  # @return [Array<Hash>]
  def read_slots
    self.class.bmc_table(self.class.catalog_of(@resource), self.class.peer_channels(@resource), cached: false)
  end

  # @return [Hash, nil] the table entry for the resolved slot
  def slot_entry
    slots.find { |u| u[:id] == resolved_user_id }
  end

  # @return [String, nil] the name the resolved slot holds, nil when the
  #   table has no such slot
  def slot_name
    slot_entry&.fetch(:name, nil)
  end

  # @return [Array<Integer>] the channels the table covers: the LAN
  #   channels and those resources name
  def table_channels
    (slots.first&.fetch(:privs)&.keys || []) | [channel]
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
  # The slot is revoked on every channel and disabled first (see
  # revoke_before_rename), so a failure never leaves a "free" slot that
  # still has access.
  #
  # @return [void]
  def destroy
    # Raises when the allocator found a present resource on this slot.
    resolved_user_id
    id = @property_hash[:user_id]
    revoke_before_rename(id, slots.find { |u| u[:id] == id })
    write_name!(id, PuppetX::Ipmi::Provider::UserLogic.disabled_name(id))
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

    @password_synced = self.class.password_matches?(channel, resolved_user_id, pw)
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
    write_password!(resolved_user_id, pw)
  end

  # @return [Symbol] :true if the slot grants access, :false otherwise
  def enable
    @property_hash.fetch(:enable, :false)
  end

  # A disabled resource is converged once the BMC reports the account
  # disabled, or, when it does not report it, once no channel grants the
  # slot a privilege.  NO ACCESS on this channel alone is not enough: it
  # leaves any privilege on another.
  #
  # Most BMCs refuse permission changes on a disabled account, so a slot
  # that is reported disabled but still holds a privilege is drift we
  # cannot fix.  Note it once per evaluation and treat it as converged
  # rather than attempting a write that fails (or silently no-ops) on every
  # run.
  #
  # @return [Boolean]
  def access_revoked?
    logic = PuppetX::Ipmi::Provider::UserLogic
    entry = slots.find { |u| u[:id] == @property_hash[:user_id] }
    return false if entry.nil?
    return !logic.grants_anywhere?(entry) if entry[:status] == :unknown
    return false unless entry[:status] == :disabled

    granted = entry[:privs].select { |_, priv| logic.grants?(priv) }
    unless granted.empty?
      Puppet.info("ipmi_user #{user_name}: slot #{entry[:id]} is disabled with #{granted.map { |c, p| "priv #{p} on channel #{c}" }.join(', ')}; " \
                  'BMCs do not allow permission changes on disabled accounts, treating as converged')
    end
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

  # Puppet syncs `priv` before `enable`.  When this run enables a disabled
  # account, `enable=` writes the privilege as part of the fail-closed
  # enable sequence, so nothing is written here while it is still disabled.
  #
  # @param val [Integer] privilege level to set
  # @return [void]
  def priv=(val)
    return if @property_hash[:enable] == :false && @resource[:enable] == :true

    assert_slot_owned!
    write_priv!(resolved_user_id, val)
  end

  private

  # Record a successful write to slot `id`: empty the catalog's table
  # cache, and apply the write's effect to the snapshot, if it has the
  # slot.  A write that raised records nothing, so the snapshot never shows
  # a change the BMC may not have made.
  #
  # @yieldparam entry [Hash] the slot's entry, to update
  # @return [void]
  def wrote(id)
    PuppetX::Ipmi::Provider::UserLogic::TableCache.clear_tables
    entry = @slots&.find { |u| u[:id] == id }
    yield entry if entry && block_given?
  end

  # @return [void]
  def write_name!(id, name)
    self.class.write_name(channel, id, name)
    wrote(id) { |entry| entry[:name] = name }
  end

  # The table holds no password, so @password_synced is what keeps this run
  # from writing it twice.
  #
  # @return [void]
  def write_password!(id, password)
    self.class.write_password(channel, id, password)
    @password_synced = true
    wrote(id)
  end

  # @return [void]
  def write_priv!(id, priv)
    self.class.write_priv(channel, id, priv)
    wrote(id) { |entry| entry[:privs][channel] = priv }
  end

  # A BMC that reports the account's status reports the one just set.
  #
  # @return [void]
  def grant_access!(id, priv)
    self.class.grant_access(channel, id, priv)
    wrote(id) do |entry|
      entry[:privs][channel] = priv
      entry[:status] = :enabled if entry[:status] == :disabled
    end
  end

  # @return [void]
  def revoke_access!(id, channels, already_disabled:)
    self.class.revoke_access(channels, id, already_disabled: already_disabled)
    wrote(id) do |entry|
      channels.each { |c| entry[:privs][c] = NO_ACCESS_PRIV }
      entry[:status] = :disabled if entry[:status] == :enabled
    end
  end

  # Refuse to modify password or privilege unless the resolved slot is owned
  # by the target user.  If a previous name write failed (e.g. the BMC
  # rejected a duplicate name), this prevents the wrong slot from receiving
  # this resource's password or privilege.
  def assert_slot_owned!
    actual = slot_name
    return if actual == user_name

    raise Puppet::Error, "Refusing to modify slot #{resolved_user_id}: expected user '#{user_name}' but slot contains #{actual.inspect}"
  end

  # Whether the slot must be renamed for this user, which takes it over.
  # A takeover revokes another account, so it is confirmed on a fresh read
  # of the BMC, the one place a write needs one: a resource for this
  # username on another channel, or of another provider, may have renamed
  # the slot since this provider's snapshot was read.
  #
  # @return [Boolean]
  def takeover?
    return false if slot_name == user_name

    refresh_slots!
    slot_name != user_name
  end

  # Revoke the slot's privilege, channel and SOL access on every channel the
  # table covers, then disable the account, unless the BMC reports it
  # disabled and no channel grants it a privilege.  An unknown status is
  # never taken as disabled.  A BMC may refuse permission changes on a
  # disabled account, so unless it reports the account enabled, refusals are
  # tolerated; disabling it must still succeed.
  #
  # @param id [Integer]
  # @param entry [Hash, nil] the slot's table entry
  # @return [Boolean] whether the slot was revoked
  def revoke_unless_disabled(id, entry)
    unless PuppetX::Ipmi::Provider::UserLogic.needs_revoke?(entry)
      Puppet.debug("ipmi_user #{user_name}: slot #{id} is disabled with no privilege on any channel, leaving it alone")
      return false
    end

    revoke_access!(id, table_channels, already_disabled: !entry.nil? && entry[:status] != :enabled)
    true
  end

  # Revoke the slot (see revoke_unless_disabled) so that renaming it retires
  # its account.  An accepted revoke proves the account is shut out only
  # when the BMC reported it enabled: refusals on any other account are
  # tolerated, a BMC may ignore permission changes on a disabled account,
  # and one that reports no Enable Status may have no way to disable it.  So
  # any other revoked slot is read again, and must grant no privilege on any
  # channel, including every channel revoked; one the read misses counts as
  # granting.  Otherwise this raises before the rename, and the slot keeps
  # its name, so the next run tries again.
  #
  # @param id [Integer]
  # @param entry [Hash, nil] the slot's table entry
  # @return [void]
  def revoke_before_rename(id, entry)
    reported = entry&.fetch(:status)
    revoked = table_channels
    return unless revoke_unless_disabled(id, entry) && reported != :enabled

    refresh_slots!
    fresh = slots.find { |u| u[:id] == id }
    raise Puppet::Error, "Refusing to rename slot #{id}: it is missing from the BMC's user table, so its revoke cannot be confirmed" if fresh.nil?

    granted = (fresh[:privs].keys | revoked).to_h { |c| [c, fresh[:privs][c]] }.select { |_, priv| PuppetX::Ipmi::Provider::UserLogic.grants?(priv) }
    return if granted.empty?

    held = granted.map { |c, p| "priv #{p || 'unread'} on channel #{c}" }.join(', ')
    raise Puppet::Error, "Refusing to rename slot #{id}: the BMC did not revoke its access, it still has #{held}"
  end

  # Enable the resolved slot with the configured username, password,
  # privilege and channel access.
  #
  # A slot is never renamed while another account in it has access: it is
  # revoked and disabled first (see revoke_before_rename).  Every value is
  # checked before the first write, so one the backend cannot write changes
  # nothing.  If a later write fails, the slot is left disabled.
  #
  # The name write is skipped when the slot already holds the target name:
  # some firmwares invalidate sessions on rename even when the value is
  # unchanged.  The password write is skipped when this run found it in
  # sync or already wrote it.
  #
  # @return [void]
  def enable_user!
    id = resolved_user_id
    rename = takeover?
    pw = real_password
    pw = nil if pw&.empty? || @password_synced
    self.class.check_name(channel, id, user_name) if rename
    self.class.check_password(channel, id, pw) if pw

    revoke_before_rename(id, slot_entry) if rename
    write_name!(id, user_name) if rename
    write_password!(id, pw) if pw
    grant_access!(id, @resource[:priv] || 4)
  end

  # Disable the resolved slot by removing privileges and channel access,
  # then name it, so the disabled resource reserves the requested username
  # there: an explicit `user_id` takes over a slot held by another name,
  # and an auto slot that was free (empty or `DISABLED_*`) is claimed.  The
  # slot is renamed only once its access is revoked.
  #
  # @return [void]
  def disable_user!
    id = resolved_user_id
    rename = takeover?
    self.class.check_name(channel, id, user_name) if rename

    if rename
      revoke_before_rename(id, slot_entry)
      write_name!(id, user_name)
    else
      revoke_unless_disabled(id, slot_entry)
    end
  end
end
