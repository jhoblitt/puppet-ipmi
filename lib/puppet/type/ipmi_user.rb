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
      first removes channel and SOL access (only while the account is still
      enabled, because BMCs do not allow permission changes on a disabled
      account) and then renames the slot to `DISABLED_<id>`; the slot is then
      treated as free.
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

      An explicit ID may be occupied: declaring an enabled user with a different
      username at that ID replaces/renames the account and configures its password
      and access. Check the target slot and retain alternate BMC access before
      applying. When moving the same username to a different slot, use
      `purge_duplicates => true` to revoke and rename its old slot; otherwise
      the old slot can remain enabled. `auto` never allocates a slot occupied
      by another username.

      With 'auto' the slot is chosen from the BMC's current user table and
      the whole catalog, so it does not depend on resource evaluation order:
      explicit `user_id` values are reserved first, a user that already holds
      a slot keeps it (lowest id if several), and remaining 'auto' resources
      take the lowest free slots in title order.  A slot is free when its id
      is 2 or more and its name is empty or `DISABLED_*`.  ID 1 is the
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
    DESC
    defaultto do
      PuppetX::Ipmi::LanChannel.default_channel(nil)
    end
    validate do |value|
      raise Puppet::Error, 'channel must be an integer between 1 and 15' unless value.to_s =~ %r{^[1-9]$|^1[0-5]$}
    end
    munge(&:to_i)
  end

  newparam(:username) do
    desc 'The IPMI username.  Defaults to the resource title.'
    defaultto do
      @resource[:name]
    end
    validate do |value|
      str = value.to_s
      raise Puppet::Error, 'username must be a non-empty string' if str.empty?
      raise Puppet::Error, 'username must be 16 bytes or fewer' if str.bytesize > 16
      raise Puppet::Error, 'username must not contain whitespace' if str =~ %r{\s}
    end
  end

  newproperty(:password) do
    desc 'Password for the IPMI user. A String or Sensitive[String], at most 20 bytes. Required when enable is true.'

    sensitive true

    validate do |value|
      real = value.respond_to?(:unwrap) ? value.unwrap : value
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
    desc 'Whether this user account should be enabled or disabled.'
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

    real_pw = self[:password].respond_to?(:unwrap) ? self[:password].unwrap : self[:password]
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

  # Reject catalogs where two live resources claim the same username or slot.
  def pre_run_check
    PuppetX::Ipmi::UserCatalog.check_unique!(self)
  end
end
