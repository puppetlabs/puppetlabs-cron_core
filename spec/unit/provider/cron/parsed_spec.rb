require 'spec_helper'

describe Puppet::Type.type(:cron).provider(:crontab) do
  let :provider do
    described_class.new(command: '/bin/true')
  end

  let :resource do
    Puppet::Type.type(:cron).new(
      minute: ['0', '15', '30', '45'],
      hour: ['8-18', '20-22'],
      monthday: ['31'],
      month: ['12'],
      weekday: ['7'],
      name: 'basic',
      command: '/bin/true',
      target: 'root',
      provider:,
    )
  end

  let :resource_special do
    Puppet::Type.type(:cron).new(
      special: 'reboot',
      name: 'special',
      command: '/bin/true',
      target: 'nobody',
    )
  end

  let :resource_sparse do
    Puppet::Type.type(:cron).new(
      minute: ['42'],
      target: 'root',
      name: 'sparse',
    )
  end

  let :record_special do
    {
      record_type: :crontab,
      special: 'reboot',
      command: '/bin/true',
      on_disk: true,
      target: 'nobody',
    }
  end

  let :record do
    {
      record_type: :crontab,
      minute: ['0', '15', '30', '45'],
      hour: ['8-18', '20-22'],
      monthday: ['31'],
      month: ['12'],
      weekday: ['7'],
      special: :absent,
      command: '/bin/true',
      on_disk: true,
      target: 'root',
    }
  end

  describe 'when determining the correct filetype' do
    it 'uses the suntab filetype on Solaris' do
      allow(Facter).to receive(:value).with('os.family').and_return 'Solaris'
      expect(described_class.filetype).to eq(Puppet::Provider::Cron::FileType::FileTypeSuntab)
    end

    it 'uses the aixtab filetype on AIX' do
      allow(Facter).to receive(:value).with('os.family').and_return 'AIX'
      expect(described_class.filetype).to eq(Puppet::Provider::Cron::FileType::FileTypeAixtab)
    end

    it 'uses the crontab filetype on other platforms' do
      allow(Facter).to receive(:value).with('os.family').and_return 'Not a real operating system family'
      expect(described_class.filetype).to eq(Puppet::Provider::Cron::FileType::FileTypeCrontab)
    end
  end

  # I'd use expect(ENV).to receive(:[]).with('USER') but this does not work because
  # ENV["USER"] is evaluated at load time.
  describe 'when determining the default target' do
    it "uses the current user #{ENV['USER']}", if: ENV['USER'] do
      expect(described_class.default_target).to eq(ENV['USER'])
    end

    it 'fallbacks to root', unless: ENV['USER'] do
      expect(described_class.default_target).to eq('root')
    end
  end

  describe '.targets' do
    let(:tabs) { [described_class.default_target] + ['foo', 'bar'] }

    before(:each) do
      allow(File).to receive(:readable?).and_return true
      allow(File).to receive(:file?).and_return true
      allow(File).to receive(:writable?).and_return true
    end

    it 'adds all crontabs as targets' do
      expect(Dir).to receive(:foreach).and_yield(tabs[0]).and_yield(tabs[1]).and_yield(tabs[2])
      expect(described_class.targets).to eq(tabs)
    end
  end

  describe 'when parsing a record' do
    it 'parses a comment' do
      expect(described_class.parse_line('# This is a test')).to eq(record_type: :comment,
                                                                   line: '# This is a test')
    end

    it 'gets the resource name of a PUPPET NAME comment' do
      expect(described_class.parse_line('# Puppet Name: My Fancy Cronjob')).to eq(record_type: :comment,
                                                                                  name: 'My Fancy Cronjob',
                                                                                  line: '# Puppet Name: My Fancy Cronjob')
    end

    it 'ignores blank lines' do
      expect(described_class.parse_line('')).to eq(record_type: :blank, line: '')
      expect(described_class.parse_line(' ')).to eq(record_type: :blank, line: ' ')
      expect(described_class.parse_line("\t")).to eq(record_type: :blank, line: "\t")
      expect(described_class.parse_line("  \t ")).to eq(record_type: :blank, line: "  \t ")
    end

    it 'extracts environment assignments' do
      # man 5 crontab: MAILTO="" with no value can be used to surpress sending
      # mails at all
      expect(described_class.parse_line('MAILTO=""')).to eq(record_type: :environment, line: 'MAILTO=""')
      expect(described_class.parse_line('FOO=BAR')).to eq(record_type: :environment, line: 'FOO=BAR')
      expect(described_class.parse_line('FOO_BAR=BAR')).to eq(record_type: :environment, line: 'FOO_BAR=BAR')
      expect(described_class.parse_line('SPACE = BAR')).to eq(record_type: :environment, line: 'SPACE = BAR')
    end

    it 'extracts a cron entry' do
      expect(described_class.parse_line('* * * * * /bin/true')).to eq(record_type: :crontab,
                                                                      hour: :absent,
                                                                      minute: :absent,
                                                                      month: :absent,
                                                                      weekday: :absent,
                                                                      monthday: :absent,
                                                                      special: :absent,
                                                                      command: '/bin/true')
      expect(described_class.parse_line('0,15,30,45 8-18,20-22 31 12 7 /bin/true')).to eq(record_type: :crontab,
                                                                                          minute: ['0', '15', '30', '45'],
                                                                                          hour: ['8-18', '20-22'],
                                                                                          monthday: ['31'],
                                                                                          month: ['12'],
                                                                                          weekday: ['7'],
                                                                                          special: :absent,
                                                                                          command: '/bin/true')
      # A percent sign will cause the rest of the string to be passed as
      # standard input and will also act as a newline character. Not sure
      # if puppet should convert % to a \n as the command property so the
      # test covers the current behaviour: Do not do any conversions
      expect(described_class.parse_line('0 22 * * 1-5   mail -s "It\'s 10pm" joe%Joe,%%Where are your kids?%')).to eq(record_type: :crontab,
                                                                                                                      minute: ['0'],
                                                                                                                      hour: ['22'],
                                                                                                                      monthday: :absent,
                                                                                                                      month: :absent,
                                                                                                                      weekday: ['1-5'],
                                                                                                                      special: :absent,
                                                                                                                      command: 'mail -s "It\'s 10pm" joe%Joe,%%Where are your kids?%')
    end

    describe 'it should support special strings' do
      ['reboot', 'yearly', 'anually', 'monthly', 'weekly', 'daily', 'midnight', 'hourly'].each do |special|
        it "supports @#{special}" do
          expect(described_class.parse_line("@#{special} /bin/true")).to eq(record_type: :crontab,
                                                                            hour: :absent,
                                                                            minute: :absent,
                                                                            month: :absent,
                                                                            weekday: :absent,
                                                                            monthday: :absent,
                                                                            special:,
                                                                            command: '/bin/true')
        end
      end
    end
  end

  describe '.instances' do
    before :each do
      allow(described_class).to receive(:targets).and_return ['foobar']
    end

    describe 'on linux' do
      before(:each) do
        allow(Facter).to receive(:value).with('os.family').and_return 'Linux'
        allow(Facter).to receive(:value).with('os.name')
      end

      it 'contains no resources for a user who has no crontab' do
        allow(Puppet::Util).to receive(:uid).and_return(10)

        expect(Puppet::Util::Execution).to receive(:execute).with('crontab -u foobar -l', failonfail: true, combine: true).and_return('')
        expect(described_class.instances).to be_empty
      end

      it 'contains no resources for a user who is absent' do
        allow(Puppet::Util).to receive(:uid).and_return(nil)

        expect(described_class.instances).to be_empty
      end

      it 'is able to create records from not-managed records' do
        allow(described_class).to receive(:target_object).and_return File.new(my_fixture('simple'))
        parameters = described_class.instances.map do |p|
          h = { name: p.get(:name) }
          Puppet::Type.type(:cron).validproperties.each do |property|
            h[property] = p.get(property)
          end
          h
        end

        expect(parameters[0][:name]).to match(%r{unmanaged:\$HOME/bin/daily.job_>>_\$HOME/tmp/out_2>&1-\d+})
        expect(parameters[0][:minute]).to eq(['5'])
        expect(parameters[0][:hour]).to eq(['0'])
        expect(parameters[0][:weekday]).to eq(:absent)
        expect(parameters[0][:month]).to eq(:absent)
        expect(parameters[0][:monthday]).to eq(:absent)
        expect(parameters[0][:special]).to eq(:absent)
        expect(parameters[0][:command]).to match(%r{\$HOME/bin/daily.job >> \$HOME/tmp/out 2>&1})
        expect(parameters[0][:ensure]).to eq(:present)
        expect(parameters[0][:environment]).to eq([])
        expect(parameters[0][:user]).to eq(:absent)

        expect(parameters[1][:name]).to match(%r{unmanaged:\$HOME/bin/monthly-\d+})
        expect(parameters[1][:minute]).to eq(['15'])
        expect(parameters[1][:hour]).to eq(['14'])
        expect(parameters[1][:weekday]).to eq(:absent)
        expect(parameters[1][:month]).to eq(:absent)
        expect(parameters[1][:monthday]).to eq(['1'])
        expect(parameters[1][:special]).to eq(:absent)
        expect(parameters[1][:command]).to match(%r{\$HOME/bin/monthly})
        expect(parameters[1][:ensure]).to eq(:present)
        expect(parameters[1][:environment]).to eq([])
        expect(parameters[1][:user]).to eq(:absent)
        expect(parameters[1][:target]).to eq('foobar')
      end

      it 'is able to parse puppet managed cronjobs' do
        allow(described_class).to receive(:target_object).and_return File.new(my_fixture('managed'))
        expect(described_class.instances.map do |p|
          h = { name: p.get(:name) }
          Puppet::Type.type(:cron).validproperties.each do |property|
            h[property] = p.get(property)
          end
          h
        end).to eq([
                     {
                       name: 'real_job',
                       minute: :absent,
                       hour: :absent,
                       weekday: :absent,
                       month: :absent,
                       monthday: :absent,
                       special: :absent,
                       command: '/bin/true',
                       ensure: :present,
                       environment: [],
                       user: :absent,
                       target: 'foobar',
                     },
                     {
                       name: 'complex_job',
                       minute: :absent,
                       hour: :absent,
                       weekday: :absent,
                       month: :absent,
                       monthday: :absent,
                       special: 'reboot',
                       command: '/bin/true >> /dev/null 2>&1',
                       ensure: :present,
                       environment: [
                         'MAILTO=foo@example.com',
                         'SHELL=/bin/sh',
                       ],
                       user: :absent,
                       target: 'foobar',
                     },
                   ])
      end
    end
  end

  describe '.match' do
    describe 'normal records' do
      it 'matches when all fields are the same' do
        expect(described_class.match(record, resource[:name] => resource)).to eq(resource)
      end

      {
        minute: ['0', '15', '31', '45'],
        hour: ['8-18'],
        monthday: ['30', '31'],
        month: ['12', '23'],
        weekday: ['4'],
        command: '/bin/false',
        target: 'nobody',
      }.each_pair do |field, new_value|
        it "does not match a record when #{field} does not match" do
          record[field] = new_value
          expect(described_class.match(record, resource[:name] => resource)).to be_falsey
        end
      end
    end

    describe 'special records' do
      it 'matches when all fields are the same' do
        expect(described_class.match(record_special, resource_special[:name] => resource_special)).to eq(resource_special)
      end

      {
        special: 'monthly',
        command: '/bin/false',
        target: 'root',
      }.each_pair do |field, new_value|
        it "does not match a record when #{field} does not match" do
          record_special[field] = new_value
          expect(described_class.match(record_special, resource_special[:name] => resource_special)).to be_falsey
        end
      end
    end

    describe 'with a resource without a command' do
      it 'does not raise an error' do
        expect { described_class.match(record, resource_sparse[:name] => resource_sparse) }.not_to raise_error
      end
    end
  end

  describe 'when setting a time field on a record with a special schedule (#100)' do
    let(:target) { 'nobody' }
    let(:special_record) { { record_type: :crontab, name: 'special', special: 'daily', minute: :absent, hour: :absent, monthday: :absent, month: :absent, weekday: :absent, command: '/bin/true', target: } }
    let(:special_provider) { described_class.new(special_record.dup) }

    # to_file runs the record through pre_gen and to_line, like a real flush
    def generated_line(provider)
      described_class.to_file([provider.property_hash]).lines.grep(%r{/bin/true}).first.chomp
    end

    before(:each) do
      allow(described_class).to receive(:header).and_return ''
      # marking a target as modified is class level state that would otherwise
      # leak into other examples and make them write the target
      allow(described_class).to receive(:modified)
    end

    it 'defines the time field setters on the provider itself rather than the generic ones' do
      described_class::TIME_FIELDS.each do |field|
        expect(described_class.instance_method(:"#{field}=").owner).to eq(described_class)
        expect(described_class.instance_method(:"#{field}=").source_location.first).to end_with('crontab.rb')
      end
    end

    {
      minute: [['8'], '8 * * * * /bin/true'],
      hour: [['4'], '* 4 * * * /bin/true'],
      monthday: [['15'], '* * 15 * * /bin/true'],
      month: [['6'], '* * * 6 * /bin/true'],
      weekday: [['2'], '* * * * 2 /bin/true'],
    }.each do |field, (value, expected_line)|
      context "with #{field}" do
        it 'clears the special schedule when given a real value' do
          special_provider.send(:"#{field}=", value)
          expect(special_provider.property_hash[:special]).to eq(:absent)
          expect(special_provider.property_hash[field]).to eq(value)
        end

        it 'generates a numeric crontab line after the special schedule was cleared' do
          expect(generated_line(special_provider)).to eq('@daily /bin/true')
          special_provider.send(:"#{field}=", value)
          expect(generated_line(special_provider)).to eq(expected_line)
        end

        it 'marks the target as modified' do
          expect(described_class).to receive(:modified).with(target)
          special_provider.send(:"#{field}=", value)
        end

        it 'keeps the special schedule when set to :absent' do
          special_provider.send(:"#{field}=", :absent)
          expect(special_provider.property_hash[:special]).to eq('daily')
          expect(special_provider.property_hash[field]).to eq(:absent)
          expect(generated_line(special_provider)).to eq('@daily /bin/true')
        end

        it "keeps the special schedule when set to 'absent'" do
          special_provider.send(:"#{field}=", 'absent')
          expect(special_provider.property_hash[:special]).to eq('daily')
        end

        it 'keeps the special schedule when set to an empty array' do
          special_provider.send(:"#{field}=", [])
          expect(special_provider.property_hash[:special]).to eq('daily')
        end
      end
    end

    it 'clears the special schedule when given an array with several values' do
      special_provider.minute = ['0', '15', '30']
      expect(special_provider.property_hash[:special]).to eq(:absent)
      expect(generated_line(special_provider)).to eq('0,15,30 * * * * /bin/true')
    end

    it 'clears the special schedule when given a single non-array value' do
      special_provider.hour = '4'
      expect(special_provider.property_hash[:special]).to eq(:absent)
    end

    it 'logs that the special schedule is being cleared' do
      expect(Puppet).to receive(:info).with(%r{Clearing special schedule 'daily' for special because minute is now managed})
      special_provider.minute = ['8']
    end

    it 'does not log when no special schedule is present' do
      numeric_provider = described_class.new(special_record.merge(special: :absent))
      expect(Puppet).not_to receive(:info)
      numeric_provider.minute = ['8']
    end

    it 'keeps all values when several fields are set one after another' do
      special_provider.minute = ['8']
      special_provider.hour = ['4']
      expect(special_provider.property_hash[:special]).to eq(:absent)
      expect(generated_line(special_provider)).to eq('8 4 * * * /bin/true')
    end

    it 'does not touch the special schedule when setting special itself' do
      special_provider.special = 'weekly'
      expect(special_provider.property_hash[:special]).to eq('weekly')
      expect(generated_line(special_provider)).to eq('@weekly /bin/true')
    end

    it 'leaves a record without a special schedule alone' do
      numeric_provider = described_class.new(special_record.merge(special: :absent, minute: ['1']))
      numeric_provider.minute = ['8']
      expect(numeric_provider.property_hash[:special]).to eq(:absent)
      expect(generated_line(numeric_provider)).to eq('8 * * * * /bin/true')
    end

    it 'does not fail for a record that has no special key' do
      bare_provider = described_class.new(record_type: :crontab, command: '/bin/true', target:)
      expect { bare_provider.minute = ['8'] }.not_to raise_error
      expect(bare_provider.property_hash[:minute]).to eq(['8'])
    end
  end
end
