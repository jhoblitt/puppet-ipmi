# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi', type: :class do
  def modprobe_conf
    '/etc/modprobe.d/50-ipmi-watchdog.conf'
  end

  def modules_load_conf
    '/etc/modules-load.d/50-ipmi-watchdog.conf'
  end

  def dropin
    '/etc/systemd/system.conf.d/50-ipmi-watchdog.conf'
  end

  def modprobe_exec
    'ipmi::watchdog modprobe ipmi_watchdog'
  end

  def reexec
    'ipmi::watchdog systemctl daemon-reexec'
  end

  # The parameters puppet/systemd's systemd::system::dropin_file passes when
  # it declares the drop-in directory with its defaults.
  def dropin_dir_params
    <<~PUPPET
      {
        ensure                  => 'directory',
        owner                   => 'root',
        group                   => 'root',
        mode                    => '0755',
        recurse                 => false,
        purge                   => false,
        selinux_ignore_defaults => false,
      }
    PUPPET
  end

  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) do
        facts.merge(
          {
            ipmitool: { mc_info: { IPMI_Puppet_Service_Recommend: 'running' } },
            ipmi: { default: { channel: 1 } },
          },
        )
      end

      case facts[:os]['family']
      when 'RedHat'
        let(:config_file) { '/etc/sysconfig/ipmi' }
      when 'Debian'
        let(:config_file) { '/etc/default/ipmi' }
      end

      context 'with defaults' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('ipmi::watchdog') }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi').with(enable: false) }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi::watchdog_param').with(enable: false) }
        it { is_expected.to contain_augeas('ipmi_watchdog').with(changes: ['set IPMI_WATCHDOG no']) }
        it { is_expected.to contain_file(modprobe_conf).with_ensure('absent') }
        it { is_expected.to contain_file(modules_load_conf).with_ensure('absent') }
        it { is_expected.to contain_file(dropin).with_ensure('absent') }
        it { is_expected.not_to contain_exec(modprobe_exec) }
        it { is_expected.not_to contain_class('kmod') }
        it { is_expected.not_to contain_class('systemd') }
      end

      context 'with watchdog => true' do
        let(:params) { { watchdog: true } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi').with(enable: true) }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi::watchdog_param').with(enable: true) }

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: ['set IPMI_WATCHDOG yes'],
          )
        end

        it { is_expected.not_to contain_class('kmod') }
        it { is_expected.not_to contain_class('systemd') }
      end

      context 'when OpenIPMI owns the device' do
        context 'with watchdog => true' do
          let(:params) { { watchdog: true, watchdog_supervisor: 'openipmi' } }

          it 'leaves loading the module to the OpenIPMI service' do
            is_expected.to contain_file(modprobe_conf).with_ensure('absent')
            is_expected.to contain_file(modules_load_conf).with_ensure('absent')
            is_expected.not_to contain_exec(modprobe_exec)
          end

          it 'keeps the package IPMI_WATCHDOG_OPTIONS when nothing is configured' do
            is_expected.to contain_augeas('ipmi_watchdog').with_changes(['set IPMI_WATCHDOG yes'])
          end
        end

        context 'with watchdog_timeout and watchdog_module_options' do
          let(:params) do
            {
              watchdog: true,
              watchdog_supervisor: 'openipmi',
              watchdog_timeout: 30,
              watchdog_module_options: { 'action' => 'power_cycle' },
            }
          end

          it { is_expected.to contain_file(modprobe_conf).with_ensure('absent') }

          it 'passes them as IPMI_WATCHDOG_OPTIONS' do
            is_expected.to contain_augeas('ipmi_watchdog').with(
              context: "/files#{config_file}",
              changes: [
                'set IPMI_WATCHDOG yes',
                %(set IPMI_WATCHDOG_OPTIONS '"timeout=30 action=power_cycle"'),
              ],
            )
          end
        end

        context 'with watchdog_manage_module => false' do
          let(:params) do
            { watchdog: true, watchdog_supervisor: 'openipmi', watchdog_manage_module: false, watchdog_timeout: 30 }
          end

          it do
            is_expected.to contain_augeas('ipmi_watchdog').with_changes(
              ['set IPMI_WATCHDOG yes', %(set IPMI_WATCHDOG_OPTIONS '"timeout=30"')],
            )
          end
        end

        context 'with watchdog => false and module options set' do
          let(:params) { { watchdog: false, watchdog_supervisor: 'openipmi', watchdog_timeout: 30 } }

          it { is_expected.to contain_augeas('ipmi_watchdog').with_changes(['set IPMI_WATCHDOG no']) }
        end

        context 'with a conflicting timeout in watchdog_module_options' do
          let(:params) do
            {
              watchdog: true,
              watchdog_supervisor: 'openipmi',
              watchdog_timeout: 30,
              watchdog_module_options: { 'timeout' => 45 },
            }
          end

          it { is_expected.to compile.and_raise_error(%r{conflicts with ipmi::watchdog_timeout}) }
        end
      end

      context 'with a watchdog_module_options value a shell would split' do
        let(:params) { { watchdog: true, watchdog_module_options: { 'action' => 'power_cycle $(reboot)' } } }

        it { is_expected.to compile.and_raise_error(%r{watchdog_module_options}) }
      end

      context 'with a watchdog_module_options key that is not a parameter name' do
        let(:params) { { watchdog: true, watchdog_module_options: { 'Action Now' => 'reset' } } }

        it { is_expected.to compile.and_raise_error(%r{watchdog_module_options}) }
      end

      context 'when systemd owns the device' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }

        context 'with watchdog => true' do
          let(:params) { { watchdog: true } }

          it { is_expected.to contain_class('ipmi::watchdog::kmod') }

          it do
            is_expected.to contain_file(modules_load_conf).with(
              ensure: 'file',
              owner: 'root',
              group: 'root',
              mode: '0644',
              content: %r{^ipmi_watchdog$},
            )
          end

          it { is_expected.to contain_file(modprobe_conf).with_ensure('absent') }

          it do
            is_expected.to contain_exec(modprobe_exec).with(
              command: 'modprobe ipmi_watchdog',
              unless: "grep -q '^ipmi_watchdog ' /proc/modules",
            ).that_requires("File[#{modprobe_conf}]")
          end

          it 'leaves IPMI_WATCHDOG_OPTIONS alone' do
            is_expected.to contain_augeas('ipmi_watchdog').with_changes(['set IPMI_WATCHDOG no'])
          end
        end

        context 'with watchdog_timeout => 0' do
          let(:params) { { watchdog: true, watchdog_timeout: 0 } }

          it { is_expected.to contain_file(modprobe_conf).with_ensure('absent') }
        end

        context 'with watchdog_timeout' do
          let(:params) { { watchdog: true, watchdog_timeout: 30 } }

          it do
            is_expected.to contain_file(modprobe_conf).with(
              ensure: 'file',
              owner: 'root',
              group: 'root',
              mode: '0644',
              content: %r{^options ipmi_watchdog timeout=30$},
            )
          end

          it { is_expected.to contain_augeas('ipmi_watchdog').with_changes(['set IPMI_WATCHDOG no']) }
        end

        context 'with extra watchdog_module_options' do
          let(:params) do
            { watchdog: true, watchdog_timeout: 30, watchdog_module_options: { 'action' => 'power_cycle' } }
          end

          it { is_expected.to contain_file(modprobe_conf).with_content(%r{^options ipmi_watchdog timeout=30 action=power_cycle$}) }
        end

        context 'with a conflicting timeout in watchdog_module_options' do
          let(:params) do
            { watchdog: true, watchdog_timeout: 30, watchdog_module_options: { 'timeout' => 45 } }
          end

          it { is_expected.to compile.and_raise_error(%r{conflicts with ipmi::watchdog_timeout}) }
        end

        [30, 30.0, '30', '30.0'].each do |value|
          context "with a matching timeout #{value.inspect} in watchdog_module_options" do
            let(:params) do
              {
                watchdog: true,
                watchdog_timeout: 30,
                watchdog_module_options: { 'action' => 'reset', 'timeout' => value },
              }
            end

            it { is_expected.to contain_file(modprobe_conf).with_content(%r{^options ipmi_watchdog timeout=30 action=reset$}) }
          end
        end

        [30.5, '30.5', '45', 'thirty'].each do |value|
          context "with a mismatching timeout #{value.inspect} in watchdog_module_options" do
            let(:params) do
              { watchdog: true, watchdog_timeout: 30, watchdog_module_options: { 'timeout' => value } }
            end

            it { is_expected.to compile.and_raise_error(%r{conflicts with ipmi::watchdog_timeout}) }
          end
        end

        context 'with timeout only in watchdog_module_options' do
          let(:params) { { watchdog: true, watchdog_module_options: { 'timeout' => 45 } } }

          it { is_expected.to contain_file(modprobe_conf).with_content(%r{^options ipmi_watchdog timeout=45$}) }
        end

        context 'with watchdog_manage_module => false' do
          let(:params) { { watchdog: true, watchdog_manage_module: false, watchdog_timeout: 30 } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_file(modprobe_conf).with_ensure('absent') }
          it { is_expected.to contain_file(modules_load_conf).with_ensure('absent') }
          it { is_expected.not_to contain_exec(modprobe_exec) }
        end

        context 'with watchdog => false and module options set' do
          let(:params) { { watchdog: false, watchdog_timeout: 30 } }

          it { is_expected.to contain_file(modprobe_conf).with_ensure('absent') }
          it { is_expected.to contain_file(modules_load_conf).with_ensure('absent') }
          it { is_expected.not_to contain_exec(modprobe_exec) }
        end
      end

      context 'when the site loads ipmi_watchdog itself, as puppet/kmod does' do
        let(:pre_condition) do
          <<~PUPPET
            file { '/etc/modules-load.d/ipmi_watchdog.conf':
              ensure  => file,
              content => "ipmi_watchdog\\n",
            }
            file { '/etc/modprobe.d/ipmi_watchdog.conf':
              ensure  => file,
              content => "options ipmi_watchdog timeout=60\\n",
            }
            exec { 'modprobe ipmi_watchdog':
              path   => '/bin:/sbin:/usr/bin:/usr/sbin',
              unless => "grep -qE '^ipmi_watchdog ' /proc/modules",
            }
          PUPPET
        end
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_timeout: 30 } }

        it { is_expected.to compile.with_all_deps }
      end

      context 'when the site declares the drop-in directory like puppet/systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_timeout: 30 } }

        context 'before ipmi' do
          let(:pre_condition) { "ensure_resource('file', '/etc/systemd/system.conf.d', #{dropin_dir_params})" }

          it { is_expected.to compile.with_all_deps }
        end

        context 'after ipmi' do
          let(:post_condition) { "ensure_resource('file', '/etc/systemd/system.conf.d', #{dropin_dir_params})" }

          it { is_expected.to compile.with_all_deps }
        end
      end

      context 'refresh relationships' do
        it { is_expected.to contain_class('ipmi::watchdog').that_requires('Class[ipmi::install]') }
        it { is_expected.not_to contain_class('ipmi::watchdog').that_subscribes_to('Class[ipmi::install]') }
        it { is_expected.not_to contain_class('ipmi::config') }

        context 'when systemd owns the device' do
          let(:facts) { super().merge(ipmi_systemd_version: '257') }
          let(:params) { { watchdog: true, watchdog_timeout: 30 } }

          it 'does not re-execute PID 1 when a package is installed' do
            is_expected.to contain_exec(reexec)
            is_expected.not_to contain_exec(reexec).that_subscribes_to('Class[ipmi::install]')
          end

          it 'does not restart the services when a watchdog file changes' do
            [modprobe_conf, modules_load_conf, dropin].each do |path|
              is_expected.to contain_file(path)
              is_expected.not_to contain_file(path).that_notifies('Class[ipmi::service]')
              is_expected.not_to contain_file(path).that_notifies('Class[ipmi::service::ipmi]')
              is_expected.not_to contain_file(path).that_notifies('Class[ipmi::service::ipmievd]')
            end
          end

          it { is_expected.not_to contain_exec(modprobe_exec).that_notifies('Class[ipmi::service]') }
          it { is_expected.not_to contain_augeas('ipmi_watchdog').that_notifies('Class[ipmi::service::ipmi]') }
        end

        context 'when OpenIPMI owns the device' do
          let(:params) { { watchdog: true, watchdog_supervisor: 'openipmi' } }

          it 'restarts the ipmi service, which loads the module, when its config changes' do
            is_expected.to contain_augeas('ipmi_watchdog').that_notifies('Class[ipmi::service::ipmi]')
          end

          it { is_expected.not_to contain_augeas('ipmi_watchdog').that_notifies('Class[ipmi::service::ipmievd]') }
          it { is_expected.not_to contain_file(dropin).that_notifies('Class[ipmi::service]') }
        end
      end

      context 'with supervisor auto' do
        context 'and ipmi_systemd_version 252' do
          let(:facts) { super().merge(ipmi_systemd_version: '252') }
          let(:params) { { watchdog: true, watchdog_timeout: 30 } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_class('ipmi::watchdog::systemd') }
          it { is_expected.not_to contain_class('ipmi::watchdog::openipmi') }
          it { is_expected.to contain_class('ipmi::watchdog::openipmi::watchdog_param').with(enable: false, only_if_exists: true) }
          it { is_expected.not_to contain_class('systemd') }

          it do
            is_expected.to contain_augeas('ipmi_watchdog').with(
              context: "/files#{config_file}",
              changes: ['set IPMI_WATCHDOG no'],
              onlyif: "match /files#{config_file} size > 0",
            )
          end

          it do
            is_expected.to contain_file('/etc/systemd/system.conf.d').with(
              ensure: 'directory',
              owner: 'root',
              group: 'root',
              mode: '0755',
            )
          end

          it do
            is_expected.to contain_file(dropin).with(
              ensure: 'file',
              owner: 'root',
              group: 'root',
              mode: '0644',
              content: %r{\A#[^\n]*\n\[Manager\]\nRuntimeWatchdogSec=30\n\z},
            )
          end

          it do
            is_expected.to contain_exec(reexec).with(
              command: 'systemctl daemon-reexec',
              refreshonly: true,
            ).that_subscribes_to("File[#{dropin}]")
          end

          it { is_expected.to contain_class('ipmi::watchdog::kmod').that_comes_before('Class[ipmi::watchdog::systemd]') }
        end

        context 'and ipmi_systemd_version 1000 (numeric compare)' do
          let(:facts) { super().merge(ipmi_systemd_version: '1000') }
          let(:params) { { watchdog: true, watchdog_timeout: 30 } }

          it { is_expected.to contain_file(dropin).with_ensure('file') }
        end

        # systemd up to 249 opens /dev/watchdog; 250 and 251 open only
        # /dev/watchdog0, which ipmi_watchdog never creates; 252 tries
        # /dev/watchdog0 and then /dev/watchdog.
        {
          '219' => 'systemd',
          '239' => 'systemd',
          '245' => 'systemd',
          '249' => 'systemd',
          '250' => 'openipmi',
          '251' => 'openipmi',
          '252' => 'systemd',
          '257' => 'systemd',
        }.each do |version, owner|
          context "and ipmi_systemd_version #{version}" do
            let(:facts) { super().merge(ipmi_systemd_version: version) }
            let(:params) { { watchdog: true, watchdog_timeout: 30 } }

            if owner == 'systemd'
              it { is_expected.to contain_file(dropin).with_ensure('file') }
              it { is_expected.to contain_augeas('ipmi_watchdog').with_changes(['set IPMI_WATCHDOG no']) }
            else
              it { is_expected.to contain_file(dropin).with_ensure('absent') }
              it { is_expected.to contain_augeas('ipmi_watchdog').with_changes(['set IPMI_WATCHDOG yes', %(set IPMI_WATCHDOG_OPTIONS '"timeout=30"')]) }
            end
          end
        end

        context 'and an Integer ipmi_systemd_version 250' do
          let(:facts) { super().merge(ipmi_systemd_version: 250) }
          let(:params) { { watchdog: true, watchdog_timeout: 30 } }

          it { is_expected.to contain_file(dropin).with_ensure('absent') }
        end

        context 'and no ipmi_systemd_version fact' do
          let(:params) { { watchdog: true } }

          it { is_expected.to contain_file(dropin).with_ensure('absent') }
        end

        context "and only puppet/systemd's systemd_version fact" do
          let(:facts) { super().merge(systemd_version: '257') }
          let(:params) { { watchdog: true } }

          it { is_expected.to contain_file(dropin).with_ensure('absent') }
        end

        context 'and watchdog => false removes the drop-in' do
          let(:facts) { super().merge(ipmi_systemd_version: '257') }

          it { is_expected.to contain_file(dropin).with_ensure('absent') }
          it { is_expected.to contain_exec(reexec).that_subscribes_to("File[#{dropin}]") }
          it { is_expected.not_to contain_class('systemd') }
          it { is_expected.not_to contain_exec(modprobe_exec) }
        end
      end

      context 'with supervisor systemd on an old systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '219') }
        let(:params) { { watchdog: true, watchdog_supervisor: 'systemd', watchdog_timeout: 30 } }

        it { is_expected.to contain_file(dropin).with_ensure('file') }
        it { is_expected.to contain_augeas('ipmi_watchdog').with(changes: ['set IPMI_WATCHDOG no']) }
      end

      context 'with supervisor openipmi on a new systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_supervisor: 'openipmi' } }

        it 'removes a drop-in written while systemd was the owner' do
          is_expected.to contain_file(dropin).with_ensure('absent')
        end

        it { is_expected.to contain_exec(reexec).that_subscribes_to("File[#{dropin}]") }
        it { is_expected.to contain_augeas('ipmi_watchdog').with(changes: ['set IPMI_WATCHDOG yes']) }
      end

      context 'with the default watchdog_timeout under systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true } }

        it 'leaves RuntimeWatchdogSec to the rest of the systemd configuration' do
          is_expected.to contain_file(dropin).with_ensure('absent')
        end

        it { is_expected.not_to contain_file('/etc/systemd/system.conf.d') }
        it { is_expected.to contain_exec(reexec).that_subscribes_to("File[#{dropin}]") }
        it { is_expected.to contain_file(modules_load_conf).with_ensure('file') }
      end

      context 'with RuntimeWatchdogSec => 0 in watchdog_systemd_options' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_systemd_options: { 'RuntimeWatchdogSec' => 0 } } }

        it { is_expected.to contain_file(dropin).with_content(%r{\A#[^\n]*\n\[Manager\]\nRuntimeWatchdogSec=0\n\z}) }
      end

      context 'with only other watchdog_systemd_options under systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_systemd_options: { 'RebootWatchdogSec' => '10min' } } }

        it { is_expected.to contain_file(dropin).with_content(%r{\A#[^\n]*\n\[Manager\]\nRebootWatchdogSec=10min\n\z}) }
      end

      context 'with watchdog_timeout under systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_timeout: 30 } }

        it { is_expected.to contain_file(modprobe_conf).with_content(%r{^options ipmi_watchdog timeout=30$}) }
        it { is_expected.to contain_file(dropin).with_content(%r{^RuntimeWatchdogSec=30$}) }
      end

      context 'with watchdog_systemd_options forcing RuntimeWatchdogSec off' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) do
          {
            watchdog: true,
            watchdog_timeout: 30,
            watchdog_systemd_options: { 'RuntimeWatchdogSec' => '0' },
          }
        end

        it { is_expected.to contain_file(modules_load_conf).with_ensure('file') }
        it { is_expected.to contain_file(dropin).with_content(%r{^RuntimeWatchdogSec=0$}) }
      end

      context 'with watchdog_systemd_options overriding the timeout' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) do
          {
            watchdog: true,
            watchdog_timeout: 30,
            watchdog_systemd_options: { 'RuntimeWatchdogSec' => '45', 'KExecWatchdogSec' => '5min' },
          }
        end

        it do
          is_expected.to contain_file(dropin)
            .with_content(%r{^RuntimeWatchdogSec=45$})
            .with_content(%r{^KExecWatchdogSec=5min$})
        end
      end

      context 'with a watchdog_systemd_options value spanning lines' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) do
          { watchdog: true, watchdog_systemd_options: { 'RuntimeWatchdogSec' => "30\nRebootWatchdogSec=0" } }
        end

        it { is_expected.to compile.and_raise_error(%r{watchdog_systemd_options}) }
      end

      context 'with watchdog_manage_module => false under systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_manage_module: false, watchdog_timeout: 30 } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file(dropin).with_ensure('file') }
        it { is_expected.to contain_file(modules_load_conf).with_ensure('absent') }
        it { is_expected.not_to contain_exec(modprobe_exec) }
      end
    end
  end
end
