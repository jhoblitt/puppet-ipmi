# frozen_string_literal: true

shared_examples 'command-confined provider' do |command|
  describe 'command confinement' do
    it 'uses an existence confine for the command' do
      confines = described_class.confine_collection.instance_variable_get(:@confines)
      exists_confines = confines.grep(Puppet::Confine::Exists)

      expect(exists_confines).not_to be_empty
    end

    it 'registers the command by name' do
      path = described_class.command(command)

      expect(path).to be_nil.or(match(%r{\A/}))
    end
  end
end
