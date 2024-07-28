require_relative "quartr/version"
require_relative "quartr/api"

module Quartr
  class Error < StandardError; end
  class AccessDenied < Error; end
  class ServiceUnavailable < Error; end
  class InvalidResponse < Error; end
end
