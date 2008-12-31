

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
      return x if ! x

      if xx = @map[x]
        return xx 
      end

      xx = @map[x] = (x.dup rescue x)
      xx.deepen_copy!(self, x) if xx.respond_to?(:deepen_copy!)

      xx
    end

    alias :[] :copy
  end


end # module


###############################################################################
# EOF
