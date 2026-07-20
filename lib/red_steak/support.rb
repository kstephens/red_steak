module RedSteak
  module Support
    def bound sel, &blk_1
      lambda { |*args, &blk_2| send(sel, *args, &(blk_2 | blk_1)) }
    end
  end
end
