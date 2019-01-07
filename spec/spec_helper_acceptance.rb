require 'beaker-rspec'
require 'beaker/module_install_helper'
require 'beaker/puppet_install_helper'

$LOAD_PATH << File.join(__dir__, 'acceptance/lib')

def beaker_opts
  { debug: true, trace: true, expect_failures: true, acceptable_exit_codes: (0...256) }
  # { expect_failures: true, acceptable_exit_codes: (0...256) }
end

def compatible_agents
  agents.reject { |agent| agent['platform'].include?('windows') || agent['platform'].include?('eos-') }
end

def clean(agent, o = {})
  o = { user: 'tstuser' }.merge(o)
  run_cron_on(agent, :remove, o[:user])
  apply_manifest_on(agent, %([user{'%s': ensure => absent, managehome => false }]) % o[:user])
end

def setup(agent, o = {})
  o = { user: 'tstuser' }.merge(o)
  apply_manifest_on(agent, %(user { '%s': ensure => present, managehome => false }) % o[:user])
  apply_manifest_on(agent, %(case $operatingsystem {
                                centos, redhat, fedora: {$cron = 'cronie'}
                                solaris: { $cron = 'core-os' }
                                default: {$cron ='cron'} }
                                package {'cron': name=> $cron, ensure=>present, }))
end

RSpec.configure do |c|
  c.before :suite do
    unless ENV['BEAKER_provision'] == 'no'
      run_puppet_install_helper
      install_module_on(hosts_as('default'))
      install_module_dependencies_on(hosts)
    end
  end
end
