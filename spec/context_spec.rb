require "spec_helper"

class HelperQuery
  def initialize(pattern = "ali%")
    @pattern = pattern
  end

  def query
    AW.with_helpers do
      User.where(first_name: lower.matches(@pattern), id: gt(minimum_id).and(lt(100_000)))
    end
  end

  def expression
    AW.with_helpers { lower.eq(@pattern) }
  end

  private

  def minimum_id = 0
end

RSpec.describe "Helper blocks" do
  def on(receiver, &block)
    receiver.instance_exec(&block)
  end

  it "preserves the caller's instance variables and private methods and returns a lazy relation" do
    alice = User.create!(first_name: "Alice")
    User.create!(first_name: "Bob")
    receiver = HelperQuery.new
    query = receiver.query

    expect(receiver).not_to respond_to(:lower)
    expect(query).to be_a(ActiveRecord::Relation)
    expect(query.to_a).to eq([alice])
  end

  it "returns an expression that remains usable after the helpers are removed" do
    expression = HelperQuery.new("alice").expression
    alice = User.create!(first_name: "Alice")
    expect(User.where(first_name: expression)).to eq([alice])
  end

  it "rejects all existing helper names before executing the block or installing helpers" do
    receiver = Object.new
    receiver.define_singleton_method(:lower) { :original }
    receiver.define_singleton_method(:upper) { :private_original }
    receiver.singleton_class.__send__(:private, :upper)
    ran = false

    expect { on(receiver) { AW.with_helpers { ran = true } } }
      .to raise_error(AW::HelperCollisionError, /lower, upper/)
    expect(ran).to be(false)
    expect(receiver.lower).to eq(:original)
    expect(receiver).not_to respond_to(:gt)
  end

  it "rejects inherited public, protected and private methods" do
    %i[public protected private].each do |visibility|
      klass = Class.new do
        define_method(:lower) { :original }
        __send__(visibility, :lower)
      end
      expect { on(klass.new) { AW.with_helpers { lower } } }
        .to raise_error(AW::HelperCollisionError, /lower/)
    end
  end

  it "recognizes methods advertised through respond_to_missing?" do
    receiver = Class.new do
      def respond_to_missing?(name, include_private = false)
        name == :lower || super
      end
    end.new
    expect { on(receiver) { AW.with_helpers { lower } } }
      .to raise_error(AW::HelperCollisionError, /lower/)
  end

  it "overrides and restores singleton methods and their exact visibility" do
    %i[public protected private].each do |visibility|
      receiver = Object.new
      receiver.define_singleton_method(:lower) { |value| [:original, value] }
      receiver.singleton_class.__send__(visibility, :lower)
      original = receiver.singleton_class.instance_method(:lower)

      result = on(receiver) { AW.with_helpers(override: true) { lower } }

      expect(result).to be_a(AW::Chain)
      expect(receiver.__send__(:lower, 42)).to eq([:original, 42])
      expect(receiver.singleton_class.instance_method(:lower)).to eq(original)
      expect(receiver.singleton_class.public_send("#{visibility}_instance_methods", false)).to include(:lower)
    end
  end

  it "removes overrides of inherited methods rather than copying them onto the singleton class" do
    klass = Class.new do
      private
      def lower = :original
    end
    receiver = klass.new
    on(receiver) { AW.with_helpers(override: true) { lower } }
    klass.define_method(:lower) { :updated }

    expect(receiver.__send__(:lower)).to eq(:updated)
    expect(receiver.singleton_class.instance_methods(false)).not_to include(:lower)
  end

  it "restores helpers after exceptions" do
    receiver = Object.new
    receiver.define_singleton_method(:lower) { :original }
    expect { on(receiver) { AW.with_helpers(override: true) { raise "query failed" } } }
      .to raise_error("query failed")
    expect(receiver.lower).to eq(:original)
    expect(receiver).not_to respond_to(:gt)
    expect(on(receiver) { AW.with_helpers(override: true) { gt(1) } }).to be_a(AW::Chain)
  end

  it "restores helpers after a nonlocal exit" do
    receiver = Object.new
    result = catch(:done) { on(receiver) { AW.with_helpers { throw :done, :result } } }
    expect(result).to eq(:result)
    expect(receiver).not_to respond_to(:lower)
  end

  it "removes partially installed helpers when a singleton method hook raises" do
    receiver = Object.new
    receiver.define_singleton_method(:singleton_method_added) do |name|
      raise "installation failed" if name == :function
    end

    expect { on(receiver) { AW.with_helpers { lower } } }.to raise_error("installation failed")
    expect(receiver.singleton_methods).to eq([:singleton_method_added])
    receiver.singleton_class.remove_method(:singleton_method_added)
    expect(on(receiver) { AW.with_helpers { lower } }).to be_a(AW::Chain)
  end

  it "allows nested builds to reuse installed helpers and restores the outer override" do
    receiver = Object.new
    receiver.define_singleton_method(:lower) { :original }
    result = on(receiver) do
      AW.with_helpers(override: true) do
        inner = AW.with_helpers { lower.eq("alice") }
        [inner, lower.eq("bob")]
      end
    end
    expect(result).to all(be_a(AW::Chain))
    expect(receiver.lower).to eq(:original)
  end

  it "keeps outer helpers installed when a nested build raises" do
    receiver = Object.new
    result = on(receiver) do
      AW.with_helpers do
        begin
          AW.with_helpers { raise "inner failed" }
        rescue RuntimeError
          lower
        end
      end
    end
    expect(result).to be_a(AW::Chain)
    expect(receiver).not_to respond_to(:lower)
  end

  it "makes helpers visible to methods called on the same receiver during the block" do
    receiver = Class.new do
      def expression = lower.eq("alice")
    end.new
    expect(on(receiver) { AW.with_helpers { expression } }).to be_a(AW::Chain)
    expect { receiver.expression }.to raise_error(NameError)
    expect(Object.new).not_to respond_to(:lower)
  end

  it "rejects frozen receivers before running the block" do
    ran = false
    expect { on(Object.new.freeze) { AW.with_helpers { ran = true } } }.to raise_error(FrozenError)
    expect(ran).to be(false)
  end

  it "rejects a frozen singleton class before attempting installation" do
    receiver = Object.new
    receiver.singleton_class.freeze
    expect { on(receiver) { AW.with_helpers { lower } } }.to raise_error(FrozenError, /singleton class/)
    expect(receiver).not_to respond_to(:lower)
  end

  it "rejects helpers in prepended modules even when overriding is requested" do
    receiver = Object.new
    receiver.singleton_class.prepend(Module.new { def lower = :prepended })
    expect { on(receiver) { AW.with_helpers(override: true) { lower } } }
      .to raise_error(AW::HelperCollisionError, /prepended/)
    expect(receiver.lower).to eq(:prepended)
    expect(receiver).not_to respond_to(:gt)
  end

  it "preserves explicitly undefined inherited methods" do
    receiver = Class.new { def lower = :inherited }.new
    receiver.singleton_class.undef_method(:lower)
    expect(on(receiver) { AW.with_helpers { lower } }).to be_a(AW::Chain)
    expect { receiver.lower }.to raise_error(NoMethodError)
  end

  it "rejects overlapping builds from another fiber without removing the active helpers" do
    receiver = Object.new
    fiber = Fiber.new do
      on(receiver) { AW.with_helpers { Fiber.yield; lower } }
    end
    fiber.resume
    expect { on(receiver) { AW.with_helpers { lower } } }.to raise_error(AW::ContextInUseError)
    expect(fiber.resume).to be_a(AW::Chain)
    expect(receiver).not_to respond_to(:lower)
  end

  it "rejects overlapping builds from another thread and permits other receivers" do
    receiver = Object.new
    ready = Queue.new
    finish = Queue.new
    thread = Thread.new do
      on(receiver) { AW.with_helpers { ready << true; finish.pop; lower } }
    end
    ready.pop
    expect { on(receiver) { AW.with_helpers { lower } } }.to raise_error(AW::ContextInUseError)
    expect(on(Object.new) { AW.with_helpers { lower } }).to be_a(AW::Chain)
    finish << true
    expect(thread.value).to be_a(AW::Chain)
    expect(receiver).not_to respond_to(:lower)
  ensure
    finish << true if finish
    thread&.join
  end

  it "supports every advertised helper in a separate context without mutating the caller" do
    receiver = Object.new.freeze
    result = on(receiver) do
      AW.build { [lower, gt(18).and(lt(65)), function("TRIM").eq("alice")] }
    end
    expect(result).to all(be_a(AW::Expr))
    expect(receiver).not_to respond_to(:lower)
    AW::KNOWN_METHODS.each do |name|
      expect(AW.build { __send__(name, *(name == :function ? ["TRIM"] : [])) }).to be_a(AW::Chain)
    end
  end

  it "preserves captured locals and lexical constants inside a separate context" do
    pattern = "ali%"
    alice = User.create!(first_name: "Alice")
    result = AW.build { User.where(first_name: lower.matches(pattern)) }
    expect(result).to eq([alice])
  end

  it "preserves caller state and private methods when build takes a parameter" do
    receiver = Class.new do
      def initialize
        @pattern = "ali%"
      end

      def results
        AW.build do |aw|
          User.where(first_name: aw.lower.matches(@pattern), id: aw.gt(minimum_id))
              .order { first_name.lower.asc }
        end
      end

      private

      def minimum_id = 0
    end.new.freeze
    alice = User.create!(first_name: "Alice")
    User.create!(first_name: "Bob")

    expect(receiver.results).to eq([alice])
    expect(receiver.respond_to?(:lower, true)).to be(false)
  end

  it "keeps application methods intact in either build form" do
    receiver = Object.new
    receiver.define_singleton_method(:lower) { :original }
    receiver.freeze

    bare = on(receiver) { AW.build { lower.eq("alice") } }
    explicit = on(receiver) { AW.build { |aw| [lower, aw.lower.eq("alice")] } }

    expect(bare).to be_a(AW::Chain)
    expect(explicit.first).to eq(:original)
    expect(explicit.last).to be_a(AW::Chain)
    expect(receiver.lower).to eq(:original)
  end

  it "supports public function and predicate helpers through the build parameter" do
    expression = AW.build do |aw|
      aw.function("TRIM").lower.eq("alice").and(aw.not_eq(nil))
    end
    alice = User.create!(first_name: " Alice ")
    expect(User.where(first_name: expression)).to eq([alice])
    expect(Object.new.extend(AW::Helpers)).not_to respond_to(:lower)
  end

  it "supports an explicit lambda parameter and returns the block result" do
    result = AW.build(&->(aw) { aw.gt(18).and(aw.lt(65)) })
    expect(result).to be_a(AW::Junction)
    expect(AW.build { :result }).to eq(:result)
    expect(AW.build { |_aw| :result }).to eq(:result)
  end

  it "removes the old context entry point and rejects override options on build" do
    expect(AW.singleton_methods(false)).not_to include(:context)
    expect { AW.build(override: true) { lower } }.to raise_error(ArgumentError)
  end

  it "does not expose the caller's methods or instance variables in a separate context" do
    receiver = HelperQuery.new
    expect(on(receiver) { AW.build { @pattern } }).to be_nil
    expect { on(receiver) { AW.build { minimum_id } } }.to raise_error(NameError)
  end

  it "raises for unknown helpers in both modes" do
    expect { on(Object.new) { AW.with_helpers { lowre } } }.to raise_error(NameError)
    expect { AW.build { lowre } }.to raise_error(NameError)
  end

  it "requires a block for both entry points" do
    expect { AW.with_helpers }.to raise_error(ArgumentError, /requires a block/)
    expect { AW.build }.to raise_error(ArgumentError, /requires a block/)
  end
end
