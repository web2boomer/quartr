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

  describe '#company by id' do
    subject { api.company(company_id: 3624) }

    it "includes attributes" do  
      expect(subject.count).to be > 0
    end
  end  

  describe '#company by ticker' do
    subject { api.company(ticker: "NVDA") }

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
    subject { api.earlier_events(tickers: ["NVDA", "SHOP"]) }

    it "includes attributes" do  
      expect(subject.count).to be > 0
    end
  end      



end
