source 'https://rubygems.org'

if puppetversion = ENV['PUPPET_GEM_VERSION']
  gem 'puppet', puppetversion, :require => false
else
  gem 'puppet', :require => false
end

if facterversion = ENV['FACTER_GEM_VERSION']
  gem 'facter', facterversion, :require => false
else
  gem 'facter', :require => false
end

group :development, :test do
  gem 'rake',                     :require => false
  gem 'rspec', '~> 3.2',          :require => false
  gem 'puppetlabs_spec_helper',   :require => false
  gem 'puppet-lint', '~> 1.1',    :require => false
  gem 'puppet-syntax',            :require => false
  gem 'rspec-puppet', '~> 2.2',   :require => false
  gem 'metadata-json-lint',       :require => false
  gem 'travis', '~> 1.8',         :require => false
end

group :beaker do
  gem 'winrm',                              :require => false
  if beaker_version = ENV['BEAKER_VERSION']
    gem 'beaker', *location_for(beaker_version)
  else
    gem 'beaker', '>= 4.2.0', :require => false
  end
  if beaker_rspec_version = ENV['BEAKER_RSPEC_VERSION']
    gem 'beaker-rspec', *location_for(beaker_rspec_version)
  else
    gem 'beaker-rspec',  :require => false
  end
  gem 'serverspec',                         :require => false
  gem 'beaker-hostgenerator', '>= 1.1.22',  :require => false
  gem 'beaker-docker',                      :require => false
  gem 'beaker-puppet',                      :require => false
  gem 'beaker-puppet_install_helper',       :require => false
  gem 'beaker-module_install_helper',       :require => false
  gem 'rbnacl', '>= 4',                     :require => false if RUBY_VERSION >= '2.2.6'
  gem 'rbnacl-libsodium',                   :require => false if RUBY_VERSION >= '2.2.6'
  gem 'bcrypt_pbkdf',                       :require => false
end

group :release do
  gem 'puppet-blacksmith', :require => false
end

# vim:ft=ruby
