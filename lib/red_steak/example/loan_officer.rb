module RedSteak
  module Example
  class LoanOfficer
  include RedSteak::Logging

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

  def prompt_customer! *args
    _log "prompt customer"
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

  def loan_denied! *args
    true
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
    line = caller(1).first
    line =~ /`([^']*)'/
    method = $1 || line
    super("#{method} #{args * ' '}")
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
end
end
