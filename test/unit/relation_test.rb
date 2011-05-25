require "#{File.dirname(__FILE__)}/../test_helper"

class Perry::RelationTest < Test::Unit::TestCase
  SINGLE_VALUE_METHODS = Perry::Relation::SINGLE_VALUE_METHODS
  MULTI_VALUE_METHODS = Perry::Relation::MULTI_VALUE_METHODS

  def assert_relation_has_value(relation, method, expected_value)
    value = if MULTI_VALUE_METHODS.include?(method)
      relation.send("#{method}_values").first
    else
      relation.send("#{method}_value")
    end
    assert_equal expected_value, value
  end

  context "Perry::Relation class" do
    setup do
      @model = Class.new(Perry::Test::Base)
      @relation = @model.send(:relation)
      @model.class_eval do
        scope :foo, where('foo')
        scope :bar, where('bar')
      end
      @adapter = @model.send(:read_adapter)
    end

    teardown do
      @adapter.reset
    end

    context "merge method" do
      should "push multi-fields onto that value's array" do
        relation = @relation.dup
        MULTI_VALUE_METHODS.each { |method| relation = relation.merge(@relation.send(method, 'foo')) }
        hash = relation.to_hash
        MULTI_VALUE_METHODS.each do |method|
          assert_equal ['foo'], hash[method]
        end
      end

      should "replace single-field values with merge relation's value" do
        relation = @relation.dup
        SINGLE_VALUE_METHODS.each { |method| relation = relation.merge(@relation.send(method, 'foo')) }
        hash = relation.to_hash
        (SINGLE_VALUE_METHODS - [:includes]).each do |method|
          assert_equal 'foo', hash[method]
        end
        assert_equal({:foo => {}}, hash[:includes])
      end

      should "merge modifiers into new relation" do
        relation = @relation.dup
        value = { :foo => 'bar' }
        relation = relation.merge(@relation.send(:modifiers, value))
        assert_equal value, relation.send(:modifiers_value)
      end
    end

    context "records accessor" do
      setup do
        @records = [@model.new, @model.new]
        @relation.records = @records
      end

      should "allow records to be assigned" do
        assert @relation.respond_to?(:records=)
        assert_equal @records, @relation.to_a
      end

      should "use empty array if result is nil" do
        @relation.records = nil
        assert_equal [], @relation.to_a
      end

      should "return the value of records through the reader" do
        assert_equal @records, @relation.records
      end

      should "not run a query when records is set" do
        assert_equal @records, @relation.to_a
        assert !@adapter.last_call
      end

      should_eventually "force a query to run with fresh scope even when records is set explicitly" do
        assert_not_equal @records, @relation.fresh.all
        assert @adapter.last_call
      end

    end

    context "to_hash method" do
      setup do
        @all_methods = SINGLE_VALUE_METHODS + MULTI_VALUE_METHODS - [:includes]
        @loaded_relation = @relation.clone
        @all_methods.each { |method| @loaded_relation = @loaded_relation.send(method, 'foo') }
        @loaded_relation = @loaded_relation.includes(:foo)
      end

      should "return only :sql key if :sql option is set" do
        hash = @loaded_relation.sql('bar').to_hash
        @all_methods.each { |method| assert_nil hash[method] }
        assert_equal 'bar', hash[:sql]
      end

      should "use all values if :sql option is not set" do
        hash = @loaded_relation.to_hash
        @all_methods.each { |method| assert_equal 'foo', (v = hash[method]).is_a?(Array) ? v.first : v }
        assert_nil hash[:sql]
        assert_equal({:foo => {}}, hash[:includes])
      end

      should "not include blank values" do
        hash = @relation.where('foo').to_hash
        assert_equal ['foo'], hash[:where]
        assert_equal [:where], hash.keys
      end

      should "not include :modifiers" do
        hash = @loaded_relation.modifiers( :foo => 'bar').to_hash
        assert !hash.keys.include?(:modifiers)
      end

      should "call any procs set on value methods to allow delayed execution" do
        @all_methods.each do |method|
          @relation = @relation.send(method, proc { "#{method}_val" })
        end

        hash = @relation.to_hash

        hash.each do |key, value|
          if value.is_a?(Array)
            assert value.inject(true) { |sum, v| sum && !v.is_a?(Proc) }
          else
            assert !value.is_a?(Proc)
          end
        end
      end

      should "remove all select values if one ends in '*'" do
        assert_equal %w(foo), @relation.select('foo').to_hash[:select]
        assert_equal %w(foo *bar), @relation.select('foo').select('*bar').to_hash[:select]
        assert_nil @relation.select('foo').select('*bar').select('baz*').to_hash[:select]
      end
    end

    context "scoping method" do
      setup do
        @relation = @model.foo.bar
      end

      should "impose its scopes on all references to the base model within the block" do
        @relation.scoping do
          assert_equal "foobar", @model.scoped.to_hash[:where].join
        end
      end

      should "remove all scopes when exiting the block successfully" do
        @relation.scoping {}
        assert_nil @model.scoped.to_hash[:where]
      end

      should "remove all scopes when exiting the block with exception raised" do
        assert_raises(RuntimeError) { raise "Exception" }
        assert_nil @model.scoped.to_hash[:where]
      end

      should "function correctly when unscoped block used within the scoping block" do
        @relation.scoping do
          @model.unscoped do
            assert_nil @model.scoped.to_hash[:where]
          end
          assert_equal "foobar", @model.scoped.to_hash[:where].join
        end
        assert_nil @model.scoped.to_hash[:where]
      end
    end

    #-----------------------------------------
    # TRP: Method Delegation
    #-----------------------------------------
    context "dynamic finder methods (find_by_*, etc.)" do
      setup do
        @model.class_eval do
          attributes :name, :age, :weight
        end
      end

      should "fail when attribute does not exist" do
        assert_raise(NoMethodError) { @relation.find_by_height(10) }
      end

      should "not fail when attribute does exist" do
        assert_nothing_raised { @relation.find_by_name('poop') }
      end

      should "be recognized by respond_to?" do
        assert @relation.respond_to?(:find_by_name)
        assert !@relation.respond_to?(:find_by_height)
      end
    end

    should "delegate scope calls to Base" do
      @model.scope :foo, :where => 'foo'
      assert @relation.respond_to?(:foo)
      assert_nothing_raised { @relation.foo }
    end


    #-----------------------------------------
    # TRP: Finder Methods
    #-----------------------------------------
    context "all method" do
      should "accept optional finder options and apply them to the relation" do
        @relation.all(:conditions => 'test')
        assert_equal ['test'], @adapter.last_call.last[:where]
      end

      should "return an array" do
        assert_kind_of Array, @relation.all
      end
    end

    context "first method" do
      should "accept optional finder options and apply them to the relation" do
        @relation.first(:conditions => 'test')
        assert_equal ['test'], @adapter.last_call.last[:where]
      end

      should "return an object or nil if nothing matched" do
        @adapter.data = { :id => 1 }
        assert_kind_of Perry::Base, @relation.first
      end
    end

    context "find method" do
      should "accept string or number as query for the primary_key with finder options" do
        @adapter.data = { :id => 1 }
        @relation.find(1)
        assert_equal [{:id => 1}], @adapter.last_call.last[:where]
        @relation.find("1")
        assert_equal [{:id => "1"}], @adapter.last_call.last[:where]
      end

      should "accept array of primary keys with finder options" do
        @adapter.data = { :id => 1 }
        @adapter.count = 4
        @relation.find([1,2,3,4])
        assert_equal [{:id => [1,2,3,4]}], @adapter.last_call.last[:where]
      end

      should "accept :all with finder options" do
        assert_kind_of Array, @relation.find(:all, :conditions => 'test')
        assert_equal ['test'], @adapter.last_call.last[:where]
      end

      should "accept :first with finder options" do
        @adapter.data = { :id => 1 }
        assert_kind_of Perry::Base, @relation.find(:first, :conditions => 'test')
        assert_equal ['test'], @adapter.last_call.last[:where]
      end

      should "raise ArgumentError for wrong usage" do
        assert_raises(ArgumentError) { @relation.find(1.5) }
        assert_raises(ArgumentError) { @relation.find({}) }
      end

      should "raise Perry::RecordNotFound when id passed and record could not be found" do
        assert_raises(Perry::RecordNotFound) { @relation.find(1) }
      end

      should "raise Perry::RecordNotFound when a set of ids is passed and any record could not be found" do
        assert_raises(Perry::RecordNotFound) { @relation.find([1,2,3]) }
      end
    end

    context "clone functionality" do
      should "reset query" do
        @adapter.data = { :id => 1 }
        @relation.to_a
        new_rel = @relation.clone
        assert_nil new_rel.records
      end
    end

    context "search method" do
      # TODO: Pull this code out of this gem and
    end

    context "apply_finder_options method" do
      setup do
        @model.send :attributes, :id
        @all_methods = SINGLE_VALUE_METHODS + MULTI_VALUE_METHODS + [:modifiers] - [:includes]
      end

      should "allow any of the regular query methods as keys" do
        test_value = { :foo => 'bar' } # modifiers value requires a hash or a proc
        finder_hash = @all_methods.inject({}) { |hash, method| hash.merge({ method => test_value }) }
        relation = @relation.apply_finder_options(finder_hash)
        @all_methods.each do |method|
          assert_relation_has_value(relation, method, test_value)
        end
      end

      should "allow :conditions as alias for :where" do
        assert_equal ['foo'], @relation.apply_finder_options(:conditions => 'foo').to_hash[:where]
      end

      should "allow :sql key and pass through" do
        assert_equal 'foo', @relation.apply_finder_options(:sql => 'foo').to_hash[:sql]
      end

      should "allow :include key as alias for :includes" do
        assert_equal({ :foo => {} }, @relation.apply_finder_options(:include => 'foo').to_hash[:includes])
      end

      should "allow :search key and pass through to search method" do
        assert_equal [{"id_equals" => 1}], @relation.apply_finder_options(:search => { :id_is => 1}).to_hash[:where]
      end
    end


    #-----------------------------------------
    # TRP: Query Methods
    #-----------------------------------------
    context "select query method" do
      should "delegate to array if block is passed" do
        assert_kind_of(Perry::Relation, @relation.select('foo'))
        assert_kind_of(Array, @relation.select {})
      end
    end

    # Multi query methods
    MULTI_VALUE_METHODS.each do |method|
      context "#{method} query method" do
        should "clone new relation and append value to #{method}_values" do
          new_relation = @relation.send(method, 'foo')
          assert_equal [], @relation.send("#{method}_values")
          assert_equal ['foo'], new_relation.send("#{method}_values")
        end
      end
    end

    # Single query methods
    (SINGLE_VALUE_METHODS - [:includes]).each do |method|
      context "#{method} query method" do
        should "clone new relation and replace value in #{method}_value" do
          new_relation = @relation.send(method, 'foo')
          assert_nil @relation.send("#{method}_value")
          assert_equal 'foo', new_relation.send("#{method}_value")
        end
      end
    end

    # SQL query method
    context "sql query method" do
      should "clone new relation and replace the raw_sql_value" do
        new_relation = @relation.sql('select * from foo')
        assert_nil @relation.raw_sql_value
        assert_equal 'select * from foo', new_relation.raw_sql_value
      end
    end

    context "includes query method setting hash value" do
      should "split multi item hashes into multiple entries" do
        new_relation = @relation.includes(:foo => :bar, :baz => :perry).includes(:foo => :poo).includes(:foo)
        assert_equal({:foo => {:bar => {}, :poo => {}}, :baz => { :perry => {} }},
                     new_relation.includes_value)
      end
    end

    #-----------------------------------------
    # Query modifiers
    #-----------------------------------------
    context "modifiers" do
      setup do
        @mv1 = { :foo => 'bar' }
        @mv2 = { :biz => 'baz' }
        @mv3 = { :foo => 'boo' }
        @p1 = Proc.new { @mv3 }
      end

      should "delegate :modifiers to scoped" do
        assert @model.scoped.respond_to?(:modifiers)
        assert @model.respond_to?(:modifiers)
      end

      should "clone new relation and replace the modifiers value" do
        new_relation = @relation.modifiers(@mv1)
        assert_equal({}, @relation.modifiers_value)
        assert_equal @mv1, new_relation.modifiers_value
      end

      should "reset previous modifier values if it receives nil as an argument" do
        relation = @relation.modifiers(@mv1)
        assert_equal(@mv1, relation.modifiers_value)
        relation = relation.modifiers(nil)
        assert_equal({}, relation.modifiers_value)
      end

      should "be usable in a scope" do
        value = { :expires_at => true }
        @model.class_eval do
          scope :expire, modifiers(value)
        end
        assert_equal value, @model.expire.modifiers_value
      end

      should "always return a hash" do
        assert_equal({}, @relation.modifiers_value)
      end

      should "merge values from multiple calls into a single hash" do
        relation = @relation.modifiers(@mv1).modifiers(@mv2)
        assert_equal @mv1.merge(@mv2), relation.modifiers_value
      end

      should "merge hashes returned from calling Proc values" do
        relation = @relation.modifiers(@p1)
        assert_equal @mv3, relation.modifiers_value
      end

      should "raise an error if a value is neither a hash nor a proc" do
        relation = @relation.modifiers(:errk!)
        assert_raise TypeError do
          relation.modifiers_value
        end
      end

      should "raise an error if a value is a proc that does not return a hash" do
        relation = @relation.modifiers(Proc.new { :gah! })
        assert_raise TypeError do
          relation.modifiers_value
        end
      end

      should "merge values in the order they were given" do
        relation = @relation.modifiers(@p1).modifiers(@mv1).modifiers(@mv2)
        assert_equal @mv3.merge(@mv1).merge(@mv2), relation.modifiers_value
      end
    end

  end

end
