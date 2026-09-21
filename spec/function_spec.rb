require "spec_helper"

module BareFunctionQueries
  using ArelWhereRefine

  def self.match
    User.where(first_name: function("TRIM").lower.eq("alice").or(upper.eq("BOB")))
  end
end

RSpec.describe "Named functions" do
  it "composes functions and complete predicates using bare syntax" do
    alice = User.create!(first_name: " Alice ")
    bob = User.create!(first_name: "Bob")
    User.create!(first_name: "Charlie")
    expect(BareFunctionQueries.match.order(:id)).to eq([alice, bob])
  end

  it "uses the column as the first argument and quotes additional literals" do
    absent = User.create!(first_name: nil)
    User.create!(first_name: "Alice")
    expect(User.where(first_name: AW.function("COALESCE", "O'Neil").eq("O'Neil"))).to eq([absent])
  end

  it "supports predicates on function results" do
    alice = User.create!(first_name: "Alice")
    User.create!(first_name: "Bob")
    expect(User.where(first_name: AW.function("LENGTH").gt(3))).to eq([alice])
  end

  it "allows another expression as a function argument" do
    alice = User.create!(first_name: "Alice")
    expect(User.where(first_name: AW.function("CONCAT", AW.upper).eq("AliceALICE"))).to eq([alice])
  end

  it "rejects SQL fragments as function names" do
    expect { AW.function("LOWER); SELECT 1 --") }.to raise_error(ArgumentError, /SQL identifier/)
  end

  it "does not install bare functions globally" do
    expect(Object.new.respond_to?(:function)).to be false
    expect(Object.new.respond_to?(:lower)).to be false
  end
end

module DefaultFunctionQueries
  using ArelWhereRefine

  def self.match
    User.where(first_name: trim.lower.eq("alice").and(length.gt(3)))
  end
end

RSpec.describe "Default function helpers" do
  it "retains function chains with refined helpers" do
    alice = User.create!(first_name: " Alice ")
    expect(DefaultFunctionQueries.match).to eq([alice])
  end

  it "provides the same function helpers on AW and chains" do
    column = User.arel_table[:first_name]
    AW::FUNCTIONS.each do |name|
      expect(AW.public_send(name).apply_to(column).name).to eq(name.to_s.upcase)
      expect(AW.trim.public_send(name).apply_to(column).expressions.first.name).to eq("TRIM")
    end
  end

  it "passes arguments to common helpers" do
    mary = User.create!(first_name: "Mary-Jane")
    expect(User.where(first_name: AW.replace("-", " ").eq("Mary Jane"))).to eq([mary])
  end

  it "allows application helpers to return composable expressions" do
    AW.define_singleton_method(:normalized_test_name) { trim.lower }
    alice = User.create!(first_name: " Alice ")
    expect(User.where(first_name: AW.normalized_test_name.eq("alice"))).to eq([alice])
  ensure
    AW.singleton_class.remove_method(:normalized_test_name)
  end
end
