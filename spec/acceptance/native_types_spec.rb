# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'ipmi native types' do
  let(:manifest) do
    <<-PP
      include ipmi

      ipmi_user { 'acceptance_user':
        password         => Sensitive('acceptance_password'),
        user_id          => 4,
        channel          => 1,
        purge_duplicates => true,
      }

      ipmi_network { 'acceptance_network':
        type        => 'static',
        ip          => '192.0.2.10',
        netmask     => '255.255.255.0',
        gateway     => '192.0.2.1',
        lan_channel => 1,
      }

      ipmi_snmp { 'acceptance_snmp':
        community   => 'acceptance_snmp',
        lan_channel => 1,
      }
    PP
  end

  # Errors that mean a type or provider is broken, as opposed to a BMC that
  # can not be reached.  Puppet logs an exception's message, not its class,
  # so the Ruby errors are matched by both.
  let(:broken) do
    [
      'Could not find a suitable provider',
      'not functional on this host',
      'Failed to generate additional resources',
      'NameError',
      'NoMethodError',
      'undefined method',
      'undefined local variable or method',
      'uninitialized constant',
    ]
  end

  it 'evaluates every resource with a working provider' do
    # The SUT has no BMC, so each resource fails once its provider runs
    # ipmitool, and the user's purge_duplicates lookup, which runs before
    # anything is applied, is deferred with a notice or warning instead of
    # failing to generate.  Without catch_failures beaker omits --detailed-exitcodes and
    # accepts only exit 0, which `puppet apply` returns despite resource
    # failures, but not when the catalog fails to compile or its pre-run
    # checks fail.
    result = apply_manifest(manifest, catch_failures: false)
    # Facter reports its own NoMethodErrors when a system tool such as lscpu
    # is missing from the image; those say nothing about this module.
    output = (result.stdout + result.stderr).lines.grep_v(%r{Facter: }).join

    expect(output).to match(%r{Execution of '[^']*ipmitool })
    broken.each do |message|
      expect(output).not_to include(message)
    end
  end
end
