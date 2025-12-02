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
    
    
    def live_transcripts(countries: nil, exchanges: nil, tickers: nil, event_ids: nil, states: nil, limit: 500)
      request "v3/live/transcripts", {countries: countries, exchanges: exchanges, tickers: tickers, eventIds: event_ids, states: states, limit: limit}
    end     
    
    def live_transcript(id: )
      request "v3/live/transcripts/#{id}"
    end     


    private

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
            return JSON.parse response.body

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

