require 'red_steak'
require 'pp'

describe 'RedSteak::Builder' do

  it 'should handle undefined ambiguous Transition names' do
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

    expect(sm.transition.size).to eq(2)
    expect(sm.state.size).to eq(2)

    expect((t1 = sm.transition[:'initial->final'])).to_not eq(nil)
    expect(sm.transition[0]).to be(t1)
    expect(t1.source.name).to eq(:initial)
    expect(t1.target.name).to eq(:final)
    expect(t1.trigger).to eq([ :trigger1 ])

    expect((t2 = sm.transition[:'initial->final-2'])).to_not eq(nil)
    expect(sm.transition[1]).to be(t2)
    expect(t2.source.name).to eq(:initial)
    expect(t2.target.name).to eq(:final)
    expect(t2.trigger).to eq([ :trigger2 ])
  end


  it 'should raise error overloaded Transition names' do
    expect do
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
    end.to raise_error(RedSteak::Error, /Ambiguous Transition Name/)

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

    expect((t1 = sm.transition[0])).to_not eq(nil)

    a = b = nil
    sm.build do
      a = state(:initial)
      b = state(:final)
    end
    expect(a).to be(s1)
    expect(b).to be(s2)
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

    expect((t1 = sm.transition[0])).to_not eq(nil)
    expect(t1.name).to eq(:'initial->final')
    expect(t1[:foo]).to eq(1)

    sm.build do
      transition :initial, :final, :foo => 2
    end

    expect(t1[:foo]).to eq(2)
    (t2 = expect(sm.transition[1])).to eq(nil)

    sm.build do
      transition :initial, :final
      transition :initial, :final
    end

=begin
    # FIXME!!!
    expect((t2 = sm.transition[1])).to_not eq(nil)
    expect(t2).to_not be(t1)
    expect(t2.name).to eq(:'initial->final-2')
=end

  end # it
end # describe
