# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_user'

# Puppet calls `generate` on every resource before it applies any, so the
# purge_duplicates lookup runs before ipmitool can have been installed by
# the same run.  It must not fail the run when the BMC cannot be read yet.
describe 'ipmi_user purge_duplicates before the BMC can be read' do
  let(:tmp) { Dir.mktmpdir }
  let(:messages) { [] }
  let(:bmc) { FakeIpmitoolUsers.new([[2, 'ADMIN', 'ADMINISTRATOR'], [3, '', 'NO ACCESS']], reachable: reachable) }
  let(:reachable) { true }

  # PATH holds only an empty directory, so no IPMI tool is installed.
  around do |example|
    old = ENV.fetch('PATH', nil)
    Dir.mkdir(bin_dir)
    ENV['PATH'] = bin_dir
    example.run
  ensure
    ENV['PATH'] = old
  end

  before do
    Puppet[:statedir] = tmp
    Puppet::Util::Log.newdestination(Puppet::Test::LogCollector.new(messages))
  end

  after do
    bmc.cleanup
    FileUtils.rm_rf(tmp)
  end

  def bin_dir
    File.join(tmp, 'bin')
  end

  def user(**params)
    Puppet::Type.type(:ipmi_user).new({ name: 'bob', password: 'secret', user_id: 3, channel: 1, purge_duplicates: true }.merge(params))
  end

  def apply(*resources)
    catalog = Puppet::Resource::Catalog.new
    resources.each { |r| catalog.add_resource(r) }
    report = catalog.apply.report
    report.finalize_report
    report
  end

  def logged(level, pattern)
    messages.select { |m| m.level == level && m.message.match?(pattern) }
  end

  shared_examples 'a run that generate does not fail' do
    it 'does not report a generate failure' do
      expect(report.resources_failed_to_generate).to be_falsey
      expect(messages.map(&:message).grep(%r{Failed to generate additional resources})).to be_empty
    end
  end

  context 'when no provider is suitable' do
    let(:report) do
      Puppet::Type.type(:ipmi_user).stubs(:defaultprovider).returns(nil)
      apply(user)
    end

    it_behaves_like 'a run that generate does not fail'

    it 'defers the purge with a notice' do
      report
      expect(logged(:notice, %r{purge_duplicates is deferred})).not_to be_empty
    end
  end

  context 'when ipmitool is installed later in the same run' do
    let(:report) do
      install = Puppet::Type.type(:file).new(path: File.join(bin_dir, 'ipmitool'), content: File.read(bmc.executable), mode: '0755')
      apply(user(provider: 'ipmitool'), install)
    end

    it_behaves_like 'a run that generate does not fail'

    it 'applies the user, defers the purge with a notice and reports the run as changed' do
      expect(report.resource_statuses['Ipmi_user[bob]'].changed).to be(true)
      expect(logged(:notice, %r{purge_duplicates is deferred})).not_to be_empty
      expect(report.status).to eq('changed')
    end
  end

  context 'when the BMC cannot be read' do
    let(:reachable) { false }
    let(:report) do
      bmc.activate
      apply(user(provider: 'ipmitool'))
    end

    it_behaves_like 'a run that generate does not fail'

    it 'skips the purge with a warning' do
      report
      expect(logged(:warning, %r{purge_duplicates is skipped.*Unable to establish})).not_to be_empty
    end
  end
end
