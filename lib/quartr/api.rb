require 'json'
require 'logger'
require 'faraday'

module Quartr
  class API
    # HOST = "https://api.quartr.com/public/"
    HOST = "https://api-demo.quartr.com/public/"
    
    
    JSON_CONTENT_TYPE = 'application/json'

    RETRY_WAIT = 10
    MAX_RETRY = 6    

    def initialize(apikey = ENV['QUARTR_API_KEY'] )
      @apikey = apikey # fall back on ENV var if non passed in
    end

    # beginning of endpoints, note that there are inconsistencies with some endpoints using hyphens and some underscores. To make this more obvious, hypens are strings.

    def companies
      request "v2/companies"
    end

    # def search_ticker(query:)
    #   request "v3/search-ticker", {query: query}
    # end


    private

      def request(endpoint, params = Hash.new)
        retries = 0

        begin
          full_endpoint_url = "#{HOST}#{endpoint}"

          url = URI(full_endpoint_url)
          http = Net::HTTP.new(url.host, url.port)
          http.use_ssl = true
          
          request = Net::HTTP::Get.new(url)
          request["X-Api-Key"] = @apikey
          
          response = http.request(request)
          puts response.read_body


          logger.debug @apikey
          # logger.debug response.env.url
          # logger.debug response.headers
          # logger.debug args
          # logger.debug response.status
          logger.debug response.read_body

          return

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

