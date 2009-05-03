require 'red_steak'

module RedSteak

  # Base class for all RedSteak errors.
  class Error < Exception

    attr_reader :options
    def [](*args)
      @options[*args]
    end


    attr_reader :message

    def initialize *opts
      # $stderr.puts "  opts = #{opts.inspect}"
      @options = Hash === opts[-1] ? opts.pop.dup : { }
      @message = nil

      args = nil
      opts.each_with_index do | opt, i | 
        # $stderr.puts "  opts[#{i}] = #{opt.inspect}"
        case opt
        when String, Symbol
          if @message
            (args ||= [ ]) << opt
          else
            @message = opts.shift.to_s
          end
        when Hash
          @options.update(opt)
        else
          (args ||= [ ]) << opt
        end
      end
      
      @message = @options.delete(:message) if @options[:message]
      @options[:args] = args if args
      @message ||= '<<UNKNOWN>>'

      if false
        $stderr.puts "\n\n"
        $stderr.puts "  @message = #{@message.inspect}"
        $stderr.puts "  @options = #{@options.inspect}"
      end

      super(@message)
    end


    def inspect
      @inspect ||=
        "#<#{self.class} #{@message.inspect}#{@options.keys.sort { |a, b| a.to_s <=> b.to_s }.map { | k | " #{k.inspect} => #{@options[k].inspect}" }.join('')}>".freeze
    end


    def to_s
      @to_s ||=
        "#<#{self.class} #{@message.inspect}#{@options.empty? ? '' : ' ...'}>".freeze
    end


    def method_missing sel, *args
      if args.size == 0 && @options.key?(sel = sel.to_sym)
        @options[sel]
      else
        super
      end
    end

    
    ##################################################################


    # Transition is unknown by name.
    class UnknownTransition < self; end

    # Transition between states is impossible.
    class InvalidTransition < self; end
    
    # Transition between two states is not possible due
    # to a guard.
    class CannotTransition < self; end
    
    # More than one transitions between two states is possible.
    class AmbiguousTransition < self; end

    # Unexpected recursion detected.
    class UnexpectedRecursion < self; end

    # Feature is not implemented, yet.
    class NotImplemented < self; end

    # Transition is already pending.
    class TransitionPending < self; end

    # Object failed #valid?
    class ObjectInvalid < self; end
  end

end

