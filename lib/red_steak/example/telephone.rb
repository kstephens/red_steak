module RedSteak
  module Example
class Telephone
  attr_accessor :name
  attr_reader :number
  attr_accessor :m

  def initialize
    @number = ""
    @counter = 0
  end

  def tick! ; @counter += 1 ; self; end
  def log kind, msg
    $stderr.puts("%3d | %-7s | %s" % [@counter, kind, msg])
    $stderr.puts("%3s   %-7s | %s" % ['', '', inspect])
    $stderr.puts
  end

  ########################################
  # dialed digit management.
  #

  def prefix number = self.number
    case number
    when /^0/
      [ :operator, 1 ]
    when /^[49]11/
      [ :info, 3 ]
    when /^1[2-9]\d{9}/
      [ :long_distance, 10 ]
    when /^[2-9]\d{6}/
      [ :local, 7 ]
    else
      [ nil, nil ]
    end
  end

  def call_type
    prefix.first
  end

  def valid?
    p = prefix number
    p[0] != nil && p[1] == number.size
  end

  def incomplete?
    ! valid? && ! invalid?
  end

  def invalid?
    ! (number =~ /^\d+$/)
  end

  ########################################
  # Methods that generate events.
  #

  def dial_digit n
    @number << n
    event! [ :dial_digit, n ]
  end

  def event! e
    tick!
    log :event, e.join(', ')
    @m.event! e
  end

  [
   :after_timeout,
   :lift_receiver,
   :connected,
   :busy,
   :callee_answers,
   :callee_hangs_up,
   :caller_hangs_up,
   :terminate,
  ].each do | meth |
    class_eval <<"RUBY", __FILE__, __LINE__
def #{meth}
event! [ #{meth.inspect} ]
end
RUBY
  end

  def inspect
    "#{self.class} state=#{@m.state.to_s} n=#{number.inspect} t=#{call_type.inspect}"
  end

  def method_missing sel, *args
    tick!
    log :do, "#{sel}(#{args.inspect.gsub(/^\[|\]$/, '')})"
  end

  def sm
    @sm ||= RedSteak::Builder.new.build do
      statemachine :telephone do
        initial :idle
        final :final

        state :idle
        transition :active,
          :trigger => :lift_receiver,
          :effect => :get_dial_tone,
          :dot_options => { :color => :green }
        transition :final,
          :trigger => :terminate

        state(:active, :dot_options => { :show_decomposition => true }) do
          statemachine do
            initial :dial_tone

            state :dial_tone,
              :do => :play_dial_tone
            transition :time_out,
              :trigger => :after_timeout
            transition :dialing,
              :trigger => :dial_digit

            state :time_out,
              :do => :play_message

            state :dialing
            transition :dialing,
              :trigger => :dial_digit,
              :guard => :incomplete?
            transition :time_out,
              :trigger => :after_timeout
            transition :connecting,
              :trigger => :dial_digit,
              :guard => :valid?,
              :effect => :connect
            transition :invalid,
              :trigger => :invalid

            state :invalid,
              :do => :play_message

            state :connecting
            transition :busy,
              :trigger => :busy
            transition :ringing,
              :trigger => :connected

            state :busy,
              :do => :play_busy_tone

            state :ringing,
              :do => :play_ringing_tone
            transition :talking,
              :trigger => :callee_answers,
              :effect => :enable_speech

            state :talking,
              :dot_options => { color: :blue, fontcolor: :blue }
            transition :pinned,
              :trigger => :callee_hangs_up

            state :pinned
            transition :talking,
              :trigger => :callee_answers
          end
        end
        transition :idle,
          :trigger => :caller_hangs_up,
          :effect => :disconnect
        transition :final,
          :trigger => :terminate
=begin
        transition :aborted,
          :trigger => :abort

        state :aborted
=end
        state :final
      end
    end
  end
end
end
end
