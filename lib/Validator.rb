require 'uri'
require 'colorize'
require 'json'

require_relative 'MyLogger'

class Validator
    # NOTE:
    # Calls to an object's super class is for custom objects like Employees.
    # This prevents us from having to expand the list when future
    # custom objects are added
    NOUNS = %w[
        AccessLevels
        Albums
        AlternateStores
        AspectRatios
        Categories
        CopyrightHolders
        CopyrightPolicies
        EmployeeKeywords
        EmployeeKeywordCategories
        CustomObject
        FieldLookupStrings
        Fields
        Files
        Groups
        Keywords
        KeywordCategories
        Photographers
        Projects
        ProjectKeywords
        ProjectKeywordCategories
        Searches
        SearchItems
        Sizes
        TextRewrites
        Users
    ].freeze

    # Multi-line regex to match latitude and longitude
    # values that fall within the correct range:
    # +90.0, -127.554334 => Match
    # -90., -180. => No Match
    REGEX = %r{^[-+]?([1-8]?\d(\.\d+)?|90(\.0+)?)
            \s*,\s*
            [-+]?(180(\.0+)?|((1[0-7]\d)|([1-9]?\d))(\.\d+)?)$}x

    ACCEPTED_KEYS = ['latitude','longitude'].freeze

    def self.coordinates_valid?(value)
        REGEX.match(value)
    end

    #Validate the right object type is passed for Noun's constructor
    def self.validate_argument(arg,val='NOUN',options=nil) # Options lets us specify more allowed arg types
        obj = {}
        unless arg.is_a?(NilClass) || arg.is_a?(Hash)
            options = options ? ", #{options}, " : ' '
            msg = "Argument Validation Error: Expected no argument#{options}or a Hash to create #{val} object." +
                  "\nInstead got a(n) #{arg.class} with contents => #{arg.inspect}"
            Logging.logger.error(msg)
            Thread.exit
        end
        if arg.is_a?(Hash)
            # Convert all keys to strings in case user passes symbols as keys so values can be extracted
            obj = arg.each_with_object({}) { |pair,hash| hash[pair.first.to_s] = pair.last }
        end
        obj # Return arg or empty hash in case arg is nil
    end

    def self.process_http_response(response,verbose=nil,resource='',http_method='')
        if response.kind_of? Net::HTTPSuccess
            msg = "Success: HTTP => #{response.code} #{response.message}"
            Logging.logger.info(msg.green)
        elsif response.kind_of? Net::HTTPRedirection
            location = response['location']
            msg      = "Unexpected Redirect to #{location}"
            Logging.logger.error(msg.yellow)
        elsif response.kind_of? Net::HTTPUnauthorized
            msg = "Error: #{response.message}: Invalid Credentials."
            Logging.logger.error(msg)
        elsif response.kind_of? Net::HTTPServerError

            code = "Code: #{response.code}"
            msg  = "Message: #{response.message}"

            if response.code.eql?('500') # Internal Server Error
                msg += ': Try again later.'
                response.body = {'error_message' => "#{response.message}: Web Server Error - No idea what happened here.",'http_status_code' => response.code.to_s}.to_json
            elsif response.code.eql?('502') # Bad Gateway
                response.body = {'error_message' => "#{response.message}: The server received an invalid response from the upstream server",
                                 'http_status_code' => response.code.to_s}.to_json
            elsif response.code.eql?('503') # Service Unavailable => Web Server overloaded or temporarily down
                response.body = {'error_message' => "#{response.message}: The server is currently unavailable (because it is overloaded or down for maintenance)",
                                 'http_status_code' => response.code.to_s}.to_json
            else
                response.body = {'error_message' => "#{response.message.to_s.gsub(/[<>]+/,'')}",'http_status_code' => response.code.to_s}.to_json
            end
            Logging.logger.error(code)
            Logging.logger.error(msg)
        else
            if response.body.include?('<title>OpenAsset - Something went wrong!</title>') &&
               !http_method.upcase.eql?('GET')
                    response.body = {'error_message' => 'Possibly unsupported file type: NGINX Error - OpenAsset - Something went wrong!','http_status_code' => response.code.to_s}.to_json
            elsif response.code.eql?('403') && http_method.upcase.eql?('GET') &&
               response.body.include?('<title>OpenAsset - Something went wrong!</title>')
                    msg = "Don't let the error fool you. The image size specified is no longer available in S3. Go see the Wizard."
                    Logging.logger.error(msg)
            end
        end
        response
    end

    def self.validate_field_lookup_string_arg(field)
        id = nil
        #check for a field object or an id as a string or integer
        if field.is_a?(Fields)
            id = field.id
        elsif field.is_a?(Integer)
            id = field
        elsif field.is_a?(String) && field.to_i > 0
            id = field.to_i.to_s #In case something like "12abc" is passed it returns "12"
        elsif field.is_a?(Hash) && field.has_key?('id')
            id = field['id']
        else
            msg = "Argument Error in get_field_lookup_strings method:\n\tFirst Parameter Expected " +
                  "one of the following so take your pick.\n\t1. Fields object\n\t2. Field object converted " +
                  "to Hash (e.g) field.json\n\t3. A hash just containing an id (e.g) {'id' => 1}\n\t" +
                  "4. A string or an Integer for the id\n\t5. An array of Integers of Numeric Strings" +
                  "\n\tInstead got => #{field.inspect}"
            Logging.logger.error(msg)
            Thread.exit
            #abort
        end
        id
    end

    def self.validate_and_process_url(uri)
        #Perform all the checks for the url
        unless uri.is_a?(String)
            msg = "Expected a String for first argument => \"uri\": Instead Got #{uri.class}"
            Logging.logger.error(msg)
            Thread.exit
            #abort
        end

        uri_with_protocol = Regexp.new('(^https:\/\/|http:\/\/)[\w-]+\.[\w-]+\.(com)$', true)

        uri_without_protocol = Regexp.new('^[\w-]+\.[\w-]+\.(com)$', true)

        uri_is_ip_address = Regexp.new('(http(s)?:\/\/)?(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',true)

        uri_is_localhost = Regexp.new('^(https?:\/\/)?localhost(:\d{2,4})?$')

        # check for valid url and that protocol is specified
        if uri_with_protocol.match(uri)
            uri
        elsif uri_is_localhost.match(uri)
            protocol = uri_is_localhost.match(uri)[1]
            uri = "http://" + uri unless protocol
        elsif uri_without_protocol.match(uri)
            uri = "https://" + uri
        elsif uri_is_ip_address.match(uri)
            unless uri.to_s.include?('http://') || uri.to_s.include?('https://')
                uri = 'http://' + uri.to_s
            end
            # Only allow private IPs because public ones will fail due to SSL certificate error
            unless /http:\/\/10\.\d{1,3}\.\d{1,3}\.\d{1,3}/ =~ uri ||                # Class A IP range
                   /http:\/\/172\.(1[6-9]|2[0-9]|3[01])\.\d{1,3}\.\d{1,3}/ =~ uri || # Class B IP range
                   /http:\/\/192\.168\.\d{1,3}\.\d{1,3}/ =~ uri                      # Class C IP range

                msg = "Only private IP ranges allowed. Public IPs will trigger an SSL certificate error."
                Logging.logger.error(msg)
                Thread.exit
                #abort
            end
            uri
        else
            msg = "Invalid url! Expected http(s)://<subdomain>.openasset.com" +
                  "\nInstead got => #{uri.inspect}"
            Logging.logger.error(msg)
            Thread.exit
        end

    end

    def self.validate_and_process_request_data(data)
        json_object = nil

        if data.nil?
            msg = "Error: No body provided."
            Logging.logger.error(msg)
            return false
        end

        # Perform all the checks for what will be the body of the HTTP request
        if data.is_a?(Hash)
            json_object = data # Already in json object format
        elsif data.is_a?(Array) && !data.empty?
            if data.first.is_a?(Hash) # Array json objects
                json_object = data
            elsif NOUNS.include?(data.first.class.name) || # Array of NOUN objects
                  NOUNS.include?(data.first.class.superclass.name)
                json_object = data.map(&:json)
            end
        elsif NOUNS.include?(data.class.name) ||
              NOUNS.include?(data.class.superclass.name) # Single object
            json_object = data.json # This means we have a noun object
        elsif data.is_a?(Array) && data.empty?
            msg = 'Oops. Array is empty so there is nothing to send.'
            Logging.logger.error(msg)
            return false
        else
            msg = "Argument Error: Expected either\n1. A NOUN object\n2. An Array of NOUN objects\n3. A Hash\n4. An Array of Hashes\n" +
                  "Instead got a #{data.class}."
            Logging.logger.error(msg)
            return false
        end
        json_object
    end

    def self.validate_and_process_delete_body(data)
        json_object = nil

        # Perform all the checks for what will be the body of the delete request
        if data.is_a?(Hash)
            json_object = data #already a JSON object
        elsif data.is_a?(Integer) || data.is_a?(String)# if just an id is passed, create json object
            #Check if its an acutal number and not just random letters
            if data.to_i != 0
                json_object = {}
                json_object['id'] = data.to_s
            else
                msg = "Expected an Integer or Numberic string for id in delete request body. Instead got #{data.inspect}"
                Logging.logger.error(msg)
                return false
            end
        elsif data.is_a?(Array) && !data.empty?
            if data.first.is_a?(Hash) #Array of JSON objects
                json_object = data
            elsif NOUNS.include?(data.first.class.name) ||
                  NOUNS.include?(data.first.class.superclass.name) # Array of objects
                json_object = data.map(&:json) # Convert all the Noun objects to JSON objects, NOT JSON Strings
            elsif data.first.is_a?(String) || data.first.is_a?(Integer) #Array of id's
                json_object = data.map do |id_value|
                    if id_value.to_i.zero?
                        msg = "Invalid id value of #{id_value.inspect}. Skipping it."
                        Logging.logger.warn(msg.yellow)
                    else
                        {'id' => id_value.to_s} # Convert each id into json object and return array of JSON objects
                    end
                end
            else
                msg = "Expected Array of id Strings or Integers but instead got => #{data.first.class}"
                Logging.logger.error(msg)
                return false
            end
        elsif NOUNS.include?(data.class.name) ||
              NOUNS.include?(data.class.superclass.name) # Single object
            json_object = data.json # Convert Noun to JSON object (NOT JSON string. We do that right befor sending the request)
        elsif data.is_a?(Array) && data.empty?
            msg = 'Oops. Array is empty so there is nothing to send.'
            Logging.logger.error(msg)
            return false
        else
            msg = "Argument Error: Expected either\n\t1. A NOUN object\n\t2. An Array of NOUN objects" +
                                  "\n\t3. A Hash\n\t4. An Array of Hashes\n\t5. An Array of id strings or integers\n\t" +
                                  "Instead got a => #{data.class}."
            Logging.logger.error(msg)
            return false
        end
        json_object
    end

    def self.validate_coordinates(*args)
        coordinate_pair = []

        if args.first.is_a?(Array) # Array
            if args.length == 1
                coordinate_pair = args.first
            elsif args.length > 1
                coordinate_pair[0] = args[0]
                coordinate_pair[1] = args[1]
            end
        elsif args.first.is_a?(Hash) # Hash
            hash = args.first
            hash.keys.each do |key|
                unless ACCEPTED_KEYS.include?(key.to_s)
                    msg = "Invalid key #{key.inspect}. Acceptable hash keys"\
                          " are #{ACCEPTED_KEYS.inpect}."
                    Logging.logger.error(msg)
                    return coordinate_pair
                end
            end
            coordinate_pair = hash.values
        elsif !args[1].nil? # Two separate arguments
            coordinate_pair << args[0] << args[1]
        else # String
            coordinate_pair = args.first.split(',')
        end

        # Sanitize latitude and longitude values (remove any degree symbols, letters, etc)
        coordinate_pair = coordinate_pair.map { |val| val.to_s.gsub(/[^0-9\.]/, '') }.reject(&:empty?)

        # Make sure the coordinates are within valid ranges
        unless coordinates_valid?(coordinate_pair.join(','))
            Logging.logger.warn("Invalid coordinates detected => #{coordinate_pair}")
        end
        coordinate_pair
    end
end