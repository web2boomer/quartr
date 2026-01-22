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

  describe '#parse_live_transcript_jsonl' do
    let(:sample_jsonl) do
      <<~JSONL
        {"type": "start", "file_format_version": "1.6"}
        {"t": "Hello", "s": 0.1, "e": 0.5, "p": "0", "S": "0"}
        {"t": "world", "s": 0.5, "e": 1.0, "p": "0", "S": "0"}
        {"type": "keep-alive"}
        {"t": "[indiscernible]", "s": 1.0, "e": 1.5, "p": "1", "c": 0.3, "ot": "everyone"}
        {"type": "section", "name": "predicted-qna", "s": 1.0}
        {"type": "end"}
      JSONL
    end

    subject { api.parse_live_transcript_jsonl(sample_jsonl) }

    it "parses all record types" do
      expect(subject.length).to eq(7)
    end

    it "parses start record" do
      start_record = subject.find { |r| r[:type] == 'start' }
      expect(start_record[:file_format_version]).to eq('1.6')
    end

    it "parses entry records" do
      entries = subject.select { |r| r[:type] == 'entry' }
      expect(entries.length).to eq(3)
      expect(entries[0][:text]).to eq('Hello')
      expect(entries[0][:start_time]).to eq(0.1)
      expect(entries[0][:speaker_index]).to eq('0')
    end

    it "preserves original text and confidence for low-confidence entries" do
      indiscernible = subject.find { |r| r[:text] == '[indiscernible]' }
      expect(indiscernible[:original_text]).to eq('everyone')
      expect(indiscernible[:confidence]).to eq(0.3)
    end

    it "parses section records" do
      section = subject.find { |r| r[:type] == 'section' }
      expect(section[:name]).to eq('predicted-qna')
    end

    it "parses keep-alive records" do
      keep_alive = subject.find { |r| r[:type] == 'keep-alive' }
      expect(keep_alive).not_to be_nil
    end

    it "parses end record" do
      end_record = subject.find { |r| r[:type] == 'end' }
      expect(end_record).not_to be_nil
    end
  end

  describe '#parse_live_transcript_jsonl with v1.7 refinements' do
    let(:sample_jsonl_v17) do
      <<~JSONL
        {"type": "start", "file_format_version": "1.7"}
        {"t": "TomHanks", "s": 1.0, "e": 2.0, "p": "0", "S": "0"}
        {"i": "word-delete", "s": 1.0}
        {"i": "word-insert", "s": 1.0, "rt": "Tom"}
        {"i": "word-insert", "s": 1.5, "rt": "Hanks"}
        {"type": "end"}
      JSONL
    end

    subject { api.parse_live_transcript_jsonl(sample_jsonl_v17) }

    it "parses refinement instructions" do
      refinements = subject.select { |r| r[:type] == 'refinement' }
      expect(refinements.length).to eq(3)
    end

    it "parses word-delete instruction" do
      delete_inst = subject.find { |r| r[:instruction] == 'word-delete' }
      expect(delete_inst[:start_time]).to eq(1.0)
    end

    it "parses word-insert instruction" do
      insert_insts = subject.select { |r| r[:instruction] == 'word-insert' }
      expect(insert_insts.length).to eq(2)
      expect(insert_insts[0][:replacement_text]).to eq('Tom')
    end
  end

  describe '#build_transcript_text' do
    let(:records) do
      [
        { type: 'start', file_format_version: '1.6' },
        { type: 'entry', text: 'Hello', start_time: 0.1, phrase_id: '0' },
        { type: 'entry', text: 'world', start_time: 0.5, phrase_id: '0' },
        { type: 'entry', text: '[indiscernible]', start_time: 1.0, phrase_id: '1' },
        { type: 'entry', text: 'everyone', start_time: 1.5, phrase_id: '1' },
        { type: 'end' }
      ]
    end

    it "builds text from entries excluding indiscernible by default" do
      text = api.build_transcript_text(records, group_by_paragraph: false)
      expect(text).to eq('Hello world everyone')
    end

    it "includes indiscernible when requested" do
      text = api.build_transcript_text(records, group_by_paragraph: false, include_indiscernible: true)
      expect(text).to eq('Hello world [indiscernible] everyone')
    end
  end

  describe '#build_transcript_text with refinements' do
    let(:records) do
      [
        { type: 'entry', text: 'TomHanks', start_time: 1.0, phrase_id: '0' },
        { type: 'entry', text: 'is', start_time: 2.0, phrase_id: '0' },
        { type: 'entry', text: 'great', start_time: 3.0, phrase_id: '0' },
        { type: 'refinement', instruction: 'word-delete', start_time: 1.0 },
        { type: 'refinement', instruction: 'word-insert', start_time: 1.0, replacement_text: 'Tom' },
        { type: 'refinement', instruction: 'word-insert', start_time: 1.5, replacement_text: 'Hanks' }
      ]
    end

    it "applies refinement instructions" do
      text = api.build_transcript_text(records, group_by_paragraph: false)
      expect(text).to eq('Tom Hanks is great')
    end
  end

end
