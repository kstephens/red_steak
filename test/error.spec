# -*- ruby -*-
$: << 'lib'

require 'red_steak/error'

require 'pp'

describe 'RedSteak::Error' do

  it 'should handle (:message)' do
    e = RedSteak::Error.new(:message)
    e.message.should == "message"
    e.options.keys.should == [ ]
    e.options[:message].should == nil
    e.message.should == "message"
    e.inspect.should == "#<RedSteak::Error \"message\">" 
  end


  it 'should handle ("message")' do
    e = RedSteak::Error.new("message")
    e.message.should == "message"
    e.options.keys.should == [ ]
    e.options[:message].should == nil
    e.message.should == "message"
    e.inspect.should == "#<RedSteak::Error \"message\">" 
  end


  it 'should handle (:message => "message")' do
    e = RedSteak::Error.new(:message => "message")
    e.message.should == "message"
    e.options.keys.should == [ ]
    e.options[:message].should == nil
    e.message.should == "message"
    e.inspect.should == "#<RedSteak::Error \"message\">" 
  end

  it 'should handle ("message", :foo => :bar)' do
    e = RedSteak::Error.new("message", :foo => :bar)
    e.message.should == "message"
    e.options.keys.should == [ :foo ]
    e.options[:message].should == nil
    e.options[:foo].should == :bar
    e.message.should == "message"
    e.inspect.should == "#<RedSteak::Error \"message\" :foo => :bar>" 
  end


end # describe


