require 'net/http'
require 'json'

module SchemaRegistry
  class ResponseError < Error
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  RESPONSE_ERROR_CODES = {
    40401 => (SubjectNotFound           = Class.new(SchemaRegistry::ResponseError)),
    40402 => (VersionNotFound           = Class.new(SchemaRegistry::ResponseError)),
    40403 => (SchemaNotFound            = Class.new(SchemaRegistry::ResponseError)),
    42201 => (InvalidAvroSchema         = Class.new(SchemaRegistry::ResponseError)),
    42202 => (InvalidVersion            = Class.new(SchemaRegistry::ResponseError)),
    42203 => (InvalidCompatibilityLevel = Class.new(SchemaRegistry::ResponseError)),
    409   => (IncompatibleAvroSchema    = Class.new(SchemaRegistry::ResponseError)),
  }

  class Client

    attr_reader :endpoint, :username, :password

    def initialize(endpoint, username = nil, password = nil)
      @endpoint = URI(endpoint)
      @username, @password = username, password
    end

    def schema(id)
      request(:get, "/schemas/ids/#{id}")['schema']
    end

    def subjects
      data = request(:get, "/subjects")
      data.map { |subject| SchemaRegistry::Subject.new(self, subject) }
    end

    def subject(name)
      SchemaRegistry::Subject.new(self, name)
    end

    def default_compatibility_level
      request(:get, "/config")["compatibilityLevel"]
    end

    def default_compatibility_level=(level)
      request(:put, "/config", compatibility: level)
    end

    def request(method, path, body = nil)
      Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: endpoint.scheme == 'https') do |http|
        request_class = case method
          when :get;    Net::HTTP::Get
          when :post;   Net::HTTP::Post
          when :put;    Net::HTTP::Put
          when :delete; Net::HTTP::Delete
          else raise ArgumentError, "Unsupported request method"
        end

        request = request_class.new(path)
        request.basic_auth(username, password) if username && password
        request['Accept'] = "application/vnd.schemaregistry.v1+json"
        if body
          request['Content-Type'] = "application/json"
          request.body = JSON.dump(body)
        end

        response = http.request(request)
        response_data = JSON.parse(response.body)
        case response
        when Net::HTTPSuccess;
          response_data
        else
          error_class = RESPONSE_ERROR_CODES[response_data['error_code']] || SchemaRegistry::ResponseError
          raise error_class.new(response_data['error_code'], response_data['message'])
        end
      end
    end
  end
end