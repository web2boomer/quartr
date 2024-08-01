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

    def initialize(apikey = ENV['QUARTR_API_KEY'] )
      @apikey = apikey # fall back on ENV var if non passed in
    end

    # beginning of endpoints, note that there are inconsistencies with some endpoints using hyphens and some underscores. To make this more obvious, hypens are strings.

    def companies(limit: nil, page: nil )
      request "v2/companies", {limit: limit , page: page}
    end

    # def search_ticker(query:)
    #   request "v3/search-ticker", {query: query}
    # end


    private

      def request(endpoint, params = Hash.new)
        retries = 0

        begin
          
          chosen_host = ENV['QUARTR_DEMO'] == "yes" ? DEMO_HOST : PRODUCTION_HOST
          full_endpoint_url = "#{chosen_host}#{endpoint}"
          conn = Faraday.new(url: chosen_host)

          response = conn.get(endpoint, params) do |req|
            # req.body = params.to_json
            req.headers['X-Api-Key'] = @apikey
          end

          # logger.debug response.env.url
          # logger.debug response.headers
          # logger.debug args
          # logger.debug response.status
          # logger.debug response.body

          if response.status == 403 || response.status == 401
            raise AccessDenied.new response.body

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

