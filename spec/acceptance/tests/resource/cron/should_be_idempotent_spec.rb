require 'spec_helper_acceptance'
require 'puppet/acceptance/common_utils'
extend Puppet::Acceptance::CronUtils

Rspec.context 'when checking idempotency' do
  before(:each) do
    compatible_agents.each do |agent|
      step 'ensure the user exists via puppet'
      setup(agent)
    end
  end

  after(:each) do
    compatible_agents.each do |agent|
      step 'Cron: cleanup'
      clean(agent)
    end
  end

  compatible_agents.each do |agent|
    it "ensures idempotency on #{agent}" do
      step 'Cron: basic - verify that it can be created'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => "*", minute  => [1], ensure  => present,}') do
        expect(result.stdout).to match(%r{ensure: created})
      end
      run_cron_on(agent, :list, 'tstuser') do
        expect(result.stdout).to match(%r{. . . . . .bin.true})
      end

      step 'Cron: basic - should not create again'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => "*", minute  => [1], ensure  => present,}') do
        expect(result.stdout).not_to match(%r{ensure: created})
      end
    end
  end
end
