# -*- ruby -*-

$: << 'lib'

require 'red_steak'
require 'ostruct'
require 'pp'

describe 'RedSteak::Machine#event!' do

=begin
  before(:all) do
    RedSteak::Dot.verbose = true
  end
=end

  # A test context for the StateMachine.
  class Telephone
    attr_accessor :name

    attr_reader :number

    attr_accessor :m

    def initialize
      @number = ""
    end

    def prefix number = self.number
      case number
      when /^0/
        [ :operator, 0 ]
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

    def valid *args
      p = prefix number
      p[0] != nil && p[1] == number.size
    end 

    def incomplete *args
      ! valid && ! invalid
    end

    def invalid *args
      ! (number =~ /^\d+$/)
    end

    def dial_digit n
      @number << n
      @m.event! [ :dial_digit, n ]
    end


    def inspect
      "#{self.class} #{name} n=#{number.inspect} t=#{call_type.inspect} state=#{@m.state.to_s}"
    end


    def method_missing sel, *args
      $stderr.puts "#{name} #{sel}(#{args.inspect.gsub(/^\[|\]$/, '')})"
    end


    def sm
      @sm ||=
        RedSteak::Builder.new.build do
        statemachine :telephone do
          initial :idle
          final :final

          state :idle
          transition :active,
            :trigger => :lift_reciever,
            :effect => :get_dial_tone
          transition :final,
            :trigger => :terminate

          state :active do
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
                :guard => :incomplete
              transition :time_out,
                :trigger => :after_timeout
              transition :dialing,
                :trigger => :dial_digit,
                :guard => :incomplete
              transition :connecting,
                :trigger => :dial_digit,
                :guard => :valid,
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

              state :talking
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


  def render_graph sm, opts = { }
    opts[:dir] ||= File.expand_path(File.dirname(__FILE__) + '/../doc/example')
    opts[:name_prefix] = 'red_steak-'
    @graph_id ||= 0
    opts[:name_suffix] = "-%02d" % (@graph_id += 1)

    opts[:show_state_sequence] = true
    opts[:show_transition_sequence] = true
    opts[:highlight_state_history] = true
    opts[:highlight_transition_history] = true
    opts[:show_effect] = true
    opts[:show_guard] = true
    opts[:show_entry] = true
    opts[:show_exit] = true
    opts[:show_do] = true

    RedSteak::Dot.new.render_graph(sm, opts)
    # pp sm.history
  end


  ####################################################################


  attr_accessor :t

  it 'transitions using transition_if_valid!' do
    self.t = Telephone.new
    t.name = "t"
    sm = t.sm
    m = sm.machine
    m.context = t
    t.m = m
    m.logger = lambda { | msg | $stderr.puts "m #{msg}" }
    m.history = [ ]
    render_graph(m)

    m.start!
    render_graph(m)

    events =
      [
       :lift_reciever,
       [ :dial_digit, "5" ],
       [ :dial_digit, "5" ],
       [ :dial_digit, "5" ],
       [ :dial_digit, "1" ],
       [ :dial_digit, "2" ],
       [ :dial_digit, "1" ],
       [ :dial_digit, "2" ],
       :connected,
       :callee_answers,
       :caller_hangs_up,
       :terminate,
      ]
    
    until m.at_end?
      $stderr.puts "t = #{t.inspect}"
      event = events.shift
      raise "out of events" unless events
      case event
      when Array
        t.send(*event)
      else
        m.event! event
      end
      m.run_events!
      render_graph(m)
    end
  end

end # describe


