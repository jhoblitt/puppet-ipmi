# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::user', type: :define do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) do
        facts.merge(
          {
            ipmitool: { mc_info: { IPMI_Puppet_Service_Recommend: 'running' } },
            ipmi: { default: { channel: 1 } }
          }
        )
      end
      let(:title) { 'newuser' }

      context 'when deploying with password param' do
        let(:params) do
          {
            password: 'password',
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            user: 'root',
            user_id: 3,
            password: 'password',
            priv: 4,
            channel: 1,
            enable: true,
            purge_id_mismatch: false
          )
        }
      end

      context 'when deploying with all params' do
        let(:params) do
          {
            user: 'newuser1',
            password: 'password',
            priv: 3,
            user_id: 4,
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            user: 'newuser1',
            user_id: 4,
            password: 'password',
            priv: 3,
            channel: 1,
            enable: true
          )
        }
      end

      context 'when deploying with all params and a sensitive password' do
        let(:params) do
          {
            user: 'newuser1',
            password: sensitive('password'),
            priv: 3,
            user_id: 4,
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            user: 'newuser1',
            user_id: 4,
            priv: 3,
            channel: 1,
            enable: true
          )
        }
      end

      context 'when deploying with user_id auto' do
        let(:params) do
          {
            user: 'newuser1',
            password: 'password',
            user_id: 'auto',
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            user: 'newuser1',
            user_id: :auto,
            priv: 4,
            channel: 1,
            enable: true
          )
        }
      end

      describe 'when deploying with no params' do
        it 'fails and raise password required error' do
          expect { is_expected.to contain_ipmi_user('ipmi_user_newuser') }.to raise_error(Puppet::Error, %r{You must supply a password to enable})
        end
      end

      describe 'when deploying with invalid priv' do
        let(:params) do
          {
            user: 'newuser1',
            password: 'password',
            priv: 5,
            user_id: 4,
          }
        end

        it 'fails and raise invalid privilege error' do
          expect { is_expected.to contain_ipmi_user('ipmi_user_newuser') }.to raise_error(Puppet::Error, %r{priv must be})
        end
      end

      describe 'when deploying without a password set' do
        let(:params) do
          {
            enable: true
          }
        end

        it 'fails and raise password required error' do
          expect { is_expected.to contain_ipmi_user('ipmi_user_newuser') }.to raise_error(Puppet::Error, %r{You must supply a password to enable})
        end
      end

      describe 'when disabling a user' do
        let(:params) do
          {
            enable: false
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            enable: false
          )
        }
      end

      describe 'when disabling a user with purge_id_mismatch => true' do
        let(:params) do
          {
            enable: false,
            purge_id_mismatch: true,
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            enable: false,
            purge_id_mismatch: true
          )
        }
      end

      describe 'when purge_id_mismatch => true with enable => true' do
        let(:params) do
          {
            user: 'newuser1',
            password: 'password',
            priv: 3,
            user_id: 4,
            purge_id_mismatch: true,
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            user: 'newuser1',
            user_id: 4,
            priv: 3,
            channel: 1,
            enable: true,
            purge_id_mismatch: true
          )
        }
      end

      describe 'when purge_id_mismatch => true with a sensitive password' do
        let(:params) do
          {
            user: 'newuser1',
            password: sensitive('password'),
            priv: 3,
            user_id: 4,
            purge_id_mismatch: true,
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_user('ipmi_user_newuser').with(
            user: 'newuser1',
            user_id: 4,
            priv: 3,
            enable: true,
            purge_id_mismatch: true
          )
        }
      end
    end
  end
end
