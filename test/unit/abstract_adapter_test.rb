require "#{File.dirname(__FILE__)}/../test_helper"

class Perry::AbstractAdapterTest < Test::Unit::TestCase

  context "AbstractAdapter class" do

    setup do
      @abstract = Perry::Adapters::AbstractAdapter
    end

    context "initialize method" do

      should "take two parameters" do
        assert_equal 2, @abstract.instance_method('initialize').arity
      end

      should "set the first to @type and the second to @configuration_contexts" do
        adapter = @abstract.new(:foo, ['foo'])
        assert_equal :foo, adapter.send(:instance_variable_get, :@type)
        assert_equal ['foo'], adapter.send(:instance_variable_get, :@configuration_contexts)
      end

      should "ensure @configuration_contexts is an array" do
        adapter = @abstract.new(:foo, 'bar')
        assert_equal ['bar'], adapter.send(:instance_variable_get, :@configuration_contexts)
      end

      should "set @type to a symbol" do
        adapter = @abstract.new('foo', 'bar')
        assert_equal :foo, adapter.send(:instance_variable_get, :@type)
      end

    end

    context "register_as class method" do
      should "register the calling class in @@registered_adapters" do
        class Foo < @abstract
          register_as 'foo'
        end
        class_var = @abstract.send(:class_variable_get, :@@registered_adapters)
        assert_equal Foo, class_var[:foo]
        class_var.delete(:foo)
      end
    end

    context "create class method" do
      setup do
        class Foo < @abstract
          register_as :foo
        end
        @foo = Foo
      end

      teardown do
        @abstract.send(:class_variable_get, :@@registered_adapters).delete(:foo)
      end

      should "use the specified type's class" do
        assert_equal @foo, @abstract.create(:foo, {}).class
      end

      should "pass configuration to init method" do
        adapter = @abstract.create(:foo, { :bar => :baz })
        assert_equal :baz, adapter.config[:bar]
      end
    end

    context "call instance method" do

      should "take two arguments" do
        assert_equal 2, @abstract.instance_method('call').arity
      end

      should "set the mode option before calling the stack" do
        class ModeAdapter < Class.new(@abstract)
          [:read, :write, :delete].each do |mode|
            define_method(mode) do |options|
              [{ :mode => options[:mode] }]
            end
          end
          def stack_items
            []
          end
        end

        adapter = ModeAdapter.new(:mode_adapter, {})
        [:read, :write, :delete].each do |mode|
          assert_equal mode, adapter.call(mode, {}).first[:mode]
        end
      end

      should "create base option :noop if set as a true modifier" do
        Perry::Test::FakeAdapterStackItem.reset
        cls = Class.new(Perry::Test::Base)
        class Foo < @abstract
          register_as :foo

          def read(options)
            Perry::Test::FakeAdapterStackItem.log << ["read", options]
            [ { :id => 1 } ]
          end
        end
        adapter = Foo.new(:foo, {})
        assert_equal nil, adapter.call(:read, :relation => cls.scoped.modifiers(:noop => true))
        assert Perry::Test::FakeAdapterStackItem.log.empty?
      end

      should "call stack items in order: processors, model bridge, middlewares" do
        Perry::Test::FakeAdapterStackItem.reset
        class MiddlewareA < Perry::Test::FakeAdapterStackItem; end
        class MiddlewareB < Perry::Test::FakeAdapterStackItem; end
        class ProcessorA < Perry::Test::FakeAdapterStackItem; end
        class ProcessorB < Perry::Test::FakeAdapterStackItem; end

        class Foo < @abstract
          register_as :foo

          def read(options)
            Perry::Test::FakeAdapterStackItem.log << ["read", options]
            [ { :id => 1 } ]
          end
        end

        config = proc do |config|
          config.add_middleware(MiddlewareA, :foo => 'A')
          config.add_processor(ProcessorA, :bar => 'A')
        end

        config2 = proc do |config|
          config.add_middleware(MiddlewareB, :foo => 'B')
          config.add_processor(ProcessorB, :bar => 'B')
        end

        adapter = Foo.new(:foo, config)
        adapter = adapter.extend_adapter(config2)

        relation = Perry::Test::Blog::Site.scoped
        adapter.call('read', { :relation => relation })

        correct = [
          [ "ProcessorA", { :bar => 'A' }, { :relation => relation, :mode => :read } ],
          [ "ProcessorB", { :bar => 'B' }, { :relation => relation, :mode => :read } ],
          [ "MiddlewareA", { :foo => 'A' }, { :relation => relation, :mode => :read  } ],
          [ "MiddlewareB", { :foo => 'B' }, { :relation => relation, :mode => :read } ],
          [ "read", { :relation => relation, :mode => :read } ],
          [ Hash ],
          [ Hash ],
          [ Perry::Test::Blog::Site ],
          [ Perry::Test::Blog::Site ],
        ]

        assert_equal(correct, Perry::Test::FakeAdapterStackItem.log)

        adapter.call('read', { :relation => relation })

        assert_equal(correct + correct, Perry::Test::FakeAdapterStackItem.log)
      end

    end

    context "execute method" do
      setup do
        class Test < @abstract
          attr_reader :last_called
          register_as :execute_method_test
          def read(options)
            @last_called = :read
          end
          def write(options)
            @last_called = :write
          end
          def delete(options)
            @last_called = :delete
          end
        end
        @test = @abstract.create(:execute_method_test, {})
      end

      should "pass all options on to options[:mode] method" do
        [:read, :write, :delete].each do |mode|
          @test.execute(:option => :foo, :mode => mode)
          assert_equal mode, @test.last_called
        end
      end

      should "not call options[:mode] method if options[:noop] true" do
        [:read, :write, :delete].each do |mode|
          val = @test.execute(:noop => true, :mode => mode)
          assert_equal nil, @test.last_called
          assert_equal nil, val
        end
      end

    end

    context "configuration in hash or AdapterConfig" do
      setup do
        class Foo < @abstract
          register_as :foo
        end
        @foo = Foo
      end

      should "merge from instances chained with extend_adapter" do
        adapter = @abstract.create(:foo, :foo => 'bar')
        assert_equal 'bar', adapter.config[:foo]

        adapter = adapter.extend_adapter(:foo => 'baz')
        assert_equal 'baz', adapter.config[:foo]

        adapter = adapter.extend_adapter(proc { |conf| conf.foo = 'poo' })
        assert_equal 'poo', adapter.config[:foo]
      end

      should "append middlewares added on each adapter extension" do
        adapter = @abstract.create(:foo, {})

        adapter = adapter.extend_adapter(proc { |conf| conf.add_middleware('foo') })
        assert_equal [['foo', {}]], adapter.config[:middlewares]

        adapter = adapter.extend_adapter(proc { |conf| conf.add_middleware('bar', :baz => :poo) })
        assert_equal [['foo', {}], ['bar', {:baz => :poo}]], adapter.config[:middlewares]

        adapter = adapter.extend_adapter(proc { |conf| conf.add_middleware('baz') })
        assert_equal [['foo', {}], ['bar', {:baz => :poo}], ['baz', {}]],
            adapter.config[:middlewares]
      end
    end

  end

  context "AdapterConfig class" do
    setup do
      @config = Perry::Adapters::AbstractAdapter::AdapterConfig
    end

    should "have functionality of OpenStruct" do
      assert @config.ancestors.include?(OpenStruct)
    end

    context "add_middleware instance method" do

      should "take 2 parameters with the second optional" do
        assert_equal -2, @config.instance_method(:add_middleware).arity
      end

      should "push value on array in :middlwares value on marshal" do
        conf = @config.new
        conf.add_middleware('Value')
        assert_equal({ :middlewares => [['Value', {}]] }, conf.marshal_dump)
      end

    end

    context "add_processor instance method" do
      should "take 2 parameters with the second being optional" do
        method = @config.instance_method(:add_processor)
        assert method
        assert_equal -2, method.arity
      end

      should "push value on array in :processors value on marshal" do
        config = @config.new
        config.add_processor('Poop', :foo => :bar)
        assert_equal({ :processors => [['Poop', { :foo => :bar }]] }, config.to_hash)
      end
    end

    context "to_hash instance method" do

      should "return the marshal dump" do
        conf = @config.new(:foo => :bar)
        assert_equal({ :foo => :bar }, conf.to_hash)
      end

    end

  end

end

