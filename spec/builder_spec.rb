require 'red_steak'
require 'pp'

RSpec.describe 'RedSteak::Builder' do
  it 'should raise error if start and stop states are not specified' do
    expect do
      sm = RedSteak::Builder.new.build do
        statemachine __LINE__.to_s do
          state :a
          state :b
          transition :a, :b
        end
      end
    end.to raise_error(RedSteak::Error::ObjectInvalid)
  end

  it 'should handle undefined ambiguous Transition names' do
    sm = RedSteak::Builder.new.build do
      statemachine __LINE__.to_s do
        initial :initial
        final :final
        state :initial
        transition :final, trigger: :trigger1
        transition :final, trigger: :trigger2
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

  it 'should raise error if State is not reachable' do
    expect do
      sm = RedSteak::Builder.new.build do
        statemachine __LINE__.to_s do
          initial :a
          final :b

          state :a
          state :b
          state :c
        end
      end
    end.to raise_error(RedSteak::Error::ObjectInvalid)
  end

  xit 'should raise error overloaded State names' do
    expect do
      sm = RedSteak::Builder.new.build do
        statemachine __LINE__.to_s do
          initial :a
          final :b

          state :a
          state :a
          state :b
          transition :a, :b
        end
      end
    end.to raise_error(RedSteak::Error::NameConflict, /state/)
  end

  it 'should raise error overloaded Transition names' do
    expect do
      sm = RedSteak::Builder.new.build do
        statemachine __LINE__.to_s do
          initial :initial
          final :final

          state :initial
          transition :final, name: :foo
          transition :initial, :final, name: :foo
          state :final
        end
      end
    end.to raise_error(RedSteak::Error::NameConflict, /transition/)
  end

  it 'should find original States when augmenting' do
    s1 = s2 = nil
    sm = RedSteak::Builder.new.build do
      statemachine __LINE__.to_s do
        initial :initial
        final :final

        s1 = state :initial
        transition :final
        s2 = state :final
      end
    end

    t1 = sm.transition[0]
    expect(sm.transition.size).to eq(1)
    expect(t1).to_not eq(nil)
    expect(t1.source).to be(s1)
    expect(t1.target).to be(s2)

    a = b = nil
    sm.build do
      a = state :initial
      b = state :final
    end
    expect(a).to be(s1)
    expect(b).to be(s2)
  end

  it 'should uniquely name Transitions when augmenting' do
    sm = RedSteak::Builder.new.build do
      statemachine __LINE__.to_s do
        initial :initial
        final :final

        state :initial
        transition :final, foo: 1
        state :final
      end
    end

    expect((t1 = sm.transition[0])).to_not eq(nil)
    expect(t1.name).to eq(:'initial->final')
    expect(t1[:foo]).to eq(1)

    sm.build do
      transition :initial, :final, foo: 2
    end

    expect(t1[:foo]).to eq(2)
    (t2 = expect(sm.transition[1])).to eq(nil)

    sm.build do
      transition :initial, :final
      transition :initial, :final, name: :other
    end

    expect(sm.transition.size).to eq(2)
    t2 = sm.transition[1]
    expect(t2.name).to eq(:other)
  end
end
