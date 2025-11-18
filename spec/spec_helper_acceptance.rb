require 'beaker-rspec'
require 'beaker-puppet'
require 'beaker/module_install_helper'
require 'voxpupuli/acceptance/spec_helper_acceptance'

$LOAD_PATH << File.join(__dir__, 'acceptance/lib')

# TODO: This should be added to Beaker
def assert_matching_arrays(expected, actual, message = '')
  assert_equal(expected.sort, actual.sort, message)
end

# TODO: Remove the wrappers to user_present
# and user_absent if Beaker::Host's user_present
# and user_absent functions are fixed to work with
# Arista (EOS).

def user_present(host, username)
  case host['platform']
  when %r{eos}
    on(host, "useradd #{username}")
  else
    host.user_present(username)
  end
end

def user_absent(host, username)
  case host['platform']
  when %r{eos}
    on(host, "userdel #{username}", acceptable_exit_codes: [0, 1])
  else
    host.user_absent(username)
  end
end

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
  apply_manifest_on(agent, %(case $facts['os']['name'] {
                                centos, redhat, fedora, amazon: {$cron = 'cronie'}
                                solaris: { $cron = 'core-os' }
                                default: {$cron ='cron'} }
                                package {'cron': name=> $cron, ensure=>present, }))
end

# Returns all of the lines that correspond to crontab entries
# on the agent. For simplicity, these are any lines that do
# not begin with '#'.
def crontab_entries_of(host, username)
  crontab_contents = run_cron_on(host, :list, username).stdout.strip
  crontab_contents.lines.map(&:chomp).reject { |line| line =~ %r{^#} }
end

def resource_manifest(resource, title, params = {})
  params_str = params.map { |param, value|
    # This is not quite correct for all parameter values,
    # but it is good enough for most purposes.
    value_str = value.to_s
    value_str = "\"#{value_str}\"" if value.is_a?(String)

    "  #{param} => #{value_str}"
  }.join(",\n")

  <<-MANIFEST
  #{resource} { '#{title}':
  #{params_str}
}
   MANIFEST
end

def file_manifest(path, params = {})
  resource_manifest('file', path, params)
end

def cron_manifest(entry_name, params = {})
  resource_manifest('cron', entry_name, params)
end

def user_manifest(username, params = {})
  resource_manifest('user', username, params)
end

RSpec.configure do |c|
  c.before :suite do
    unless ENV['BEAKER_provision'] == 'no'
      def run_puppet_install_helper
        return unless ENV['PUPPET_INSTALL_TYPE'] == 'agent'
        if ENV['BEAKER_PUPPET_COLLECTION'].match? %r{/-nightly$/}
          # Workaround for RE-10734
          options[:release_apt_repo_url] = 'http://nightlies.puppet.com/apt'
          options[:win_download_url] = 'http://nightlies.puppet.com/downloads/windows'
          options[:mac_download_url] = 'http://nightlies.puppet.com/downloads/mac'
        end

        agent_sha = ENV['BEAKER_PUPPET_AGENT_SHA'] || ENV['PUPPET_AGENT_SHA']
        if agent_sha.nil? || agent_sha.empty?
          install_puppet_agent_on(hosts, options.merge(version:))
        else
          # If we have a development sha, assume we're testing internally
          dev_builds_url = ENV['DEV_BUILDS_URL'] || 'http://builds.delivery.puppetlabs.net'
          install_from_build_data_url('puppet-agent', "#{dev_builds_url}/puppet-agent/#{agent_sha}/artifacts/#{agent_sha}.yaml", hosts)
        end

        # XXX install_puppet_agent_on() will only add_aio_defaults_on when the
        # nodeset type == 'aio', but we don't want to depend on that.
        add_aio_defaults_on(hosts)
        add_puppet_paths_on(hosts)
      end

      hosts.each { |host| host[:type] = 'aio' }
      run_puppet_install_helper
      install_module_on(hosts_as('default'))
      install_module_dependencies_on(hosts)
    end
  end
end
