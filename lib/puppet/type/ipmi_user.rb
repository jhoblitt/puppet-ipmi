# frozen_string_literal: true

require 'puppet/parameter/boolean'
require 'puppet_x/ipmi/lan_channel'
require 'puppet_x/ipmi/user_catalog'

Puppet::Type.newtype(:ipmi_user) do
  @doc = <<-DOC
    @summary
      Manages BMC user accounts via IPMI.

    Supports both ipmitool and freeipmi backends.  Manages user name,
    password, privilege level, enabled state, SOL access, and channel
    access in an idempotent fashion.

    The resource title is used as the IPMI username unless the `username`
    property is given explicitly.  `user_id` defaults to `'auto'`, which
    lets the provider select a slot.

    @example Create an admin user
      ipmi_user { 'admin':
        password => Sensitive('s3cret'),
        priv     => 4,
        channel  => 1,
        enable   => true,
      }

    @example Disable a user
      ipmi_user { 'old_user':
        user_id  => 5,
        channel  => 1,
        enable   => false,
      }

    @example Reserve a user ID with a name but no access
      ipmi_user { 'reserved_operator':
        username => 'OPERATOR',
        user_id  => 5,
        channel  => 1,
        enable   => false,
      }

    @example Automatically select a user ID
      ipmi_user { 'auto_user':
        password => Sensitive('s3cret'),
        priv     => 4,
        channel  => 1,
      }

    @example Use a different resource title than username
      ipmi_user { 'admin_account':
        username => 'admin',
        password => Sensitive('s3cret'),
        user_id  => 3,
        priv     => 4,
        channel  => 1,
      }
  DOC

  ensurable do
    desc <<-DESC
      Whether the user exists.  IPMI cannot delete a user slot, so `absent`
      first removes privilege, channel and SOL access on every LAN channel
      and disables the account, unless the BMC reports it disabled and no
      LAN channel grants it a privilege, and then renames the slot to
      `DISABLED_<id>`; the slot is then treated as free.  BMCs do not allow
      permission changes on a disabled account, so unless the BMC reports
      the account enabled, a refused change is tolerated, but disabling it
      must succeed.

      User slots are shared by every channel.  An absent resource for the
      same username as a present one, on any channel, must name a
      different, explicit `user_id`; one that is `auto` or names the present
      resource's slot is rejected before the run.  An `auto` user does not
      keep a slot that such an absent resource names: it moves to another
      slot holding its username, or a free one.  An absent resource whose
      slot a present resource is given once the BMC's user table is read
      (such as a slot an explicit `user_id` takes over from its username)
      fails instead of removing it.
    DESC
    defaultto :present

    newvalue(:present) { provider.create }
    newvalue(:absent) { provider.destroy }
  end

  newparam(:name, namevar: true) do
    desc 'Resource title.  Used as the IPMI username when `username` is not set.'
  end

  newparam(:user_id) do
    desc <<-DESC
      The numeric IPMI user slot ID (2-63), or 'auto' to let the provider select one.

      An explicit ID may be occupied: declaring a user with a different
      username at that ID replaces/renames the account. The old account's
      access is revoked on every LAN channel and it is disabled before the
      slot is renamed, unless the BMC reports it disabled with no privilege
      on any LAN channel, and a username or password the backend cannot
      write is refused before anything is written. An enabled user then gets its password and
      access; a disabled one stays disabled, which reserves the new name in
      that slot. Check the target slot and retain alternate BMC access before
      applying. When moving the same username to a different slot, use
      `purge_duplicates => true` to revoke and rename its old slot; otherwise
      the old slot can remain enabled. `auto` never allocates a slot occupied
      by another username.  Two present resources with different usernames
      may not name the same ID, and two present resources with the same
      username may not name different IDs, even on different channels.

      With 'auto' the slot is chosen from the BMC's current user table and
      the whole catalog, so it does not depend on resource evaluation order.
      Slots and names are BMC-wide, so resources on every channel, and of
      every provider, are allocated together, and one username gets one
      slot on all of them:
      explicit `user_id` values are reserved first, an 'auto' username that
      an explicit resource also declares takes that slot, a user that
      already holds a slot keeps it (the lowest id if several that no
      explicit `user_id`, present or absent, names), and remaining 'auto'
      resources take the lowest free slots in title order.  A slot is free when its id is 2 or
      more, its name is empty or `DISABLED_*`, the BMC does not report it
      enabled, and no LAN channel grants it a privilege.  ID 1 is the
      anonymous slot and is never allocated.  A resource that finds no free
      slot fails on its own; the others still apply.

      On SuperMicro IPMI, user id 2 is reserved for the ADMIN username.
      On ASUS IPMI, user id 2 is reserved for the admin username.
    DESC
    defaultto 'auto'
    validate do |value|
      str = value.to_s
      raise Puppet::Error, 'user_id must be an integer between 2 and 63 or "auto"' unless str == 'auto' || (str =~ %r{^\d+$} && (2..63).cover?(value.to_i))
    end
    munge do |value|
      next :auto if value.to_s == 'auto'

      value.to_i
    end
  end

  newparam(:channel) do
    desc <<-DESC
      The IPMI channel number for user access configuration.

      Defaults to 1 when declared directly. The ipmi class can inject the
      node's ipmi.default.channel fact (or ipmi::default_channel).

      A user slot's name, password and enabled state are shared by every
      channel; only its privilege and access are per channel.  So the BMC's
      user table is read across all of its LAN channels, and every channel a
      resource names.  Resources for one username on several channels are
      one account: they must agree on `enable` and `password` (one may leave
      the password out), and only `priv` may differ; a catalog where they
      disagree is rejected.
    DESC
    defaultto do
      PuppetX::Ipmi::LanChannel.default_channel(nil)
    end
    PuppetX::Ipmi::LanChannel.channel_number(self, 'channel')
  end

  newparam(:username) do
    desc <<-DESC
      The IPMI username.  Defaults to the resource title.

      At most 16 bytes, without whitespace, and not starting with `-`: the
      name goes on ipmitool's command line, where its option parser would
      take it as an option.
    DESC
    defaultto do
      @resource[:name]
    end
    validate do |value|
      str = value.to_s
      raise Puppet::Error, 'username must be a non-empty string' if str.empty?
      raise Puppet::Error, 'username must be 16 bytes or fewer' if str.bytesize > 16
      raise Puppet::Error, 'username must not contain whitespace' if str =~ %r{\s}
      raise Puppet::Error, 'username must not start with -, which ipmitool would take as an option' if str.start_with?('-')
    end
  end

  newproperty(:password) do
    desc <<-DESC
      Password for the IPMI user. A String or Sensitive[String], at most 20 bytes. Required when enable is true.

      The password is never put on a command line.  It must not contain a
      newline or a NUL byte.  With ipmitool, a password of 17 to 20 bytes
      also must not contain `#`, a tab, both kinds of quote, or `~` together
      with a space or quote.  With freeipmi it also must not contain
      whitespace.

      A password of 17 to 20 bytes is stored in the IPMI 2.0 20-byte form,
      which the BMC must support.  freeipmi writes it, like a shorter one,
      through bmc-config's `Password` key.
    DESC

    sensitive true

    validate do |value|
      real = PuppetX::Ipmi.unwrap(value)
      raise Puppet::Error, 'password must be a String or Sensitive[String]' unless real.is_a?(String)
      raise Puppet::Error, 'IPMI v2 restricts passwords to 20 or fewer bytes' if real.bytesize > 20
    end

    def insync?(_is)
      return true if should.nil?

      @resource.provider.password_insync?
    end
  end

  newproperty(:priv) do
    desc <<-DESC
      Privilege level for the user:
        4 - ADMINISTRATOR
        3 - OPERATOR
        2 - USER
        1 - CALLBACK
    DESC
    munge(&:to_i)
    defaultto 4

    def insync?(is)
      # When disabling, privilege gets set to NO ACCESS (0xF / 15)
      # so we skip the priv check when enable is false
      return true if @resource[:enable] == :false

      is.to_i == should.to_i
    end
  end

  newproperty(:enable) do
    desc <<-DESC
      Whether this user account should be enabled or disabled.  `false`
      revokes privilege, channel and SOL access on every LAN channel, then
      disables the account.  It is in sync once the BMC reports the account
      disabled, or, when the BMC does not report it, once no LAN channel
      grants it a privilege.
    DESC
    newvalues(:true, :false)
    defaultto :true

    # Disabling is only complete once the slot has NO ACCESS, which the
    # enabled flag alone does not tell us.
    def insync?(is)
      return provider.access_revoked? if [should].flatten.include?(:false)

      super
    end
  end

  newparam(:purge_duplicates, boolean: true, parent: Puppet::Parameter::Boolean) do
    desc <<-DESC
      Also remove other slots that hold this username.

      A user normally lives in one slot.  When the same username appears in
      another slot (for example after the slot changed from one `user_id` to
      another) the extra slot is blanked and disabled.  Each duplicate is
      reported as its own generated `ipmi_user` resource with
      `ensure => absent`, applied before this resource, so it honours
      `--noop` and is idempotent.

      Slots managed by other resources in the catalog, and the anonymous
      slot 1, are never purged.

      Duplicates are looked up before Puppet applies anything.  When no
      IPMI tool is installed yet, or the BMC cannot be read, the purge is
      skipped with a notice or warning and happens on a later run.
    DESC
    defaultto false
  end

  # Validate the resource parameters
  validate do
    # Absent resources never reach the provider, so their other parameters
    # are not meaningful; skip validation entirely for them.
    return if self[:ensure] == :absent

    # priv range is validated for every present resource, even a disabled
    # one: an out-of-range value is never meaningful, and catching it here
    # prevents it from silently reaching the provider.
    priv = self[:priv]
    raise Puppet::Error, "priv must be 1 (CALLBACK), 2 (USER), 3 (OPERATOR), or 4 (ADMINISTRATOR), got #{priv}" unless [1, 2, 3, 4].include?(priv)

    return unless self[:enable] == :true

    real_pw = PuppetX::Ipmi.unwrap(self[:password])
    raise Puppet::Error, "You must supply a password to enable #{self[:username]} with ipmi_user" if real_pw.nil? || real_pw == ''
  end

  # Purge duplicates before this resource runs: some BMCs refuse to give a
  # name to a slot while another slot still holds it.
  def depthfirst?
    true
  end

  # Emit one `ensure => absent` resource per duplicate slot.
  def generate
    PuppetX::Ipmi::UserCatalog.duplicate_resources(self)
  end

  # Reject catalogs where two live resources claim the same username or slot,
  # or an absent resource would remove a live one's slot.
  def pre_run_check
    PuppetX::Ipmi::UserCatalog.check_unique!(self)
  end
end
