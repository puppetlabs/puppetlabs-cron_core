require 'spec_helper'
require 'puppet/file_bucket/dipper'
require 'puppet_spec/compiler'

describe Puppet::Type.type(:cron).provider(:crontab), unless: Puppet.features.microsoft_windows? do
  include PuppetSpec::Files
  include PuppetSpec::Compiler

  before :each do
    allow(Puppet::Type.type(:cron)).to receive(:defaultprovider).and_return described_class
    allow(described_class).to receive(:suitable?).and_return true
    allow_any_instance_of(Puppet::FileBucket::Dipper).to receive(:backup) # rubocop:disable RSpec/AnyInstance

    # I don't want to execute anything
    allow(described_class).to receive(:filetype).and_return Puppet::Util::FileType::FileTypeFlat
    allow(described_class).to receive(:default_target).and_return crontab_user1

    # I don't want to stub Time.now to get a static header because I don't know
    # where Time.now is used elsewhere, so just go with a very simple header
    allow(described_class).to receive(:header).and_return "# HEADER: some simple\n# HEADER: header\n"
    FileUtils.cp(my_fixture('crontab_user1'), crontab_user1)
    FileUtils.cp(my_fixture('crontab_user2'), crontab_user2)
  end

  after :each do
    described_class.clear
  end

  let :crontab_user1 do
    tmpfile('cron_integration_specs')
  end

  let :crontab_user2 do
    tmpfile('cron_integration_specs')
  end

  def expect_output(fixture_name)
    expect(File.read(crontab_user1)).to eq(File.read(my_fixture(fixture_name)))
  end

  describe 'when managing a cron entry' do
    it 'is able to purge unmanaged entries' do
      apply_with_error_check(<<-MANIFEST)
      cron {
        'only managed entry':
          ensure      => 'present',
          command     => '/bin/true',
          target      => '#{crontab_user1}',
      }
      resources { 'cron': purge => 'true' }
      MANIFEST
      expect_output('purged')
    end

    describe 'with ensure absent' do
      it 'does nothing if entry already absent' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'no_such_entry':
            ensure => 'absent',
            target => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('crontab_user1')
      end

      it 'removes the resource from crontab if present' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'My daily failure':
            ensure => 'absent',
            target => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('remove_named_resource')
      end

      it 'removes a matching cronentry if present' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'no_such_named_resource_in_crontab':
            ensure   => absent,
            minute   => [ '17-19', '22' ],
            hour     => [ '0-23/2' ],
            weekday  => 'Tue',
            command  => '/bin/unnamed_regular_command',
            target   => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('remove_unnamed_resource')
      end
    end

    describe 'with ensure present' do
      context 'and no command specified' do
        it 'works if the resource is already present' do
          apply_with_error_check(<<-MANIFEST)
          cron {
            'My daily failure':
              special => 'daily',
              target  => '#{crontab_user1}',
          }
          MANIFEST
          expect_output('crontab_user1')
        end
        it 'fails if the resource needs creating' do
          manifest = <<-MANIFEST
          cron {
            'Entirely new resource':
              special => 'daily',
              target  => '#{crontab_user1}',
          }
          MANIFEST
          apply_compiled_manifest(manifest) do |res|
            if res.ref == 'Cron[Entirely new resource]'
              expect(res).to receive(:err).with(%r{no command})
            else
              expect(res).not_to receive(:err)
            end
          end
        end
      end

      it 'does nothing if entry already present' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'My daily failure':
            special => 'daily',
            command => '/bin/false',
            target  => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('crontab_user1')
      end

      it "works correctly when managing 'target' but not 'user'" do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'My weekly failure':
            special => 'weekly',
            command => '/bin/false',
            target  => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('crontab_user3')
      end

      it 'does nothing if a matching entry already present' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'no_such_named_resource_in_crontab':
            ensure   => present,
            minute   => [ '17-19', '22' ],
            hour     => [ '0-23/2' ],
            command  => '/bin/unnamed_regular_command',
            target   => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('crontab_user1')
      end

      it 'adds a new normal entry if currently absent' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'new entry':
            ensure      => present,
            minute      => '12',
            weekday     => 'Tue',
            command     => '/bin/new',
            environment => [
              'MAILTO=""',
              'SHELL=/bin/bash'
            ],
            target      => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('create_normal_entry')
      end

      it 'adds a new special entry if currently absent' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'new special entry':
            ensure      => present,
            special     => 'reboot',
            command     => 'echo "Booted" 1>&2',
            environment => 'MAILTO=bob@company.com',
            target      => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('create_special_entry')
      end

      it 'changes existing entry if out of sync' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'Monthly job':
            ensure      => present,
            special     => 'monthly',
            #minute => ['22'],
            command     => '/usr/bin/monthly',
            environment => [],
            target      => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('modify_entry')
      end
      it 'changes a special schedule to numeric if requested' do
        apply_with_error_check(<<-MANIFEST)
        cron {
          'My daily failure':
            special     => 'absent',
            command     => '/bin/false',
            target      => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('unspecialized')
      end
      it 'does not try to move an entry from one file to another' do
        # force the parsedfile provider to also parse user1's crontab
        apply_with_error_check(<<-MANIFEST)
        cron {
          'foo':
            ensure => absent,
            target => '#{crontab_user1}';
          'My daily failure':
            special      => 'daily',
            command      => "/bin/false",
            target       => '#{crontab_user2}',
        }
        MANIFEST
        expect(File.read(crontab_user1)).to eq(File.read(my_fixture('moved_cronjob_input1')))
        expect(File.read(crontab_user2)).to eq(File.read(my_fixture('moved_cronjob_input2')))
      end
    end

    # https://github.com/puppetlabs/puppetlabs-cron_core/issues/100
    describe 'when changing a special schedule to numeric fields without managing special' do
      def daily_failure_manifest(attributes)
        params = attributes.map { |name, value| "#{name} => #{value.inspect}," }.join("\n")
        <<-MANIFEST
        cron {
          'My daily failure':
            command => '/bin/false',
            target  => '#{crontab_user1}',
            #{params}
        }
        MANIFEST
      end

      # Applies the manifest a second time against what was written by the first run
      def reapply(manifest)
        described_class.clear
        apply_with_error_check(manifest)
      end

      def changed_resources(transaction)
        transaction.report.resource_statuses.values.select(&:changed).map(&:resource)
      end

      it 'replaces @daily with the numeric schedule' do
        manifest = daily_failure_manifest(minute: '8', hour: '4')
        transaction = apply_with_error_check(manifest)
        expect(changed_resources(transaction)).to eq(['Cron[My daily failure]'])
        expect_output('special_to_numeric')
      end

      it 'is idempotent' do
        manifest = daily_failure_manifest(minute: '8', hour: '4')
        apply_with_error_check(manifest)

        transaction = reapply(manifest)
        expect(changed_resources(transaction)).to be_empty
        expect(transaction.report.resource_statuses['Cron[My daily failure]'].events).to be_empty
        expect_output('special_to_numeric')
      end

      it 'works with array values' do
        apply_with_error_check(daily_failure_manifest(minute: ['0', '30'], hour: ['4']))
        expect(File.read(crontab_user1)).to eq(File.read(my_fixture('crontab_user1')).sub('@daily /bin/false', '0,30 4 * * * /bin/false'))
      end

      it 'works with named, range and step values and is idempotent' do
        manifest = daily_failure_manifest(minute: '*/15', hour: '1-5', month: 'jan', weekday: 'monday')
        apply_with_error_check(manifest)
        expect(File.read(crontab_user1)).to eq(File.read(my_fixture('crontab_user1')).sub('@daily /bin/false', '*/15 1-5 * 1 1 /bin/false'))

        transaction = reapply(manifest)
        expect(changed_resources(transaction)).to be_empty
      end

      it 'leaves the other entries, comments and environment lines untouched' do
        apply_with_error_check(daily_failure_manifest(minute: '8', hour: '4'))
        original = File.read(my_fixture('crontab_user1'))
        result = File.read(crontab_user1)
        expect(result.lines - original.lines).to eq(["8 4 * * * /bin/false\n"])
        expect(original.lines - result.lines).to eq(["@daily /bin/false\n"])
        expect(result).to include('@daily /bin/unnamed_special_command', 'MAILTO=""', 'SHELL=/bin/sh')
      end

      {
        minute: ['8', '8 * * * *'],
        hour: ['4', '* 4 * * *'],
        monthday: ['15', '* * 15 * *'],
        month: ['6', '* * * 6 *'],
        weekday: ['2', '* * * * 2'],
      }.each do |field, (value, schedule)|
        context "with only #{field}" do
          let(:manifest) { daily_failure_manifest(field => value) }

          it 'replaces @daily and leaves the other fields as *' do
            apply_with_error_check(manifest)
            expect(File.read(crontab_user1)).to eq(File.read(my_fixture('crontab_user1')).sub('@daily /bin/false', "#{schedule} /bin/false"))
          end

          it 'is idempotent' do
            apply_with_error_check(manifest)
            transaction = reapply(manifest)
            expect(changed_resources(transaction)).to be_empty
            expect(File.read(crontab_user1)).to eq(File.read(my_fixture('crontab_user1')).sub('@daily /bin/false', "#{schedule} /bin/false"))
          end
        end
      end

      it 'does not clear the special schedule when a field is managed as absent' do
        transaction = apply_with_error_check(daily_failure_manifest(minute: 'absent'))
        expect(changed_resources(transaction)).to be_empty
        expect_output('crontab_user1')
      end

      it "does not clear the special schedule when a field is managed as '*'" do
        transaction = apply_with_error_check(daily_failure_manifest(minute: '*', hour: '*'))
        expect(changed_resources(transaction)).to be_empty
        expect_output('crontab_user1')
      end

      it 'does not touch the special schedule when no time field is managed' do
        transaction = apply_with_error_check(daily_failure_manifest({}))
        expect(changed_resources(transaction)).to be_empty
        expect_output('crontab_user1')
      end

      it 'still converts to numeric when special is explicitly absent' do
        apply_with_error_check(daily_failure_manifest(special: 'absent'))
        expect_output('unspecialized')
      end

      it 'still converts to numeric when special is explicitly absent and fields are given' do
        apply_with_error_check(daily_failure_manifest(special: 'absent', minute: '8', hour: '4'))
        expect_output('special_to_numeric')
      end

      it 'still changes one special schedule to another' do
        apply_with_error_check(daily_failure_manifest(special: 'weekly'))
        expect_output('special_to_other_special')

        transaction = reapply(daily_failure_manifest(special: 'weekly'))
        expect(changed_resources(transaction)).to be_empty
      end

      it 'still changes a numeric schedule to a special one and back to a numeric one' do
        monthly = <<-MANIFEST
        cron {
          'Monthly job':
            special => 'weekly',
            command => '$HOME/bin/monthly',
            target  => '#{crontab_user1}',
        }
        MANIFEST
        apply_with_error_check(monthly)
        expect(File.read(crontab_user1)).to eq(File.read(my_fixture('crontab_user1')).sub('15 14 1 * * $HOME/bin/monthly', '@weekly $HOME/bin/monthly'))

        # and back again, without managing special
        described_class.clear
        apply_with_error_check(<<-MANIFEST)
        cron {
          'Monthly job':
            minute  => '15',
            hour    => '14',
            monthday => '1',
            command => '$HOME/bin/monthly',
            target  => '#{crontab_user1}',
        }
        MANIFEST
        expect_output('crontab_user1')
      end
    end

    describe 'when changing a field of an existing numeric schedule' do
      let(:manifest) do
        <<-MANIFEST
        cron {
          'Monthly job':
            minute  => '30',
            command => '$HOME/bin/monthly',
            target  => '#{crontab_user1}',
        }
        MANIFEST
      end

      it 'changes only that field' do
        apply_with_error_check(manifest)
        expect_output('modify_numeric_minute')
      end

      it 'is idempotent' do
        apply_with_error_check(manifest)
        described_class.clear
        transaction = apply_with_error_check(manifest)
        expect(transaction.report.resource_statuses.values.select(&:changed)).to be_empty
        expect_output('modify_numeric_minute')
      end
    end
  end
end
