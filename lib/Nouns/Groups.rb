# Groups class
#
# @author Juan Estrella
require_relative '../JsonBuilder'
class Groups

    include JsonBuilder

    # @!parse attr_accessor :alive, :id, :name
    attr_accessor :alive, :id, :name

    # Creates a Groups object
    #
    # @param args [ Hash, 2 Strings, or nil ] Default => nil
    # @return [ Groups object]
    #
    # @example
    #         user = Groups.new
    #         user = Groups.new("Marketing")
    #         user = Groups.new({:name=> "Marketing"})
    def initialize(*args)
        json_obj = {}

        if args.first.is_a?(String) # Assume two string args were passed
            json_obj['name'] = args.first
        else                        # Assume a Hash or nil was passed
            json_obj = Validator::validate_argument(args.first,'Groups')
        end

        @alive = json_obj['alive']
        @id = json_obj['id']
        @name = json_obj['name']
        @users = []

        if json_obj['users'].is_a?(Array) && !json_obj['users'].empty?
            @users = json_obj['users'].map do |item|
                NestedUserItems.new(item['id'])
            end
        end
    end

end