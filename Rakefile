require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-syntax/tasks/puppet-syntax'
require 'puppet-lint/tasks/puppet-lint'

PuppetLint.configuration.send("disable_80chars")
PuppetLint.configuration.send("disable_class_inherits_from_params_class")
PuppetLint.configuration.ignore_paths = ['pkg/**/*.pp', 'spec/**/*.pp', 'tests/**/*.pp']
PuppetSyntax.exclude_paths = ['spec/fixtures/**/*']

PuppetLint::RakeTask.new :lint do |config|
  config.pattern          = 'manifests/**/*.pp'
  config.fail_on_warnings = true
end

task :default => [
  :validate,
  :lint,
  :spec,
]
