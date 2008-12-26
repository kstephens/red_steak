

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


    # Returns the name as a String.
    def to_s
      name.to_s
    end


    def to_a
      [ name ]
    end


    # Returns the class and the name as a String.
    def inspect
      "#<#{self.class} #{self.name.inspect}>"
    end
  end # class


  # Simple Array proxy for looking up States and Transitions by name.
  class NamedArray
    def initialize a = [ ]
      @a = a
    end

    def [] pattern
      case pattern
      when Integer
        @a[pattern]
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

  end # class

end # module


###############################################################################
# EOF
