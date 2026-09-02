# frozen_string_literal: true

Puppet::Type.newtype(:ipmi_user) do
  @doc = <<-DOC
    @summary
      Manages BMC user accounts via IPMI.

    Supports both ipmitool and freeipmi backends.  Manages user name,
    password, privilege level, enabled state, SOL access, and channel
    access in an idempotent fashion.

    @example Create an admin user
      ipmi_user { 'admin_user':
        user     => 'admin',
        password => Sensitive('s3cret'),
        user_id  => 3,
        priv     => 4,
        channel  => 1,
        enable   => true,
      }

    @example Disable a user
      ipmi_user { 'old_user':
        user_id => 5,
        channel => 1,
        enable  => false,
      }

    @example Automatically select a user ID
      ipmi_user { 'auto_user':
        user     => 'admin',
        password => Sensitive('s3cret'),
        user_id  => 'auto',
        priv     => 4,
        channel  => 1,
      }
  DOC

  newparam(:name, namevar: true) do
    desc 'Resource title (arbitrary label for this user resource).'
  end

  newparam(:user) do
    desc 'The IPMI username to set.'
    defaultto 'root'
  end

  newparam(:user_id) do
    desc <<-DESC
      The numeric IPMI user slot ID, or 'auto' to let the provider select one.

      When set to 'auto', the provider first checks for an existing user with
      the requested username and reuses that ID.  Otherwise it selects the
      lowest unused ID reported by the BMC.  ID 1 is the anonymous slot and is
      never returned by 'auto'.

      On SuperMicro IPMI, user id 2 is reserved for the ADMIN username.
      On ASUS IPMI, user id 2 is reserved for the admin username.
    DESC
    defaultto 3
    validate do |value|
      str = value.to_s
      raise Puppet::Error, 'user_id must be a positive integer or "auto"' unless str == 'auto' || (str =~ %r{^\d+$} && value.to_i.positive?)
    end
    munge do |value|
      value.to_s == 'auto' ? :auto : value.to_i
    end
  end

  newparam(:password) do
    desc 'Password for the IPMI user. May be a Sensitive value. Required when enable is true.'
  end

  newparam(:channel) do
    desc <<-DESC
      The IPMI channel number for user access configuration.
      Defaults to 1.
    DESC
    defaultto 1
    validate do |value|
      raise Puppet::Error, 'channel must be a positive integer' unless value.to_s =~ %r{^\d+$}
    end
    munge(&:to_i)
  end

  newparam(:ipmitool_cmd) do
    desc 'Path to the ipmitool binary.'
    defaultto '/usr/bin/ipmitool'
    validate do |value|
      raise Puppet::Error, 'ipmitool_cmd must be an absolute path' unless value.start_with?('/')
    end
  end

  newparam(:bmcconfig_cmd) do
    desc 'Path to the bmc-config binary (freeipmi).'
    defaultto '/usr/sbin/bmc-config'
    validate do |value|
      raise Puppet::Error, 'bmcconfig_cmd must be an absolute path' unless value.start_with?('/')
    end
  end

  newparam(:purge_id_mismatch) do
    desc <<-DESC
      When true, any IPMI user slot that holds the given username at an ID
      other than user_id will be blanked and disabled before the desired
      slot is configured.  Only applies when enable is true.
    DESC
    newvalues(:true, :false)
    defaultto :false
  end

  newproperty(:enable) do
    desc 'Whether this user account should be enabled or disabled.'
    newvalues(:true, :false)
    defaultto :true
  end

  newproperty(:priv) do
    desc <<-DESC
      Privilege level for the user:
        4 - ADMINISTRATOR
        3 - OPERATOR
        2 - USER
        1 - CALLBACK
    DESC
    validate do |value|
      v = value.to_i
      raise Puppet::Error, "priv must be 1 (CALLBACK), 2 (USER), 3 (OPERATOR), or 4 (ADMINISTRATOR), got #{value}" unless [1, 2, 3, 4].include?(v)
    end
    munge(&:to_i)
    defaultto 4

    def insync?(is)
      # When disabling, privilege gets set to NO ACCESS (0xF / 15)
      # so we skip the priv check when enable is false
      return true if @resource[:enable] == :false

      is.to_i == should.to_i
    end
  end

  # Validate the resource parameters
  validate do
    if self[:enable] == :true
      pw = self[:password]
      raise Puppet::Error, "You must supply a password to enable #{self[:user]} with ipmi_user" if pw.nil? || (pw.respond_to?(:empty?) && pw.empty?)

      real_pw = pw.is_a?(Puppet::Pops::Types::PSensitiveType::Sensitive) ? pw.unwrap : pw
      raise Puppet::Error, 'IPMI v2 restricts passwords to 20 or fewer characters' if real_pw.length > 20
    end
  end
end
