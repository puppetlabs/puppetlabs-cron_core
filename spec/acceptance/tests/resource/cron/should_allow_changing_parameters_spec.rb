require 'spec_helper_acceptance'
require 'puppet/acceptance/common_utils'
extend Puppet::Acceptance::CronUtils

Rspec.context 'when changing parameters' do
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
    it "manages cron entries on #{agent}" do
      step 'Cron: basic - verify that it can be created'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/false", user    => "tstuser", hour    => "*", minute  => [1], ensure  => present,}') do
        expect(result.stdout).to match(%r{ensure: created})
      end
      run_cron_on(agent, :list, 'tstuser') do
        expect(result.stdout).to match(%r{.bin.false})
      end

      step 'Cron: allow changing command'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => "*", minute  => [1], ensure  => present,}') do
        expect(result.stdout).to match(%r{command changed '.bin.false'.* to '.bin.true'})
      end
      run_cron_on(agent, :list, 'tstuser') do
        expect(result.stdout).to match(%r{1 . . . . .bin.true})
      end

      step 'Cron: allow changing time'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => "1", minute  => [1], ensure  => present,}') do
        expect(result.stdout).to match(%r{hour: defined 'hour' as \['1'\]})
      end
      run_cron_on(agent, :list, 'tstuser') do
        expect(result.stdout).to match(%r{1 1 . . . .bin.true})
      end

      step 'Cron: allow changing time(array)'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => ["1","2"], minute  => [1], ensure  => present,}') do
        expect(result.stdout).to match(%r{hour: hour changed \['1'\].* to \['1', '2'\]})
      end
      run_cron_on(agent, :list, 'tstuser') do
        expect(result.stdout).to match(%r{1 1,2 . . . .bin.true})
      end

      step 'Cron: allow changing time(array modification)'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => ["3","2"], minute  => [1], ensure  => present,}') do
        expect(result.stdout).to match(%r{hour: hour changed \['1', '2'\].* to \['3', '2'\]})
      end
      run_cron_on(agent, :list, 'tstuser') do
        expect(result.stdout).to match(%r{1 3,2 . . . .bin.true})
      end
      step 'Cron: allow changing time(array modification to *)'
      apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => "*", minute  => "*", ensure  => present,}') do
        expect(result.stdout).to match(%r{minute: undefined 'minute' from \['1'\]})
        expect(result.stdout).to match(%r{hour: undefined 'hour' from \['3', '2'\]})
      end
      run_cron_on(agent, :list, 'tstuser') do
        expect(result.stdout).to match(%r{\* \* . . . .bin.true})
      end
    end
  end
end
