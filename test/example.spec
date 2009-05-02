# -*- ruby -*-

require 'red_steak'
require 'ostruct'
require 'pp'

describe 'RedSteak LoanOfficer Example' do

  before(:all) do
    RedSteak::Dot.verbose = true
  end

  # A test context for the StateMachine.
  class LoanOfficer
    attr_accessor :_logger

    attr_reader :data
    attr_reader :customer
    attr_reader :loan
    attr_accessor :controller

    def initialize
      @data = { }
      @customer = nil
      @loan = nil
      @controller = nil
    end

    ######################################3
    # Customer 
    #

    @@required_customer_data = 
      [
       :first_name,
       :last_name,
       :ssn,
       :email,
       :income,
       ]
                       
    def do_merge_customer_data! m, state, *args
      _log
      @data.merge!(controller.params)
    end

    def customer_data_complete? *args
      x = @@required_customer_data.all? { |x| @data[x].to_s != '' }
      _log x
      x
    end

    def customer_data_not_complete? *args
      x = ! customer_data_complete?
      _log x
      x
    end

    def create_customer! m, trans, *args
      _log
      @customer = @data
    end

    def customer_data_still_needed! m, trans, *args
      _log
    end


    ######################################3
    # Loan
    #

    @@required_loan_data = 
      [
       :amount,
       :due_date,
       ]

    def do_merge_loan_data! m, state, *args
      _log
      @data.merge!(controller.params)
    end

    def loan_data_complete? *args
      x = @@required_loan_data.all? { |x| @data[x].to_s != '' }
      _log x
      x
    end

    def loan_data_not_complete? *args
      x = ! loan_data_complete?
      _log x
      x
    end

    def create_loan! m, trans, *args
      _log
      @loan = @data
    end

    def start_risk_assessment! *args
      @loan[:approved?] = 
        @loan[:denied?] = false
    end

    def approve_loan? *args
      @customer[:income] >= @loan[:amount] * 10
    end

    def deny_loan? *args
      ! approve_loan?
    end

    def approve_loan! *args
      @loan[:approved?] = true
    end

    def deny_loan! *args
      @loan[:denied?] = true
    end

    def machine
      @machine ||= 
        begin
          m = sm.machine
          m.context = self
          m
        end
    end


    def _log *args
      case @_logger
      when IO
        line = caller(1).first
        line =~ /`([^']*)'/
        method = $1 || line
        @_logger.puts "  #{self.class}: #{method} #{args * ' '}"
      end
      self
    end


    def sm
      @sm ||=
        # RedSteak::StateMachine.build do
        RedSteak::Builder.new.build do
        statemachine :loan_application do
          initial :start
          final :complete

          state :start
          transition :customer_data

          state :customer_data,
            :do => :do_merge_customer_data!,
            :exit => :create_customer!
          transition :customer_data,
            :guard => :customer_data_not_complete?,
            :effect => :customer_data_still_needed!
          transition :loan_data,
            :guard => :customer_data_complete?

          state :loan_data,
            :do => :do_merge_loan_data!,
            :exit => :create_loan!
          transition :loan_data,
            :guard => :loan_data_not_complete?
          transition :risk_assessment,
            :guard => :loan_data_complete?

          state :risk_assessment,
            :entry => :start_risk_assessment!
          transition :display_contract,
            :guard => :approve_loan?,
            :effect => :approve_loan!
          transition :loan_denied,
            :guard => :deny_loan?,
            :effect => :deny_loan!

          state :display_contract
          transition :loan_approved, 
            :name => :sign_contract!
          transition :loan_unsigned, 
            :name => :loan_signature_timeout!
 
 
          state :loan_approved
          transition :complete

          state :loan_denied
          transition :complete
          transition :customer_data,
            :name => :revise_customer_data!
          transition :loan_data,
            :name => :revise_loan_data!
 
          state :loan_unsigned
          transition :complete

          state :complete
        end
      end
    end
  end


  def render_graph sm, opts = { }
    lo._log lo.data.inspect
    #pp lo.data
    #pp sm.to_hash

    opts[:dir] ||= File.expand_path(File.dirname(__FILE__) + '/../example')
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


  attr_accessor :lo

  it 'transitions using transition_if_valid!' do
    self.lo = LoanOfficer.new
    # lo._logger = $stdout
    controller = OpenStruct.new(:params => { })
    lo.controller = controller

    m = lo.machine
    m.history = [ ]
    m.logger = lo._logger
    m.auto_run = true
    render_graph(m)

    m.start!
    render_graph(m)
    m.state.name.should == :start
    lo._log m.valid_transitions.inspect
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :customer_data
    controller.params[:first_name] = 'Joe'
    lo._log m.valid_transitions.inspect
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :customer_data
    controller.params[:last_name] = 'Borrower'
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :customer_data
    controller.params[:ssn] = '123456789'
    controller.params[:email] = 'joeb@asdf.com'
    controller.params[:income] = 1000
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :loan_data
    lo.customer.should_not == nil
    controller.params[:amount] = 500
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :loan_data
    controller.params[:due_date] = '2009/01/20'
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :risk_assessment
    lo.loan.should_not == nil
    lo.loan[:approved?].should == false
    lo.loan[:denied?].should == false
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :loan_denied
    lo.loan.should_not == nil
    lo.loan[:approved?].should == false
    lo.loan[:denied?].should == true
    m.transition! :revise_loan_data!

    render_graph(m)
    m.state.name.should == :loan_data
    lo.loan[:amount] = 100
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :risk_assessment
    lo.loan[:approved?].should == false
    lo.loan[:denied?].should == false
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :display_contract
    lo.loan[:approved?].should == true
    lo.loan[:denied?].should == false
    m.transition! :sign_contract!

    render_graph(m)
    m.state.name.should == :loan_approved
    m.transition_if_valid!.should_not == nil

    render_graph(m)
    m.state.name.should == :complete
    (lo.loan[:approved?] || lo.loan[:denied?]).should == true
    m.at_end?.should == true
    m.transition_if_valid!.should == nil
  end

end # describe


