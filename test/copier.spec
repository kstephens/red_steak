# -*- ruby -*-

require 'red_steak/copier'

require 'pp'

describe 'RedSteak::Copier' do

  attr_reader :c
  before(:all) do
    @c = RedSteak::Copier.new
  end

  it 'should handle nil, true, false, Numeric, Symbol without extra memory' do
    c[nil].should == nil
    c.size.should == 0

    c[true].should == true
    c.size.should == 0

    c[false].should == false
    c.size.should == 0

    c[:a].should == :a
    c[:b].should == :b
    c.size.should == 0

    c[12].should == 12
    c.size.should == 0

    x = 12.34
    c[x].should == x
    c[x].object_id.should == x.object_id
    c.size.should == 0

    x = 192384719283741923874
    c[x].should == x
    c[x].object_id.should == x.object_id
    c.size.should == 0
  end

  it 'should copy Strings only once.' do
    x = '1234asdf'
    y = '1234asdf'.freeze

    c[x].should == x
    c[x].object_id.should_not == x.object_id
    c[x].object_id.should == c[x].object_id
    c[x].frozen?.should == false

    c[y].should == y
    c[y].should == x
    c[y].object_id.should_not == y.object_id
    c[y].object_id.should == c[y].object_id
    c[y].object_id.should_not == c[x].object_id
    c[y].frozen?.should == true
  end


  it 'should copy Arrays.' do
    x = '1234asdf'
    y = '1234asdf'.freeze
    a1 = [ x, y, 1 ]
    a2 = [ x, a1, y ]
    
    c[a1].should == a1
    c[a1].object_id.should_not == a1.object_id
    c[a1].object_id.should == c[a1].object_id
    c[a1].frozen?.should == false

    c[a2].should == a2
    c[a2][1].should == c[a1]
    c[a2][1].object_id.should == c[a1].object_id
    c[a2][1].object_id.should_not == a1.object_id

    # pp c.map
    c.size.should == 6
  end


  it 'should copy Hashes.' do
    x = '1234asdf'
    y = '1234asdf'.freeze
    a1 = { :a => x, y => y, 1 => 2 }
    a2 = { x => :b, :a1 => a1, y => [1, 2, 3] }
    
    c[a1].should == a1
    c[a1].object_id.should_not == a1.object_id
    c[a1].object_id.should == c[a1].object_id
    c[a1].frozen?.should == false

    c[a2].should == a2
    c[a2][:a1].should == c[a1]
    c[a2][:a1].object_id.should == c[a1].object_id
    c[a2][:a1].object_id.should_not == a1.object_id

    # pp c.map
    c.size.should == 9

  end

end # describe


