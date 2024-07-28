# frozen_string_literal: true

require "quartr"

RSpec.describe Quartr::API do

  let(:api) { described_class.new }

  describe '#companies' do
    subject { api.companies }

    it "includes attributes" do  
      expect(subject.count).to be > 0
    end
  end




end
