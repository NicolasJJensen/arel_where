require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe AW::Helpers do
  it "supports instance queries with the caller's state and inherited helpers" do
    base = Class.new do
      include AW::Helpers

      def initialize(pattern)
        @pattern = pattern
      end
    end
    child = Class.new(base) do
      def results
        User.where(first_name: lower.matches(@pattern))
      end
    end
    alice = User.create!(first_name: "Alice")
    User.create!(first_name: "Bob")

    expect(child.new("ali%").results).to eq([alice])
    expect(child.public_instance_methods).not_to include(:lower, :gt)
    expect(child.private_instance_methods).to include(:lower, :gt)
    expect(Object.new).not_to respond_to(:lower)
    expect(base).not_to respond_to(:lower)
  end

  it "supports inherited model class helpers and chainable query methods" do
    base = Class.new(User) do
      extend AW::Helpers
      self.abstract_class = true
    end
    child = Class.new(base) do
      def self.named(pattern)
        where(first_name: lower.matches(pattern))
      end

      def self.with_normalized_name(value)
        where(first_name: trim.lower.eq(value))
      end
    end
    alice = User.create!(first_name: "Alice")
    bob = User.create!(first_name: " Bob ")

    expect(child.named("ali%").pluck(:id)).to eq([alice.id])
    expect(child.with_normalized_name("bob").pluck(:id)).to eq([bob.id])
    expect(child.where(id: bob.id).named("ali%")).to be_empty
    expect(child.new).not_to respond_to(:lower)
  end

  it "uses normal include precedence and allows prepend for intentional overrides" do
    klass = Class.new do
      include AW::Helpers
      def lower = :application_method
    end
    expect(klass.new.lower).to eq(:application_method)

    overriding = Class.new do
      prepend AW::Helpers
      def lower = :application_method
    end
    expect(overriding.new.instance_exec { lower }).to be_a(AW::Chain)
    expect(Class.new(overriding) { def lower = :subclass_method }.new.lower).to eq(:subclass_method)
  end

  it "supports named functions and boolean combinations" do
    receiver = Object.new.extend(AW::Helpers)
    alice = User.create!(first_name: " Alice ")
    User.create!(first_name: "Bob")
    expression = receiver.instance_exec { function("TRIM").lower.eq("alice").and(not_eq(nil)) }
    expect(User.where(first_name: expression)).to eq([alice])
  end

  it "retains included helpers after an explicitly overriding build" do
    receiver = Object.new.extend(AW::Helpers)
    expect { receiver.instance_exec { AW.with_helpers { lower } } }.to raise_error(AW::HelperCollisionError)
    expression = receiver.instance_exec { AW.with_helpers(override: true) { lower } }
    expect(expression).to be_a(AW::Chain)
    expect(receiver.method(:lower).owner).to eq(AW::Helpers)
  end

  it "allows optional global inclusion without automatically including it on load" do
    script = <<~RUBY
      require "arel_where"
      raise "globally installed on load" if Object.ancestors.include?(AW::Helpers)
      Object.include(AW::Helpers)
      class GlobalHelperConsumer
        def expression
          lower.matches("ali%").and(not_eq(nil))
        end

        def self.expression
          lower.matches("ali%")
        end
      end
      raise "missing instance helpers" unless GlobalHelperConsumer.new.expression.is_a?(AW::Expr)
      raise "missing class helpers" unless GlobalHelperConsumer.expression.is_a?(AW::Chain)
      raise "existing method overridden" unless "abc".length == 3
      raise "helpers are public" if GlobalHelperConsumer.public_instance_methods.include?(:lower)
      raise "explicit AW broken" unless AW.eq("Alice").is_a?(AW::Chain)
      ActiveRecord::Base.establish_connection(ENV.fetch("TEST_DATABASE_URL", "postgresql:///postgres"))
      ActiveRecord::Base.connection.execute("CREATE TEMP TABLE global_helper_users (id bigserial PRIMARY KEY, name text)")
      class GlobalHelperUser < ActiveRecord::Base; end
      GlobalHelperUser.create!(name: "Alice")
      GlobalHelperUser.create!(name: "Bob")
      result = GlobalHelperUser.where(name: lower.matches("ali%")).pluck(:name)
      raise "global query failed" unless result == ["Alice"]
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", script)
    expect(status.success?).to be(true), output
    expect(Object.ancestors).not_to include(AW::Helpers)
  end
end
