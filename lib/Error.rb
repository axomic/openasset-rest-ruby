class Error
    attr_accessor :id, :resource_name, :resource_type, :status_code, :message
    def initialize(id=nil, name=nil, type=nil, code=nil, msg=nil)
        @id            = id || 'Not set'
        @resource_name = name || 'Not set'
        @resource_type = type || 'Not set'
        @status_code   = code || 'Not set'
        @message       = msg || 'Not set'     
    end
end