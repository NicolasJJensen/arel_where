require "spec_helper"

RSpec.describe AW::DSL do
  it "enables private instance and class helpers in newly defined subclass methods" do
    base = Class.new(User) do
      self.abstract_class = true
      include AW::DSL
    end
    child = Class.new(base) do
      def self.matching_name(pattern)
        where(first_name: lower.matches(pattern))
      end

      def namesakes
        self.class.where(first_name: lower.eq(first_name.downcase))
      end
    end
    alice = User.create!(first_name: "Alice")
    bob = User.create!(first_name: "Bob")

    expect(child.matching_name("ali%").pluck(:id)).to eq([alice.id])
    expect(child.find(alice.id).namesakes.pluck(:id)).to eq([alice.id])
    expect(child.where(id: bob.id).matching_name("ali%")).to be_empty
    expect(child.private_instance_methods).to include(:lower, :gt)
    expect(child.singleton_class.private_method_defined?(:lower)).to be(true)
    expect(child).not_to respond_to(:lower)
    expect(child.new).not_to respond_to(:lower)
    expect(User.respond_to?(:lower, true)).to be(false)
    expect(Object.new.respond_to?(:lower, true)).to be(false)
  end

  it "preserves application method precedence on both receivers" do
    klass = Class.new do
      include AW::DSL

      def lower = :instance_method
      def self.lower = :class_method
    end

    expect(klass.new.lower).to eq(:instance_method)
    expect(klass.lower).to eq(:class_method)
  end
end
