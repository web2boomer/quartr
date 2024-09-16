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

  describe '#company' do
    subject { api.company(3624) }

    it "includes attributes" do  
      expect(subject.count).to be > 0
    end
  end  

  describe '#event' do
    subject { api.event(256) }

    it "includes attributes" do  
      expect(subject.count).to be > 0
    end
  end    

  describe '#earlier_events' do
    subject { api.earlier_events(tickers: ["NVDA", "APPL"]) }

    it "includes attributes" do  
      expect(subject.count).to be > 0
    end
  end      



end
