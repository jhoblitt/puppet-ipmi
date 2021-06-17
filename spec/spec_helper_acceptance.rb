require 'beaker-rspec'
require 'beaker-puppet'
require 'beaker/puppet_install_helper'
require 'beaker/module_install_helper'

run_puppet_install_helper unless ENV['BEAKER_provision'] == 'no'

UNSUPPORTED_PLATFORMS = %w[Suse windows AIX Solaris].freeze

RSpec.configure do |c|
  # Readable test descriptions
  c.formatter = :documentation

  # Configure all nodes in nodeset
  c.before :suite do
    install_module_on(hosts)
    install_module_dependencies_on(hosts)
    install_module_from_forge('stahnma-epel', '> 1.0.0 < 2.0.0')
  end
end
