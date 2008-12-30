

module RedSteak
  class Copier
    def self.copy x
      self.new.copy(x)
    end

    attr_reader :map

    def initialize
      @map = { }
    end

    def copy x
      return x if ! x
      xx = @map[x]
      return xx if xx 
      xx = @map[x] = (x.dup rescue x)
      xx.deepen_copy!(self, x) if xx.respond_to?(:deepen_copy!)
      xx
    end

    alias :[] :copy

  end


  # Base class for RedSteak objects.
  class Base 
    # The name of this object.
    attr_accessor :name
    
    # The original object, if cloned.
    attr_reader :_proto
    
    # Options not captured by setters.
    attr_reader :options

    def initialize opts = EMPTY_HASH
      @name = nil
      @_proto = nil
      @options = nil
      self.options = opts
      @_proto ||= self
    end


    # Sets all options.
    def options= opts
      # If some options are already set, merge them.
      if @options
        return @options if opts.empty?
        @options.merge(_dup_opts opts)
      else
        @options = _dup_opts opts
      end

      # Scan options for setters,
      # deleting options with setters from Hash.
      @options.each do | k, v |
        s = "#{k}="
        if respond_to? s
          # $stderr.puts "#{self.class} #{self.object_id} s = #{s.inspect}, v = #{v.inspect}"
          send s, v
          @options.delete k
        end
      end

      @options
    end


    # Sets the name as a Symbol.
    def name= x
      @name = x && x.to_sym
      x
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
    def deepen_copy! copier, src
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
      "#<#{self.class} #{self.to_s}>"
    end
  end # class


  # Simple Array proxy for looking up States and Transitions by name.
  class NamedArray
    def initialize a = [ ], axis = nil
      @a = a
      @axis = axis
    end


    def [] pattern
      case pattern
      when Integer
        @a[pattern]
      when Array
        case pattern.size
        when 0
          nil
        when 1
          self[pattern.first]
        else
          x = self[pattern.first]
          x = x.send(@axis) if @axis
          x[pattern[1 .. -1]]
        end
      when String
        self[pattern.split(SEP).map{|x| x.to_sym}]
      else
        @a.find { | e | e === pattern }
      end
    end


    def []=(i, v)
      case i
      when Integer
        if v
          @a[i] = v
        else
          @a.delete(i)
        end
      else
        @a.delete_if { | x | x === i }
        @a << v if v
      end
    end


    def method_missing sel, *args, &blk
      @a.send(sel, *args, &blk)
    end


    def deepen_copy! copier, src
      @a = @a.map { | x | copier[x] }
    end


    def to_a
      @a
    end
  end # class

end # module


###############################################################################
# EOF
