require 'spec_helper_acceptance'

describe 'ipmi class' do

  package_name = nil
  case fact('os.release.major')
  when '5'
    package_name = ['OpenIPMI', 'OpenIPMI-tools']
  when '6', '7'
    package_name = ['OpenIPMI', 'ipmitool']
  end

  describe 'running puppet code' do
    pp = <<-EOS
      if $::osfamily == 'RedHat' {
        class { 'epel': } -> Class['ipmi']
      }

      include ::ipmi
    EOS

    it 'applies the manifest' do
      # ipmi service startup will fail because there's no bmc
      apply_manifest(pp, :catch_failures => false)
    end

    package_name.each do |pkg|
      describe package(pkg) do
        it { should be_installed }
      end
    end
  end
end
