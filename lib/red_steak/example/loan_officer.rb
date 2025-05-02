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

  def do_merge_customer_data!
    _log
    @data.merge!(controller.params)
  end

  def customer_data_complete?
    x = @@required_customer_data.all? { |x| @data[x].to_s != '' }
    _log x
    x
  end

  def customer_data_not_complete?
    x = ! customer_data_complete?
    _log x
    x
  end

  def prompt_customer!
    _log "prompt customer"
  end

  def create_customer!
    _log
    @customer = @data
  end

  def customer_data_still_needed!
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

  def do_merge_loan_data!
    _log
    @data.merge!(controller.params)
  end

  def loan_data_complete?
    x = @@required_loan_data.all? { |x| @data[x].to_s != '' }
    _log x
    x
  end

  def loan_data_not_complete?
    x = ! loan_data_complete?
    _log x
    x
  end

  def create_loan!
    _log
    @loan = @data
  end

  def start_risk_assessment!
    @loan[:approved?] = @loan[:denied?] = false
  end

  def approve_loan?
    @customer[:income] >= @loan[:amount] * 10
  end

  def deny_loan?
    ! approve_loan?
  end

  def approve_loan!
    @loan[:approved?] = true
  end

  def loan_denied!
    true
  end

  def deny_loan!
    @loan[:denied?] = true
  end

  def loan_eligible_to_reapply?
    @loan[:loan_eligible_to_reapply?]
  end

  def loan_not_eligible_to_reapply?
    ! @loan[:loan_eligible_to_reapply?]
  end

  def customer_eligible_to_reapply?
    @loan[:customer_eligible_to_reapply?]
  end

  def customer_not_eligible_to_reapply?
    ! @loan[:customer_eligible_to_reapply?]
  end

  def method_missing sel, *args, &blk
    _log sel, *args
    if sel.to_s[-1] == '?'
      @data[sel]
    else
      true
    end
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
          transition :customer_data,
            :trigger => :customer_lead_arrives!

          state :customer_data,
            :do => :do_merge_customer_data!,
            :exit => :create_customer!
          transition :customer_data,
            :trigger => :customer_submits_data!,
            :guard => :customer_data_not_complete?
          transition :loan_data,
            :trigger => :customer_submits_data!,
            :guard => :customer_data_complete?

          state :loan_data,
            :do => :do_merge_loan_data!,
            :exit => :create_loan!
          transition :loan_data,
            :trigger => :loan_data_gathered!,
            :guard => :loan_data_not_complete?
          transition :risk_assessment,
            :trigger => :loan_data_gathered!,
            :guard => :loan_data_complete?

          state :risk_assessment,
            :entry => :start_risk_assessment!
          transition :display_contract,
            :trigger => :risk_assessment_complete!,
            :guard => :approve_loan?,
            :effect => :approve_loan!
          transition :loan_denied,
            :trigger => :loan_denied!,
            :guard => :deny_loan?,
            :effect => :deny_loan!

          state :display_contract
          transition :display_contract, :contract_signed,
            :trigger => :contract_signed!,
            :effect => :save_contract!
          transition :display_contract, :loan_aborted,
            :trigger => :contract_sign_timeout!

          state :contract_signed
          transition :loan_funded,
            :trigger => :loan_funded!,
            :effect => :fund_loan!

          state :loan_denied
          transition :loan_denied, :loan_data,
            :trigger => :loan_reviewed!,
            :guard => :loan_eligible_to_reapply?
          transition :loan_denied, :customer_reapply,
            :trigger => :loan_reviewed!,
            :guard => :loan_not_eligible_to_reapply?

          state :customer_reapply
          transition :customer_reapply, :customer_data,
            :trigger => :loan_reviewed!,
            :guard => :customer_eligible_to_reapply?
          transition :customer_reapply, :complete,
            :trigger => :loan_reviewed!,
            :guard => :customer_not_eligible_to_reapply?

          state :loan_funded
          transition :complete

          state :loan_aborted
          transition :complete

          state :complete
        end
      end
    end
  end
end
end
