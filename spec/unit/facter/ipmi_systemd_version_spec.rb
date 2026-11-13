# frozen_string_literal: true

require 'spec_helper'
require 'facter'

describe 'ipmi_systemd_version', type: :fact do
  subject(:fact) { Facter.fact(:ipmi_systemd_version) }

  before do
    Facter.clear
    Facter.fact(:kernel).stubs(:value).returns('Linux')
    Facter::Core::Execution.stubs(:execute).returns('')
  end

  context 'when systemd is the init system' do
    before do
      File.stubs(:exist?).with('/run/systemd/system').returns(true)
      Facter::Core::Execution.stubs(:execute).with('systemctl --version', on_fail: '')
                             .returns("systemd 252 (252-46.el9_5.2)\n+PAM +AUDIT +SELINUX\n")
    end

    it { expect(fact.value).to eq('252') }
  end

  context 'when systemctl prints no version' do
    before do
      File.stubs(:exist?).with('/run/systemd/system').returns(true)
      Facter::Core::Execution.stubs(:execute).with('systemctl --version', on_fail: '').returns('')
    end

    it { expect(fact.value).to be_nil }
  end

  context 'when systemd is not the init system' do
    before do
      File.stubs(:exist?).with('/run/systemd/system').returns(false)
      Facter::Core::Execution.expects(:execute).with('systemctl --version', on_fail: '').never
    end

    it { expect(fact.value).to be_nil }
  end
end
