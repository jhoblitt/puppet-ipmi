#!/usr/bin/env ruby
# frozen_string_literal: true

Facter.add(:ipmitool_mc_info) do
  # https://puppet.com/docs/puppet/latest/fact_overview.html
  confine kernel: 'Linux'
  setcode do
    ipmitool_value = Facter.value('ipmitool')
    ipmitool_value.nil? ? { 'IPMI_Puppet_Service_Recommend' => 'stopped' } : ipmitool_value[:mc_info]
  end
end
