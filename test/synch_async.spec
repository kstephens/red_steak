# -*- ruby -*-

require 'red_steak'
require 'ostruct'
require 'pp'


describe "RedSteak Synchronous/Asynchronous Interactions" do
  def sm name = nil
    @sm ||=
      RedSteak::Builder.new.build do
        statemachine (name or raise 'no name') do
          initial :start
          final :final
        
          state :start
          transition :state_a
        
          state :state_a
          transition :state_b
          transition :state_c
        
          state :state_b
          transition :state_a
          transition :state_c
        
          state :state_c
          transition :final
        
          state :final
        end
      end
  end


  class TestContext
    attr_accessor :tracker
    attr_reader :m

    def method_missing sel, *args
      _log!(sel, *args)
    end


    def respond_to? sel
      # _log!(:respond_to?, sel)
      true
    end


    def exit *args
      _log!(:exit, *args)
    end


    def doActivity m, s, *args
      _log!(:doActivity, m, s, *args)
      @m = m
      @next_transition = s.outgoing.to_a
      @next_transition = @next_transition[rand(@next_transition.size)]
      if m.stateMachine.name == :synch
        _exec!('m.transition_to_next_state!') unless m.at_end?
      end
    end


    def guard m, t, *args
      result = t == @next_transition
      _interaction! "c.guard(#{_format_args([m, t] + args)}) => #{result.inspect}"
      result
    end


    def _log! sel, *args
      _interaction! "c.#{sel}(#{_format_args(args)})"
    end


    def _interaction! expr
      @tracker.interaction[:context] << { :exec => expr }
    end
    

    def _exec! expr
      _interaction! expr
      eval(expr)
    end


    def _format_args args
      case args
      when Array
        args.map{ | x | _format_arg x }.join(', ')
      else
        raise ArgumentError
      end
    end


    def _format_arg arg
      case arg
      when RedSteak::Machine
        'm'
      when TestContext
        'c'
      when RedSteak::State
        arg.name.inspect
      when RedSteak::Transition
        arg.name.inspect
      when Array
        '[ ' + _format_args(arg) + ' ]'
      else
        arg.inspect
      end
    end

  end


  class Tracker
    attr_accessor :machine, :context
    alias :m :machine
    alias :c :context

    def initialize
      @machine = nil
      @context = nil
      @interactions = [ ]
    end

    def interaction
      @interactions[-1]
    end


    def exec! *args
      expr = args.pop
      exec = "#{args * ' '}#{expr}"
      @interactions << { :exec => exec, :context => [ ]}
      eval(expr)
    end


    def render_text out
      out.puts "top-level\tcontext"
      out.puts "=========\t======="
      @interactions.each do | i |
        out.puts "#{i[:exec]}"
        i[:context].each do | c |
          out.puts "\t\t#{c[:exec]}"
        end
      end
    end


    def render_html out
      out.puts "<table>"

      out.puts "<thead>"
      out.puts "<tr><th>top-level</th><th>context</th>"
      out.puts "</thead>"

      out.puts "</tbody>"
      @interactions.each do | i |
        out.puts "<tr><td><pre>#{i[:exec]}</pre></td><td></td></tr>"
        i[:context].each do | c |
          out.puts "<tr><td></td><td><pre>#{c[:exec]}</pre></td></tr>"
        end
      end
      out.puts "</tbody>"
      out.puts "</table>"
    end

  end


  ####################################################################


  def context
    @context ||=
      begin
        c = TestContext.new
        c
      end
  end


  def tracker
    @tracker ||=
      begin
        t = Tracker.new
        t.context = context
        context.tracker = t
        t.machine = machine
        t
      end
  end


  def machine
    @machine ||=
      begin
        m = sm.machine
        m.context = context
        m
      end
  end


  ####################################################################


  it 'handles synchronous run! events' do
    sm :synch

    tracker.exec!('m.start!')
    tracker.exec!('m.run!')

    tracker.render_text $stdout
  end


  it 'handles asynchronous run! events' do
    sm :async

    tracker.exec!('m.start!')    
    until tracker.exec!('until ', 'm.at_end?')
      tracker.exec!('  ', 'm.transition_to_next_state!')
      tracker.exec!('  ', 'm.run!(true)')
    end

    tracker.render_text $stdout
  end


end

