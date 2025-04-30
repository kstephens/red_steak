require 'red_steak/error'
require 'pp'

describe 'RedSteak::Error' do

  it 'should handle (:message)' do
    e = RedSteak::Error.new(:message)
    expect(e.message).to eq("message")
    expect(e.options.keys).to eq([ ])
    expect(e.options[:message]).to eq(nil)
    expect(e.message).to eq("message")
    expect(e.inspect).to eq("#<RedSteak::Error \"message\">")
  end


  it 'should handle ("message")' do
    e = RedSteak::Error.new("message")
    expect(e.message).to eq("message")
    expect(e.options.keys).to eq([ ])
    expect(e.options[:message]).to eq(nil)
    expect(e.message).to eq("message")
    expect(e.inspect).to eq("#<RedSteak::Error \"message\">")
  end


  it 'should handle (:message => "message")' do
    e = RedSteak::Error.new(:message => "message")
    expect(e.message).to eq("message")
    expect(e.options.keys).to eq([ ])
    expect(e.options[:message]).to eq(nil)
    expect(e.message).to eq("message")
    expect(e.inspect).to eq("#<RedSteak::Error \"message\">")
  end

  it 'should handle ("message", :foo => :bar)' do
    e = RedSteak::Error.new("message", :foo => :bar)
    expect(e.message).to eq("message")
    expect(e.options.keys).to eq([ :foo ])
    expect(e.options[:message]).to eq(nil)
    expect(e.options[:foo]).to eq(:bar)
    expect(e.message).to eq("message")
    expect(e.inspect).to eq("#<RedSteak::Error \"message\"\n  :foo => :bar>")
  end


end # describe
