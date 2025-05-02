module RedSteak
  # Base class for RedSteak objects.
  class Base
    include Logging

    # The name of this object.
    attr_accessor :name

    # Options not captured by setters.
    attr_reader :options

    def initialize opts = EMPTY_HASH
      @name = nil
      @options = nil
      self.options = opts
    end

    def freeze
      return self if frozen?
      @options.freeze
      super
    end

    # Sets all options.
    def options= opts
      # If some options are already set, merge them.
      if @options
        return @options if opts.empty?

        @options.update(_dup_opts(opts))
      else
        @options = _dup_opts opts
      end

      # Scan options for setters,
      # deleting options with setters from Hash.
      @options.each do | k, v |
        s = "#{k}="
        if respond_to? s
          send s, v
          @options.delete k
        end
      end
    end

    # Shorthand for self.options[...].
    def [](*args)
      options[*args]
    end

    # Sets the name as a Symbol.
    def name= x
      @name = x && x.to_sym
    end

    # Returns the name Symbol.
    def to_sym
      @name
    end

    # Dups options Hashes deeply.
    def _dup_opts opts
      h = { }
      opts.each do | k, v |
        k = k.to_sym
        case v
        when String, Array, Hash
          v = v.dup
        end
        h[k] = v
      end
      h
    end

    # Creates a deep copy of this object.
    def copy
      Copier.copy(self)
    end

    # Deepens @options.
    # Subclasses should call super.
    def deepen_copy! _copier, _src
      @options = _dup_opts @options
    end

    # Returns the String representation of this object's namespace path.
    # This is related to its namespace.
    # See SEP.
    def to_s
      to_a * SEP
    end

    # Returns the namespace path of this object.
    def to_a
      [ name ]
    end

    # Returns the class and the name as a String.
    def inspect
      "#<#{self.class} #{to_s}>"
    end

    # Runs _validate method and collects errors into an Array.
    def validate errors = nil
      errors ||= [ ]
      e = [ ]
      _validate e
      e.each do | msg |
        msg = [ msg, self ] unless msg.instance_of?(Array)
        errors << msg
      end
      errors
    end

    def _validate _e
      self
    end

    # Returns true if this object is valid.
    def valid?
      validate.empty?
    end

    # Returns self if this object is valid.
    # Otherwise it raises a Error::ObjectInvalid error.
    def validate!
      if (errors = validate) && ! errors.empty?
        attrs = {:message => :validate!, :object => self, :errors => errors}
        pp attrs
        raise Error::ObjectInvalid, attrs
      end
    end
  end
end

require 'red_steak/copier'
require 'red_steak/named_array'
