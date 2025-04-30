require 'red_steak/copier'
require 'pp'

RSpec.describe 'RedSteak::Copier' do

  attr_reader :c
  before(:all) do
    @c = RedSteak::Copier.new
  end

  it 'should handle nil, true, false, Numeric, Symbol without extra memory' do
    expect(c[nil]).to eq(nil)
    expect(c.size).to eq(0)

    expect(c[true]).to eq(true)
    expect(c.size).to eq(0)

    expect(c[false]).to eq(false)
    expect(c.size).to eq(0)

    expect(c[:a]).to eq(:a)
    expect(c[:b]).to eq(:b)
    expect(c.size).to eq(0)

    expect(c[12]).to eq(12)
    expect(c.size).to eq(0)

    x = 12.34
    expect(c[x]).to eq(x)
    expect(c[x].object_id).to eq(x.object_id)
    expect(c.size).to eq(0)

    x = 192384719283741923874
    expect(c[x]).to eq(x)
    expect(c[x].object_id).to eq(x.object_id)
    expect(c.size).to eq(0)
  end

  it 'should copy Strings only once.' do
    x = '1234asdf'
    y = '1234asdf'.freeze

    expect(c[x]).to eq(x)
    expect(c[x].object_id).to_not eq(x.object_id)
    expect(c[x].object_id).to eq(c[x].object_id)
    expect(c[x].frozen?).to eq(false)

    expect(c[y]).to eq(y)
    expect(c[y]).to eq(x)
    expect(c[y].object_id).to_not eq(y.object_id)
    expect(c[y].object_id).to eq(c[y].object_id)
    expect(c[y].object_id).to_not eq(c[x].object_id)
    expect(c[y].frozen?).to eq(true)
  end


  it 'should copy Arrays.' do
    x = '1234asdf'
    y = '1234asdf'.freeze
    a1 = [ x, y, 1 ]
    a2 = [ x, a1, y ]

    expect(c[a1]).to eq(a1)
    expect(c[a1].object_id).to_not eq(a1.object_id)
    expect(c[a1].object_id).to eq(c[a1].object_id)
    expect(c[a1].frozen?).to eq(false)

    expect(c[a2]).to eq(a2)
    expect(c[a2][1]).to eq(c[a1])
    expect(c[a2][1].object_id).to eq(c[a1].object_id)
    expect(c[a2][1].object_id).to_not eq(a1.object_id)

    # pp c.map
    expect(c.size).to eq(6)
  end


  it 'should copy Hashes.' do
    x = '1234asdf'
    y = '1234asdf'.freeze
    a1 = { :a => x, y => y, 1 => 2 }
    a2 = { x => :b, :a1 => a1, y => [1, 2, 3] }

    expect(c[a1]).to eq(a1)
    expect(c[a1].object_id).to_not eq(a1.object_id)
    expect(c[a1].object_id).to eq(c[a1].object_id)
    expect(c[a1].frozen?).to eq(false)

    expect(c[a2]).to eq(a2)
    expect(c[a2][:a1]).to eq(c[a1])
    expect(c[a2][:a1].object_id).to eq(c[a1].object_id)
    expect(c[a2][:a1].object_id).to_not eq(a1.object_id)

    # pp c.map
    expect(c.size).to eq(9)

  end

end # describe
