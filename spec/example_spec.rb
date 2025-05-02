require 'red_steak'
require 'red_steak/example/loan_officer'
require 'red_steak/example/render'
require 'ostruct'
require 'fileutils' # FileUtil.mkdir_p
require 'pp'

RSpec.describe 'RedSteak LoanOfficer Example' do
  attr_accessor :lo

  it 'transitions using transition_if_valid!' do
    self.lo = RedSteak::Example::LoanOfficer.new
    # lo._logger = $stdout if ENV['TEST_VERBOSE']
    controller = OpenStruct.new(:params => { })
    lo.controller = controller
    m = lo.machine
    m.history = [ ]
    m.logger = lo._logger if ENV['TEST_VERBOSE']
    m.auto_run = true

    @render = RedSteak::Example::Render.new(context: lo, machine: lo.machine)

    m.start!
    render!
    expect(m.state.name).to eq(:start)
    lo._log m.valid_transitions.inspect
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:customer_data)
    controller.params[:first_name] = 'Joe'
    lo._log m.valid_transitions.inspect
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:customer_data)
    controller.params[:last_name] = 'Borrower'
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:customer_data)
    controller.params[:ssn] = '123456789'
    controller.params[:email] = 'joeb@asdf.com'
    controller.params[:income] = 1000
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:loan_data)
    expect(lo.customer).to_not eq(nil)
    controller.params[:amount] = 500
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:loan_data)
    controller.params[:due_date] = '2009/01/20'
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:risk_assessment)
    expect(lo.loan).to_not eq(nil)
    expect(lo.loan[:approved?]).to eq(false)
    expect(lo.loan[:denied?]).to eq(false)
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:loan_denied)
    expect(lo.loan).to_not eq(nil)
    expect(lo.loan[:approved?]).to eq(false)
    expect(lo.loan[:denied?]).to eq(true)
    lo.loan[:loan_eligible_to_reapply?] = true
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:loan_data)
    lo.loan[:amount] = 100
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:risk_assessment)
    expect(lo.loan[:approved?]).to eq(false)
    expect(lo.loan[:denied?]).to eq(false)
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:display_contract)
    expect(lo.loan[:approved?]).to eq(true)
    expect(lo.loan[:denied?]).to eq(false)
    m.event! :contract_signed!, :run!

    render!
    expect(m.state.name).to eq(:contract_signed)
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:loan_funded)
    expect(m.transition_if_valid!).to_not eq(nil)

    render!
    expect(m.state.name).to eq(:complete)
    expect(lo.loan[:approved?] || lo.loan[:denied?]).to eq(true)
    expect(m.at_end?).to eq(true)
    expect(m.transition_if_valid!).to eq(nil)
  end

  def render!
    $stderr.puts lo.machine.state.inspect
    @render.render_graph!
  end

end
