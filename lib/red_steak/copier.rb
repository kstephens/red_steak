

module RedSteak

  # Copies object graphs with referential integrity.
  class Copier
    def self.copy x
      self.new.copy(x)
    end

    attr_reader :map

    def initialize
      @map = { }
    end


    # Copies x deeply.
    #
    # 1) Dups x as xx
    # 2) calls xx.deepen_copy! copier, x
    #
    def copy x
      # Return immutables immediately.
      case x
      when nil, true, false, Numeric, Symbol
        return x
      end

      # Is the object already copied?
      im = (@map[x.class] ||= { })
      if xx = im[x.object_id]
        return xx.first
      end

      # Keep a reference to x to prevent the GC from potentially 
      # reusing its object_id.
      #
      # Give the new object a chance to deepen its copy.
      case x
      when Array
        xx = x.dup
        im[x.object_id] = [ xx, x ]
        xx.map! { | v | self[v] }
      when Hash
        xx = { }
        im[x.object_id] = [ xx, x ]
        x.each { | k, v | xx[self[k]] = self[v] }
      else
        im[x.object_id] = [ xx = (x.dup rescue x), x ]
      end
      xx.deepen_copy!(self, x) if xx.respond_to?(:deepen_copy!)

      # Freeze it if the original object was frozen.
      xx.freeze if xx.respond_to?(:freeze) and x.frozen? 

      xx
    end

    alias :[] :copy


    def size
      @map.inject(@map.size) { | c, v | c += v.size }
    end
  end


end # module


###############################################################################
# EOF
