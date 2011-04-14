# -*- ruby -*-

require 'red_steak'
require 'pp'

describe 'RedSteak::Builder' do

  it 'should handle undefined ambiguious Transition names' do
    sm = RedSteak::Builder.new.build do
      statemachine :test1 do
        initial :initial
        final :final
        
        state :initial
        
        transition :final,
        :trigger => :trigger1
        
        transition :final,
        :trigger => :trigger2
        
        state :final
      end
    end
    
    sm.transition.size.should == 2
    sm.state.size.should == 2
    
    (t1 = sm.transition[:'initial->final']).should_not == nil
    sm.transition[0].should == t1
    t1.source.name.should == :initial
    t1.target.name.should == :final
    t1.trigger.should == [ :trigger1 ]
    
    (t2 = sm.transition[:'initial->final-2']).should_not == nil
    sm.transition[1].should == t2
    t2.source.name.should == :initial
    t2.target.name.should == :final
    t2.trigger.should == [ :trigger2 ]
  end
  
  
  it 'should raise error overloaded Transition names' do
    lambda {
      sm = RedSteak::Builder.new.build do
        statemachine :test2 do
          initial :initial
          final :final
                                
          state :initial
                                
          transition :final, :name => :foo
          transition :final, :name => :foo
                                
          state :final
        end
      end
      pp sm
    }.should raise_error(RedSteak::Error)
                          
  end 

  it 'should find original States when augmenting' do
    s1 = s2 = nil
    sm = RedSteak::Builder.new.build do
      statemachine :test3 do
        initial :initial
        final :final

        s1 = state :initial

        transition :final

        s2 = state :final
      end
    end

    (t1 = sm.transition[0]).should_not == nil

    sm.build do 
      state(:initial).should == s1
      state(:final).should == s2
    end
  end # it

  it 'should uniquely name Transtions when augmenting' do
    sm = RedSteak::Builder.new.build do
      statemachine :test4 do
        initial :initial
        final :final
                              
        state :initial
                              
        transition :final, :foo => 1
                              
        state :final
      end
    end

    (t1 = sm.transition[0]).should_not == nil
    t1.name.should == :'initial->final'
    t1[:foo].should == 1

    sm.build do 
      transition :initial, :final, :foo => 2
    end

    t1[:foo].should == 2
    (t2 = sm.transition[1]).should == nil

    sm.build do
      transition :initial, :final
      transition :initial, :final
    end

=begin
    # FIXME!!!
    (t2 = sm.transition[1]).should_not == nil
    t2.should_not == t1
    t2.name.should == :'initial->final-2'
=end

  end # it

end # describe
     

