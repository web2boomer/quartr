require 'json'
require 'logger'
require 'faraday'

module Quartr
  class API
    PRODUCTION_HOST = "https://api.quartr.com/public/"
    DEMO_HOST = "https://api-demo.quartr.com/public/"
    
    JSON_CONTENT_TYPE = 'application/json'

    RETRY_WAIT = 10
    MAX_RETRY = 6    

    DEFAULT_PAGE_LIMIT =  500 # defaults to 10 in API , max 500

    def initialize(apikey = ENV['QUARTR_API_KEY'] )
      @apikey = apikey # fall back on ENV var if non passed in
    end

    # beginning of endpoints, note that there are inconsistencies with some endpoints using hyphens and some underscores. To make this more obvious, hypens are strings.

    def companies(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc', countries: nil, exchanges: nil, tickers: nil, isins: nil, updated_before: nil, updated_after: nil, ids: nil)
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction,
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        isins: isins,
        updatedBefore: updated_before,
        updatedAfter: updated_after,
        ids: ids
      }
      request "v3/companies", params
    end

    def company(company_id: nil, ticker: nil)
      if company_id
        return request "v3/companies/#{company_id}"
      elsif ticker
        # v3 API doesn't support direct ticker lookup, use list endpoint with ticker filter
        result = companies(tickers: ticker, limit: 1)
        return result if result && result['data'] && result['data'].any?
        raise NotFound.new "Company with ticker #{ticker} not found"
      end
    end    

    def events(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc', countries: nil, exchanges: nil, tickers: nil, company_ids: nil, type_ids: nil, start_date: nil, end_date: nil, sort_by: 'id', updated_before: nil, updated_after: nil, isins: nil)
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction,
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        companyIds: company_ids,
        typeIds: type_ids,
        startDate: start_date,
        endDate: end_date,
        sortBy: sort_by,
        updatedBefore: updated_before,
        updatedAfter: updated_after,
        isins: isins
      }
      request "v3/events", params
    end        

    def event(event_id)
      request "v3/events/#{event_id}"
    end     

    def event_types(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc')
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction
      }
      request "v3/event-types", params
    end
    
    
    def live_transcripts(countries: nil, exchanges: nil, tickers: nil, event_ids: nil, states: nil, limit: 500)
      request "v3/live/transcripts", {countries: countries, exchanges: exchanges, tickers: tickers, eventIds: event_ids, states: states, limit: limit}
    end     
    
    def live_transcript(id:)
      request "v3/live/transcripts/#{id}"
    end

    # Live Events
    def live_events(countries: nil, exchanges: nil, tickers: nil, isins: nil, states: nil, limit: DEFAULT_PAGE_LIMIT)
      params = {
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        isins: isins,
        states: states,
        limit: limit
      }
      request "v3/live/events", params
    end

    def live_event(id:)
      request "v3/live/events/#{id}"
    end

    # Live Audio
    def live_audio_list(countries: nil, exchanges: nil, tickers: nil, isins: nil, event_ids: nil, states: nil, limit: DEFAULT_PAGE_LIMIT)
      params = {
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        isins: isins,
        eventIds: event_ids,
        states: states,
        limit: limit
      }
      request "v3/live/audio", params
    end

    def live_audio(id:)
      request "v3/live/audio/#{id}"
    end

    # Stream a live transcript from the given URL (obtained from live_transcript response)
    # Options:
    #   transcript_version: "1.6" or "1.7" (1.7 includes refinement instructions)
    #   poll_interval: seconds between polls (default 2)
    #   
    # Usage with block (streaming):
    #   api.stream_live_transcript(url) do |record|
    #     case record[:type]
    #     when 'start' then puts "Stream started"
    #     when 'entry' then print record[:text] + " "
    #     when 'end' then puts "\nStream ended"
    #     end
    #   end
    #
    # Usage without block (fetch all at once):
    #   records = api.stream_live_transcript(url)
    #   text = records.select { |r| r[:type] == 'entry' }.map { |r| r[:text] }.join(' ')
    #
    def stream_live_transcript(url, transcript_version: nil, poll_interval: 2, &block)
      full_url = transcript_version ? "#{url}?transcriptVersion=#{transcript_version}" : url
      
      if block_given?
        stream_live_transcript_with_block(full_url, poll_interval, &block)
      else
        fetch_live_transcript_records(full_url)
      end
    end

    # Parse a JSONL string of live transcript data into structured records
    def parse_live_transcript_jsonl(jsonl_content)
      records = []
      jsonl_content.each_line do |line|
        line = line.strip
        next if line.empty?
        
        record = parse_live_transcript_record(line)
        records << record if record
      end
      records
    end

    # Build readable text from live transcript records, applying refinement instructions
    def build_transcript_text(records, group_by_paragraph: true, include_indiscernible: false)
      # Separate entries and refinement instructions
      entries = []
      instructions = []
      
      records.each do |record|
        case record[:type]
        when 'entry'
          entries << record.dup
        when 'refinement'
          instructions << record
        end
      end

      # Apply refinement instructions
      instructions.each do |instruction|
        case instruction[:instruction]
        when 'word-update'
          entry = entries.find { |e| e[:start_time] == instruction[:start_time] }
          entry[:text] = instruction[:replacement_text] if entry
        when 'word-insert'
          # Insert at the correct position based on timestamp
          insert_idx = entries.find_index { |e| e[:start_time] >= instruction[:start_time] } || entries.length
          entries.insert(insert_idx, {
            type: 'entry',
            text: instruction[:replacement_text],
            start_time: instruction[:start_time],
            phrase_id: 'inserted'
          })
        when 'word-delete'
          entries.reject! { |e| e[:start_time] == instruction[:start_time] }
        when 'paragraph-insert'
          # Mark the entry that starts a new paragraph
          entry = entries.find { |e| e[:start_time] >= instruction[:start_time] }
          entry[:new_paragraph] = true if entry
        end
      end

      # Build the text
      if group_by_paragraph
        paragraphs = [[]]
        entries.each do |entry|
          next if entry[:text] == '[indiscernible]' && !include_indiscernible
          paragraphs << [] if entry[:new_paragraph]
          paragraphs.last << entry[:text]
        end
        paragraphs.map { |p| p.join(' ') }.reject(&:empty?).join("\n\n")
      else
        entries
          .reject { |e| e[:text] == '[indiscernible]' && !include_indiscernible }
          .map { |e| e[:text] }
          .join(' ')
      end
    end

    # Company Segments
    def company_segments(company_id:)
      request "v3/companies/#{company_id}/segments"
    end

    # Event Summary
    def event_summary(event_id:)
      request "v3/events/#{event_id}/summary"
    end

    # Event Type (single)
    def event_type(event_type_id:)
      request "v3/event-types/#{event_type_id}"
    end

    # Document Types (single)
    def document_type(document_type_id:)
      request "v3/document-types/#{document_type_id}"
    end

    # Documents (generic)
    def documents(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc', countries: nil, exchanges: nil, tickers: nil, company_ids: nil, event_ids: nil, type_ids: nil, start_date: nil, end_date: nil, isins: nil, document_group_ids: nil, updated_before: nil, updated_after: nil)
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction,
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        companyIds: company_ids,
        eventIds: event_ids,
        typeIds: type_ids,
        startDate: start_date,
        endDate: end_date,
        isins: isins,
        documentGroupIds: document_group_ids,
        updatedBefore: updated_before,
        updatedAfter: updated_after
      }
      request "v3/documents", params
    end

    def document(document_id:)
      request "v3/documents/#{document_id}"
    end

    # Document Types
    def document_types(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc')
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction
      }
      request "v3/document-types", params
    end

    # Transcripts
    def transcripts(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc', countries: nil, exchanges: nil, tickers: nil, company_ids: nil, event_ids: nil, type_ids: nil, start_date: nil, end_date: nil, isins: nil, document_group_ids: nil, updated_before: nil, updated_after: nil, expand: nil)
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction,
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        companyIds: company_ids,
        eventIds: event_ids,
        typeIds: type_ids,
        startDate: start_date,
        endDate: end_date,
        isins: isins,
        documentGroupIds: document_group_ids,
        updatedBefore: updated_before,
        updatedAfter: updated_after,
        expand: expand
      }
      request "v3/documents/transcripts", params
    end

    def transcript(transcript_id, expand: nil)
      params = { expand: expand }
      request "v3/documents/transcripts/#{transcript_id}", params
    end

    def transcript_chapters(transcript_id:)
      request "v3/documents/transcripts/#{transcript_id}/chapters"
    end

    def transcript_summary(transcript_id:)
      request "v3/documents/transcripts/#{transcript_id}/summary"
    end

    # Slide Decks
    def slide_decks(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc', countries: nil, exchanges: nil, tickers: nil, company_ids: nil, event_ids: nil, type_ids: nil, start_date: nil, end_date: nil, isins: nil, document_group_ids: nil, updated_before: nil, updated_after: nil, expand: nil)
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction,
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        companyIds: company_ids,
        eventIds: event_ids,
        typeIds: type_ids,
        startDate: start_date,
        endDate: end_date,
        isins: isins,
        documentGroupIds: document_group_ids,
        updatedBefore: updated_before,
        updatedAfter: updated_after,
        expand: expand
      }
      request "v3/documents/slides", params
    end

    def slide_deck(slide_deck_id, expand: nil)
      params = { expand: expand }
      request "v3/documents/slides/#{slide_deck_id}", params
    end

    def slide_deck_pages(slide_deck_id:)
      request "v3/documents/slides/#{slide_deck_id}/pages"
    end

    def slide_deck_summary(slide_deck_id:)
      request "v3/documents/slides/#{slide_deck_id}/summary"
    end

    # Reports
    def reports(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc', countries: nil, exchanges: nil, tickers: nil, company_ids: nil, event_ids: nil, type_ids: nil, start_date: nil, end_date: nil, isins: nil, document_group_ids: nil, updated_before: nil, updated_after: nil, expand: nil)
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction,
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        companyIds: company_ids,
        eventIds: event_ids,
        typeIds: type_ids,
        startDate: start_date,
        endDate: end_date,
        isins: isins,
        documentGroupIds: document_group_ids,
        updatedBefore: updated_before,
        updatedAfter: updated_after,
        expand: expand
      }
      request "v3/documents/reports", params
    end

    def report(report_id, expand: nil)
      params = { expand: expand }
      request "v3/documents/reports/#{report_id}", params
    end

    def report_pages(report_id:)
      request "v3/documents/reports/#{report_id}/pages"
    end

    def report_summary(report_id:)
      request "v3/documents/reports/#{report_id}/summary"
    end

    # Backlog Audio
    def backlog_audio(limit: DEFAULT_PAGE_LIMIT, cursor: 0, direction: 'asc', countries: nil, exchanges: nil, tickers: nil, company_ids: nil, event_ids: nil, type_ids: nil, start_date: nil, end_date: nil, isins: nil, updated_before: nil, updated_after: nil)
      params = {
        limit: limit,
        cursor: cursor,
        direction: direction,
        countries: countries,
        exchanges: exchanges,
        tickers: tickers,
        companyIds: company_ids,
        eventIds: event_ids,
        typeIds: type_ids,
        startDate: start_date,
        endDate: end_date,
        isins: isins,
        updatedBefore: updated_before,
        updatedAfter: updated_after
      }
      request "v3/backlog/audio", params
    end

    def backlog_audio_item(audio_id:)
      request "v3/backlog/audio/#{audio_id}"
    end

    def backlog_audio_chapters(audio_id:)
      request "v3/backlog/audio/#{audio_id}/chapters"
    end

    private

      def stream_live_transcript_with_block(url, poll_interval)
        last_position = 0
        stream_ended = false

        until stream_ended
          begin
            conn = Faraday.new
            response = conn.get(url) do |req|
              req.headers['Range'] = "bytes=#{last_position}-" if last_position > 0
              req.headers['Cache-Control'] = 'no-cache'
            end

            if response.success?
              new_content = response.body
              last_position += new_content.bytesize

              new_content.each_line do |line|
                record = parse_live_transcript_record(line.strip)
                next unless record
                
                yield record
                stream_ended = true if record[:type] == 'end'
              end
            elsif response.status == 416 # Range not satisfiable - no new content
              # No new content yet, wait and retry
            else
              raise ServiceUnavailable.new "Failed to fetch live transcript: #{response.status}"
            end

            sleep poll_interval unless stream_ended
          rescue Faraday::Error => e
            logger.warn "Connection error while streaming: #{e.message}, retrying..."
            sleep poll_interval
          end
        end
      end

      def fetch_live_transcript_records(url)
        conn = Faraday.new
        response = conn.get(url) do |req|
          req.headers['Cache-Control'] = 'no-cache'
        end

        raise ServiceUnavailable.new "Failed to fetch live transcript: #{response.status}" unless response.success?
        
        parse_live_transcript_jsonl(response.body)
      end

      def parse_live_transcript_record(line)
        return nil if line.empty?
        
        begin
          json = JSON.parse(line)
        rescue JSON::ParserError
          logger.warn "Failed to parse transcript line: #{line}"
          return nil
        end

        # Check for refinement instructions first (v1.7) - they have 'i' field instead of 'type'
        if json['i']
          return {
            type: 'refinement',
            instruction: json['i'],
            start_time: json['s']&.to_f,
            end_time: json['e']&.to_f,
            replacement_text: json['rt']
          }
        end

        type = json['type'] || 'entry'

        case type
        when 'start'
          {
            type: 'start',
            file_format_version: json['file_format_version']
          }
        when 'entry', nil
          # Entry is the default type when no type is specified
          record = {
            type: 'entry',
            text: json['t'],
            start_time: json['s']&.to_f,
            end_time: json['e']&.to_f,
            phrase_id: json['p'],
            speaker_index: json['S']
          }
          record[:confidence] = json['c'].to_f if json['c']
          record[:original_text] = json['ot'] if json['ot']
          record
        when 'end'
          {
            type: 'end',
            code: json['code'],
            system_reason: json['system_reason'],
            user_reason: json['user_reason']
          }
        when 'interruption'
          {
            type: 'interruption',
            time: json['time']&.to_f,
            restarting: json['restarting']
          }
        when 'keep-alive'
          { type: 'keep-alive' }
        when 'section'
          {
            type: 'section',
            name: json['name'],
            start_time: json['s']&.to_f,
            end_time: json['e']&.to_f
          }
        else
          # Unknown type - return raw for forward compatibility
          { type: type, raw: json }
        end
      end

      def request(endpoint, params = Hash.new, the_body = nil)
        retries = 0

        begin


          params = params.compact # get rid of nil values in params 
          
          chosen_host = ENV['QUARTR_DEMO'] == "yes" ? DEMO_HOST : PRODUCTION_HOST
          full_endpoint_url = "#{chosen_host}#{endpoint}"
          conn = Faraday.new(url: chosen_host)

          request_type = the_body ? "post" : "get"

          response = conn.send(request_type, endpoint) do |request|
            request.params = params
            request.headers['Content-Type'] = 'application/json'
            request.body =  the_body.to_json if the_body
            request.headers['X-Api-Key'] = @apikey
          end

          # logger.debug response.env.url
          # logger.debug response.headers
          # logger.debug response.status
          # logger.debug response.body

          if response.status == 500
            raise ServerError.new response.body          

          elsif response.status == 403 || response.status == 401
            raise AccessDenied.new response.body

          elsif response.status == 404
            raise NotFound.new response.body 
            
          elsif response.status == 502
            raise ServerError.new "#{response.status} Bad Gateway"                  

          elsif response.status == 504
            raise ServiceUnavailable.new "#{response.status} Gateway Timeout"

          elsif response.status != 200
            error_message = JSON.parse response.body
            raise ServiceUnavailable.new "#{response.status} #{error_message["Error Message"]}"

          # elsif !response.headers['content-type'].include? JSON_CONTENT_TYPE
          #   raise InvalidResponse.new response.body

          elsif response.success?
            parsed_response = JSON.parse response.body
            # parsed_response['data']
            return parsed_response

          else
            raise Error.new response.body
          end




        rescue ServiceUnavailable => exception

          if retries < MAX_RETRY
            retries += 1
            logger.info("Service unavailable due to #{exception.message}, retrying (attempt #{retries} of #{MAX_RETRY})...")
            sleep RETRY_WAIT
            retry
          else
            raise exception
          end
        end
      end


      def logger
        @logger ||= Logger.new(STDOUT)
      end

  end
end

