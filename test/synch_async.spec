# -*- ruby -*-

$: << 'lib'

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
      if m.stateMachine.name == :synchronous
        at_end = _exec!('  ', 'm.at_end?')
        _exec!('  ', 'm.transition_to_next_state!') unless at_end
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
      @tracker.context! expr
    end
    

    def _exec! *args
      exec = args.pop
      expr = "#{args * ' '}#{expr}"
       _interaction! expr
      eval(exec)
    end


    def _format_args args
      case args
      when Array
        args.map{ | x | _format_arg x }.join(', ')
      else
        raise ArgumentError, args.inspect
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
      @top_level = [ ]
    end

    def exec! *args
      expr = args.pop
      exec = "#{args * ' '}#{expr}"
      top_level!(exec)
      eval(expr)
    end


    def top_level! expr
      #$stderr.puts "top_level! #{expr}"
      @top_level << { :expr => expr, :machine => [ ]}
    end

    def machine! expr
      #$stderr.puts "\t\tmachine! #{expr}"
      @top_level[-1][:machine] << { :expr => expr, :context => [ ]}
    end
    
    def context! expr
      #$stderr.puts "\t\t\t\tcontext! #{expr}"
      x = @top_level[-1][:machine]
      #$stderr.puts __LINE__, x.inspect
      x << { :expr => "", :context => [ ] } if x.empty?
      x = x[-1][:context]
      #$stderr.puts __LINE__, x.inspect
      x << { :expr => expr }
      #$stderr.puts __LINE__, x.inspect
    end


    def render_text out
      out.puts "\n\n#{machine.stateMachine.name} interactions:"
      out.write "\n"
      out.puts "top-level\tmachine\t\tcontext"
      out.puts "=========\t=======\t\t======="
      @top_level.each do | i |
        out.puts "#{i[:expr]}"
        i[:machine].each do | m |
          out.puts "\t\t#{m[:expr]}"
          m[:context].each do | c |
            out.puts "\t\t\t\t#{c[:expr]}"
          end
        end
      end
      out.write "\n\n"
    end


    def render_html out
      out.puts "<h2>#{machine.stateMachine.name} interactions:</h2>"
      out.puts "<table>"

      out.puts "<thead>"
      out.puts "<tr><th>top-level</th><th>machine</th><th>context</th>"
      out.puts "</thead>"

      out.puts "</tbody>"
      @top_level.each do | i |
        out.puts "<tr><td><pre>#{i[:expr]}</pre></td><td></td></tr>"
        i[:machine].each do | m |
          out.puts "<tr><td></td><td><pre>#{m[:expr]}</pre></td><td></td></tr>"
          i[:context].each do | c |
            out.puts "<tr><td></td><td></td><td><pre>#{c[:expr]}</pre></td></tr>"
          end
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
        machine.logger = lambda do | msg |
          t.machine! "m.#{msg}"
        end
        t
      end
  end


  def machine
    @machine ||=
      begin
        m = sm.machine
        m.context = context
        m.history = [ ]
        m
      end
  end


  ####################################################################


  it 'handles synchronous run! events' do
    sm :synchronous

    tracker.exec!('m.start!')
    tracker.exec!('m.run!')

    tracker.render_text $stdout
  end


  it 'handles asynchronous run! events' do
    sm :asynchronous

    tracker.exec!('m.start!')
    # pp machine.to_hash
    until tracker.exec!('until ', 'm.at_end?')
      tracker.exec!('  ', 'm.transition_to_next_state!')
      # pp machine.to_hash
      tracker.exec!('  ', 'm.run!(:single)')
      # pp machine.to_hash
    end

    tracker.render_text $stdout
  end


end

