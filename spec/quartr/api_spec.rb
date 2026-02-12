# frozen_string_literal: true

require "spec_helper"

RSpec.describe Quartr::API do
  let(:api_key) { "test-api-key-123" }
  let(:api) { described_class.new(api_key) }
  let(:base_url) { "https://api.quartr.com/public" }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Use regex matching so query params don't cause stub mismatches
  def stub_quartr(method, path, status: 200, body: {})
    stub_request(method, /#{Regexp.escape("#{base_url}/#{path}")}/)
      .to_return(
        status: status,
        body: body.is_a?(String) ? body : body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def expect_quartr_request(method, path, query: {})
    expect(WebMock).to have_requested(method, /#{Regexp.escape("#{base_url}/#{path}")}/)
      .with(query: hash_including(query))
  end

  # ---------------------------------------------------------------------------
  # Initialization
  # ---------------------------------------------------------------------------

  describe "#initialize" do
    it "accepts an explicit API key" do
      client = described_class.new("my-key")
      stub_quartr(:get, "v3/companies", body: { "data" => [] })
      client.companies
      expect(WebMock).to have_requested(:get, /v3\/companies/)
        .with(headers: { "X-Api-Key" => "my-key" })
    end

    it "falls back to QUARTR_API_KEY env var" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("QUARTR_API_KEY").and_return("env-key")
      client = described_class.new
      stub_quartr(:get, "v3/companies", body: { "data" => [] })
      client.companies
      expect(WebMock).to have_requested(:get, /v3\/companies/)
        .with(headers: { "X-Api-Key" => "env-key" })
    end

    it "uses demo host when QUARTR_DEMO=yes" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("QUARTR_DEMO").and_return("yes")
      allow(ENV).to receive(:[]).with("QUARTR_API_KEY").and_return(api_key)

      stub_request(:get, /api-demo\.quartr\.com/).to_return(
        status: 200,
        body: { "data" => [] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      client = described_class.new
      client.companies
      expect(WebMock).to have_requested(:get, /api-demo\.quartr\.com/)
    end
  end

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  describe "constants" do
    it "defines production host" do
      expect(described_class::PRODUCTION_HOST).to eq("https://api.quartr.com/public/")
    end

    it "defines demo host" do
      expect(described_class::DEMO_HOST).to eq("https://api-demo.quartr.com/public/")
    end

    it "defines retry config" do
      expect(described_class::MAX_RETRY).to eq(6)
      expect(described_class::RETRY_WAIT).to eq(10)
    end

    it "defines default page limit" do
      expect(described_class::DEFAULT_PAGE_LIMIT).to eq(500)
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    it "raises AccessDenied on 401" do
      stub_quartr(:get, "v3/companies", status: 401, body: "Unauthorized")
      expect { api.companies }.to raise_error(Quartr::AccessDenied)
    end

    it "raises AccessDenied on 403" do
      stub_quartr(:get, "v3/companies", status: 403, body: "Forbidden")
      expect { api.companies }.to raise_error(Quartr::AccessDenied)
    end

    it "raises NotFound on 404" do
      stub_quartr(:get, "v3/events/99999", status: 404, body: "Not Found")
      expect { api.event(99999) }.to raise_error(Quartr::NotFound)
    end

    it "raises ServerError on 500" do
      stub_quartr(:get, "v3/companies", status: 500, body: "Internal Server Error")
      expect { api.companies }.to raise_error(Quartr::ServerError)
    end

    it "raises ServerError on 502 Bad Gateway" do
      stub_quartr(:get, "v3/companies", status: 502, body: "Bad Gateway")
      expect { api.companies }.to raise_error(Quartr::ServerError, /Bad Gateway/)
    end

    it "raises ServiceUnavailable on 504 and retries" do
      stub_quartr(:get, "v3/companies", status: 504, body: "Gateway Timeout")
      allow(api).to receive(:sleep) # skip real sleep during retry

      expect { api.companies }.to raise_error(Quartr::ServiceUnavailable, /Gateway Timeout/)
    end

    it "raises ServiceUnavailable for other non-200 status codes" do
      stub_quartr(:get, "v3/companies", status: 429, body: { "Error Message" => "Rate limited" })
      allow(api).to receive(:sleep)

      expect { api.companies }.to raise_error(Quartr::ServiceUnavailable, /Rate limited/)
    end
  end

  # ---------------------------------------------------------------------------
  # Retry logic
  # ---------------------------------------------------------------------------

  describe "retry logic" do
    it "retries on ServiceUnavailable up to MAX_RETRY times then raises" do
      stub_quartr(:get, "v3/companies", status: 504, body: "Gateway Timeout")
      allow(api).to receive(:sleep)

      expect { api.companies }.to raise_error(Quartr::ServiceUnavailable)
      # Initial request + MAX_RETRY retries
      expect(a_request(:get, /v3\/companies/)).to have_been_made.times(7)
    end

    it "recovers when retry succeeds" do
      call_count = 0
      stub_request(:get, /v3\/companies/)
        .to_return do |_request|
          call_count += 1
          if call_count < 3
            { status: 504, body: "Gateway Timeout" }
          else
            { status: 200, body: { "data" => [{ "id" => 1 }] }.to_json,
              headers: { "Content-Type" => "application/json" } }
          end
        end
      allow(api).to receive(:sleep)

      result = api.companies
      expect(result["data"]).to eq([{ "id" => 1 }])
      expect(call_count).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # Companies
  # ---------------------------------------------------------------------------

  describe "#companies" do
    it "fetches companies with default params" do
      stub_quartr(:get, "v3/companies", body: { "data" => [{ "id" => 1, "name" => "Apple" }] })
      result = api.companies
      expect(result["data"].first["name"]).to eq("Apple")
      expect_quartr_request(:get, "v3/companies", query: { "limit" => "500", "cursor" => "0", "direction" => "asc" })
    end

    it "passes filter parameters" do
      stub_quartr(:get, "v3/companies", body: { "data" => [] })
      api.companies(countries: "US", exchanges: "NASDAQ", tickers: "AAPL", limit: 10)
      expect_quartr_request(:get, "v3/companies", query: {
        "countries" => "US",
        "exchanges" => "NASDAQ",
        "tickers" => "AAPL",
        "limit" => "10"
      })
    end

    it "omits nil parameters" do
      stub_quartr(:get, "v3/companies", body: { "data" => [] })
      api.companies(countries: nil, isins: nil)
      expect(WebMock).to have_requested(:get, /v3\/companies/)
        .with { |req| !req.uri.query.include?("countries") && !req.uri.query.include?("isins") }
    end
  end

  # ---------------------------------------------------------------------------
  # Company
  # ---------------------------------------------------------------------------

  describe "#company" do
    it "fetches company by ID" do
      stub_quartr(:get, "v3/companies/3624", body: { "id" => 3624, "name" => "NVIDIA" })
      result = api.company(company_id: 3624)
      expect(result["name"]).to eq("NVIDIA")
    end

    it "fetches company by ticker" do
      stub_quartr(:get, "v3/companies",
        body: { "data" => [{ "id" => 3624, "name" => "NVIDIA", "ticker" => "NVDA" }] })
      result = api.company(ticker: "NVDA")
      expect(result["data"].first["ticker"]).to eq("NVDA")
    end

    it "raises NotFound when ticker yields no results" do
      stub_quartr(:get, "v3/companies", body: { "data" => [] })
      expect { api.company(ticker: "XXXXXX") }.to raise_error(Quartr::NotFound, /XXXXXX/)
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  describe "#events" do
    it "fetches events with default params" do
      stub_quartr(:get, "v3/events", body: { "data" => [{ "id" => 1 }] })
      result = api.events
      expect(result["data"].first["id"]).to eq(1)
    end

    it "passes date range and company filters" do
      stub_quartr(:get, "v3/events", body: { "data" => [] })
      api.events(company_ids: "1,2", start_date: "2025-01-01", end_date: "2025-12-31")
      expect_quartr_request(:get, "v3/events", query: {
        "companyIds" => "1,2",
        "startDate" => "2025-01-01",
        "endDate" => "2025-12-31"
      })
    end
  end

  describe "#event" do
    it "fetches a single event by ID" do
      stub_quartr(:get, "v3/events/256", body: { "id" => 256, "title" => "Earnings Call" })
      result = api.event(256)
      expect(result["title"]).to eq("Earnings Call")
    end
  end

  describe "#event_summary" do
    it "fetches event summary" do
      stub_quartr(:get, "v3/events/256/summary", body: { "summary" => "Q1 results" })
      result = api.event_summary(event_id: 256)
      expect(result["summary"]).to eq("Q1 results")
    end
  end

  describe "#event_types" do
    it "fetches event types" do
      stub_quartr(:get, "v3/event-types", body: { "data" => [{ "id" => 1, "name" => "Earnings" }] })
      result = api.event_types
      expect(result["data"].first["name"]).to eq("Earnings")
    end
  end

  describe "#event_type" do
    it "fetches a single event type" do
      stub_quartr(:get, "v3/event-types/1", body: { "id" => 1, "name" => "Earnings" })
      result = api.event_type(event_type_id: 1)
      expect(result["name"]).to eq("Earnings")
    end
  end

  # ---------------------------------------------------------------------------
  # Live Transcripts
  # ---------------------------------------------------------------------------

  describe "#live_transcripts" do
    it "fetches live transcripts" do
      stub_quartr(:get, "v3/live/transcripts", body: { "data" => [{ "id" => 10 }] })
      result = api.live_transcripts
      expect(result["data"].first["id"]).to eq(10)
    end

    it "passes filters" do
      stub_quartr(:get, "v3/live/transcripts", body: { "data" => [] })
      api.live_transcripts(tickers: "AAPL", states: "completed")
      expect_quartr_request(:get, "v3/live/transcripts", query: { "tickers" => "AAPL", "states" => "completed" })
    end
  end

  describe "#live_transcript" do
    it "fetches a single live transcript" do
      stub_quartr(:get, "v3/live/transcripts/10", body: { "id" => 10, "url" => "https://example.com/t.jsonl" })
      result = api.live_transcript(id: 10)
      expect(result["url"]).to eq("https://example.com/t.jsonl")
    end
  end

  # ---------------------------------------------------------------------------
  # Live Events
  # ---------------------------------------------------------------------------

  describe "#live_events" do
    it "fetches live events" do
      stub_quartr(:get, "v3/live/events", body: { "data" => [{ "id" => 5 }] })
      result = api.live_events
      expect(result["data"].first["id"]).to eq(5)
    end
  end

  describe "#live_event" do
    it "fetches a single live event" do
      stub_quartr(:get, "v3/live/events/5", body: { "id" => 5 })
      result = api.live_event(id: 5)
      expect(result["id"]).to eq(5)
    end
  end

  # ---------------------------------------------------------------------------
  # Live Audio
  # ---------------------------------------------------------------------------

  describe "#live_audio_list" do
    it "fetches live audio list" do
      stub_quartr(:get, "v3/live/audio", body: { "data" => [{ "id" => 7 }] })
      result = api.live_audio_list
      expect(result["data"].first["id"]).to eq(7)
    end
  end

  describe "#live_audio" do
    it "fetches a single live audio" do
      stub_quartr(:get, "v3/live/audio/7", body: { "id" => 7, "state" => "live" })
      result = api.live_audio(id: 7)
      expect(result["state"]).to eq("live")
    end
  end

  # ---------------------------------------------------------------------------
  # Documents
  # ---------------------------------------------------------------------------

  describe "#documents" do
    it "fetches documents" do
      stub_quartr(:get, "v3/documents", body: { "data" => [{ "id" => 100 }] })
      result = api.documents
      expect(result["data"].first["id"]).to eq(100)
    end

    it "passes type and event filters" do
      stub_quartr(:get, "v3/documents", body: { "data" => [] })
      api.documents(type_ids: "1,2", event_ids: "10")
      expect_quartr_request(:get, "v3/documents", query: { "typeIds" => "1,2", "eventIds" => "10" })
    end
  end

  describe "#document" do
    it "fetches a single document" do
      stub_quartr(:get, "v3/documents/100", body: { "id" => 100, "title" => "Transcript" })
      result = api.document(document_id: 100)
      expect(result["title"]).to eq("Transcript")
    end
  end

  describe "#document_types" do
    it "fetches document types" do
      stub_quartr(:get, "v3/document-types", body: { "data" => [{ "id" => 1 }] })
      result = api.document_types
      expect(result["data"].first["id"]).to eq(1)
    end
  end

  describe "#document_type" do
    it "fetches a single document type" do
      stub_quartr(:get, "v3/document-types/1", body: { "id" => 1, "name" => "Transcript" })
      result = api.document_type(document_type_id: 1)
      expect(result["name"]).to eq("Transcript")
    end
  end

  # ---------------------------------------------------------------------------
  # Transcripts
  # ---------------------------------------------------------------------------

  describe "#transcripts" do
    it "fetches transcripts" do
      stub_quartr(:get, "v3/documents/transcripts", body: { "data" => [{ "id" => 200 }] })
      result = api.transcripts
      expect(result["data"].first["id"]).to eq(200)
    end
  end

  describe "#transcript" do
    it "fetches a single transcript" do
      stub_quartr(:get, "v3/documents/transcripts/200", body: { "id" => 200, "text" => "..." })
      result = api.transcript(200)
      expect(result["id"]).to eq(200)
    end

    it "passes expand parameter" do
      stub_quartr(:get, "v3/documents/transcripts/200", body: { "id" => 200 })
      api.transcript(200, expand: "chapters")
      expect_quartr_request(:get, "v3/documents/transcripts/200", query: { "expand" => "chapters" })
    end
  end

  describe "#transcript_chapters" do
    it "fetches transcript chapters" do
      stub_quartr(:get, "v3/documents/transcripts/200/chapters", body: { "data" => [] })
      result = api.transcript_chapters(transcript_id: 200)
      expect(result).to have_key("data")
    end
  end

  describe "#transcript_summary" do
    it "fetches transcript summary" do
      stub_quartr(:get, "v3/documents/transcripts/200/summary", body: { "summary" => "Q1" })
      result = api.transcript_summary(transcript_id: 200)
      expect(result["summary"]).to eq("Q1")
    end
  end

  # ---------------------------------------------------------------------------
  # Slide Decks
  # ---------------------------------------------------------------------------

  describe "#slide_decks" do
    it "fetches slide decks" do
      stub_quartr(:get, "v3/documents/slides", body: { "data" => [{ "id" => 300 }] })
      result = api.slide_decks
      expect(result["data"].first["id"]).to eq(300)
    end
  end

  describe "#slide_deck" do
    it "fetches a single slide deck" do
      stub_quartr(:get, "v3/documents/slides/300", body: { "id" => 300 })
      result = api.slide_deck(300)
      expect(result["id"]).to eq(300)
    end
  end

  describe "#slide_deck_pages" do
    it "fetches slide deck pages" do
      stub_quartr(:get, "v3/documents/slides/300/pages", body: { "data" => [] })
      result = api.slide_deck_pages(slide_deck_id: 300)
      expect(result).to have_key("data")
    end
  end

  describe "#slide_deck_summary" do
    it "fetches slide deck summary" do
      stub_quartr(:get, "v3/documents/slides/300/summary", body: { "summary" => "Deck" })
      result = api.slide_deck_summary(slide_deck_id: 300)
      expect(result["summary"]).to eq("Deck")
    end
  end

  # ---------------------------------------------------------------------------
  # Reports
  # ---------------------------------------------------------------------------

  describe "#reports" do
    it "fetches reports" do
      stub_quartr(:get, "v3/documents/reports", body: { "data" => [{ "id" => 400 }] })
      result = api.reports
      expect(result["data"].first["id"]).to eq(400)
    end
  end

  describe "#report" do
    it "fetches a single report" do
      stub_quartr(:get, "v3/documents/reports/400", body: { "id" => 400 })
      result = api.report(400)
      expect(result["id"]).to eq(400)
    end
  end

  describe "#report_pages" do
    it "fetches report pages" do
      stub_quartr(:get, "v3/documents/reports/400/pages", body: { "data" => [] })
      result = api.report_pages(report_id: 400)
      expect(result).to have_key("data")
    end
  end

  describe "#report_summary" do
    it "fetches report summary" do
      stub_quartr(:get, "v3/documents/reports/400/summary", body: { "summary" => "Annual" })
      result = api.report_summary(report_id: 400)
      expect(result["summary"]).to eq("Annual")
    end
  end

  # ---------------------------------------------------------------------------
  # Company Segments
  # ---------------------------------------------------------------------------

  describe "#company_segments" do
    it "fetches segments for a company" do
      stub_quartr(:get, "v3/companies/3624/segments", body: { "data" => [{ "name" => "GPU" }] })
      result = api.company_segments(company_id: 3624)
      expect(result["data"].first["name"]).to eq("GPU")
    end
  end

  # ---------------------------------------------------------------------------
  # Backlog Audio
  # ---------------------------------------------------------------------------

  describe "#backlog_audio" do
    it "fetches backlog audio" do
      stub_quartr(:get, "v3/backlog/audio", body: { "data" => [{ "id" => 500 }] })
      result = api.backlog_audio
      expect(result["data"].first["id"]).to eq(500)
    end

    it "passes filters" do
      stub_quartr(:get, "v3/backlog/audio", body: { "data" => [] })
      api.backlog_audio(tickers: "MSFT", start_date: "2025-01-01")
      expect_quartr_request(:get, "v3/backlog/audio", query: { "tickers" => "MSFT", "startDate" => "2025-01-01" })
    end
  end

  describe "#backlog_audio_item" do
    it "fetches a single backlog audio item" do
      stub_quartr(:get, "v3/backlog/audio/500", body: { "id" => 500 })
      result = api.backlog_audio_item(audio_id: 500)
      expect(result["id"]).to eq(500)
    end
  end

  describe "#backlog_audio_chapters" do
    it "fetches backlog audio chapters" do
      stub_quartr(:get, "v3/backlog/audio/500/chapters", body: { "data" => [] })
      result = api.backlog_audio_chapters(audio_id: 500)
      expect(result).to have_key("data")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_live_transcript_jsonl
  # ---------------------------------------------------------------------------

  describe "#parse_live_transcript_jsonl" do
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
      expect(section[:start_time]).to eq(1.0)
    end

    it "parses keep-alive records" do
      keep_alive = subject.find { |r| r[:type] == 'keep-alive' }
      expect(keep_alive).not_to be_nil
    end

    it "parses end record" do
      end_record = subject.find { |r| r[:type] == 'end' }
      expect(end_record).not_to be_nil
    end

    it "skips empty lines" do
      jsonl_with_blanks = "\n{\"type\": \"end\"}\n\n"
      result = api.parse_live_transcript_jsonl(jsonl_with_blanks)
      expect(result.length).to eq(1)
    end

    it "skips lines with invalid JSON" do
      jsonl_with_bad = "not json\n{\"type\": \"end\"}\n"
      result = api.parse_live_transcript_jsonl(jsonl_with_bad)
      expect(result.length).to eq(1)
    end

    it "parses end record with reason codes" do
      jsonl = '{"type": "end", "code": 1000, "system_reason": "completed", "user_reason": "done"}'
      result = api.parse_live_transcript_jsonl(jsonl)
      expect(result.first[:code]).to eq(1000)
      expect(result.first[:system_reason]).to eq("completed")
      expect(result.first[:user_reason]).to eq("done")
    end

    it "parses interruption records" do
      jsonl = '{"type": "interruption", "time": 42.5, "restarting": true}'
      result = api.parse_live_transcript_jsonl(jsonl)
      expect(result.first[:type]).to eq('interruption')
      expect(result.first[:time]).to eq(42.5)
      expect(result.first[:restarting]).to eq(true)
    end

    it "preserves unknown record types for forward compatibility" do
      jsonl = '{"type": "new-future-type", "foo": "bar"}'
      result = api.parse_live_transcript_jsonl(jsonl)
      expect(result.first[:type]).to eq('new-future-type')
      expect(result.first[:raw]).to eq({ "type" => "new-future-type", "foo" => "bar" })
    end
  end

  # ---------------------------------------------------------------------------
  # parse_live_transcript_jsonl v1.7 refinements
  # ---------------------------------------------------------------------------

  describe "#parse_live_transcript_jsonl with v1.7 refinements" do
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

    it "parses word-update instruction" do
      jsonl = '{"i": "word-update", "s": 1.0, "e": 2.0, "rt": "Thomas"}'
      result = api.parse_live_transcript_jsonl(jsonl)
      expect(result.first[:type]).to eq('refinement')
      expect(result.first[:instruction]).to eq('word-update')
      expect(result.first[:replacement_text]).to eq('Thomas')
    end
  end

  # ---------------------------------------------------------------------------
  # build_transcript_text
  # ---------------------------------------------------------------------------

  describe "#build_transcript_text" do
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

    it "groups by paragraph by default" do
      paragraph_records = [
        { type: 'entry', text: 'First', start_time: 0.1, phrase_id: '0' },
        { type: 'entry', text: 'paragraph.', start_time: 0.5, phrase_id: '0' },
        { type: 'entry', text: 'Second', start_time: 1.0, phrase_id: '1', new_paragraph: true },
        { type: 'entry', text: 'paragraph.', start_time: 1.5, phrase_id: '1' }
      ]
      text = api.build_transcript_text(paragraph_records)
      expect(text).to eq("First paragraph.\n\nSecond paragraph.")
    end

    it "returns empty string for records with no entries" do
      text = api.build_transcript_text([{ type: 'start' }, { type: 'end' }], group_by_paragraph: false)
      expect(text).to eq('')
    end
  end

  # ---------------------------------------------------------------------------
  # build_transcript_text with refinements
  # ---------------------------------------------------------------------------

  describe "#build_transcript_text with refinements" do
    it "applies word-delete and word-insert refinements" do
      records = [
        { type: 'entry', text: 'TomHanks', start_time: 1.0, phrase_id: '0' },
        { type: 'entry', text: 'is', start_time: 2.0, phrase_id: '0' },
        { type: 'entry', text: 'great', start_time: 3.0, phrase_id: '0' },
        { type: 'refinement', instruction: 'word-delete', start_time: 1.0 },
        { type: 'refinement', instruction: 'word-insert', start_time: 1.0, replacement_text: 'Tom' },
        { type: 'refinement', instruction: 'word-insert', start_time: 1.5, replacement_text: 'Hanks' }
      ]
      text = api.build_transcript_text(records, group_by_paragraph: false)
      expect(text).to eq('Tom Hanks is great')
    end

    it "applies word-update refinements" do
      records = [
        { type: 'entry', text: 'Hello', start_time: 1.0, phrase_id: '0' },
        { type: 'entry', text: 'wrld', start_time: 2.0, phrase_id: '0' },
        { type: 'refinement', instruction: 'word-update', start_time: 2.0, replacement_text: 'world' }
      ]
      text = api.build_transcript_text(records, group_by_paragraph: false)
      expect(text).to eq('Hello world')
    end

    it "applies paragraph-insert refinements" do
      records = [
        { type: 'entry', text: 'First', start_time: 1.0, phrase_id: '0' },
        { type: 'entry', text: 'sentence.', start_time: 2.0, phrase_id: '0' },
        { type: 'entry', text: 'New', start_time: 3.0, phrase_id: '1' },
        { type: 'entry', text: 'paragraph.', start_time: 4.0, phrase_id: '1' },
        { type: 'refinement', instruction: 'paragraph-insert', start_time: 3.0 }
      ]
      text = api.build_transcript_text(records, group_by_paragraph: true)
      expect(text).to eq("First sentence.\n\nNew paragraph.")
    end
  end
end
