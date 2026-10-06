# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'ipmi native types' do
  let(:manifest) do
    <<-PP
      include ipmi

      ipmi_user { 'acceptance_user':
        password => Sensitive('acceptance_password'),
        user_id  => 4,
        channel  => 1,
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

  it 'compiles and applies the manifest' do
    # BMC commands will fail when no BMC is present; only verify that the
    # catalog compiles and the resources are declared.
    apply_manifest(manifest, catch_failures: false)
  end
end
