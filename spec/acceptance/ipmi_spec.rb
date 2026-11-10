# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'ipmi class' do
  case fact('os.family')
  when 'RedHat'
    packages = %w[
      OpenIPMI
      ipmitool
    ]
  when 'Debian'
    packages = %w[
      openipmi
      ipmitool
    ]
  end

  describe 'running puppet code' do
    let(:manifest) do
      <<-PP
        include ipmi
      PP
    end

    it 'applies the manifest' do
      # ipmi service startup will fail because there's no bmc
      apply_manifest(manifest, catch_failures: false)
    end

    packages.each do |pkg|
      describe package(pkg) do
        it { is_expected.to be_installed }
      end
    end
  end
end
