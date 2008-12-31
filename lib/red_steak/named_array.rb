

module RedSteak

  # Simple Array proxy for looking up States and Transitions by name.
  class NamedArray
    def initialize a = [ ], axis = nil, subset = nil
      @a = a
      @axis = axis
      @subset = nil
    end


    def [] pattern
      case pattern
      when Integer
        to_a[pattern]
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
        to_a.find { | e | e === pattern }
      end
    end


    def select &blk
      self.class.new(@a.select(&blk), @axis)
    end


    def + x
      to_a + x.to_a
    end


    def - x
      to_a - x.to_a
    end


    def method_missing sel, *args, &blk
      to_a.send(sel, *args, &blk)
    end


    # Deepens elements through a Copier.
    def deepen_copy! copier, src
      @a = @a.map { | x | copier[x] }
    end


    def to_a
      @subset ? @a.select{|e| @subset === e} : @a
    end


    EMPTY = self.new([ ].freeze) unless defined? EMPTY
  end # class

end # module


###############################################################################
# EOF
