module RedSteak
  # Generic event.
  class Event
    attr_accessor :name

    def initialize name, opts = { }
      @name = name.to_sym
      @opts = opts
    end

    def [] key
      @opts[key]
    end

    def freeze
      @opts.freeze
      super
    end
  end # class
end # module
