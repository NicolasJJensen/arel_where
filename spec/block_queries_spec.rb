require_relative "spec_helper"

RSpec.describe "block query DSL" do
  it "preserves caller state and private methods when given a row parameter" do
    alice = create(:user, first_name: "Alice", active: true)
    create(:user, first_name: "Bob", active: true)
    search = Class.new do
      def initialize
        @pattern = "ali%"
      end

      def results
        User.where { |row| row.first_name.lower.matches(@pattern).and(row.active.eq(required_status)) }
      end

      private

      def required_status = true
    end.new

    expect(search.results).to contain_exactly(alice)
  end

  it "retains captured locals in zero-argument blocks and composes with AW.build" do
    alice = create(:user, first_name: "Alice")
    create(:user, first_name: "Bob")
    pattern = "ali%"
    expect(User.where { first_name.lower.matches(pattern) }).to contain_exactly(alice)
    receiver = Object.new
    result = receiver.instance_exec do
      AW.build { User.where(first_name: lower.matches(pattern)).order { first_name.lower.asc } }
    end
    expect(result).to eq([alice])
  end

  it "supports block where and where.not clauses" do
    alice = create(:user, first_name: "Alice", active: true)
    create(:user, first_name: "Bob", active: false)

    expect(User.where { first_name.matches("A%") }).to contain_exactly(alice)
    expect(User.where.not { first_name.eq("Bob") }).to contain_exactly(alice)
  end

  it "supports block order and preserves an explicitly passed row" do
    zed = create(:user, first_name: "Zed", last_name: "Aardvark")
    alice = create(:user, first_name: "alice", last_name: "Zephyr")

    expect(User.order { |row| row.last_name.asc }.to_a).to eq([zed, alice])
    expect(User.order { first_name.lower.asc }.to_a).to eq([alice, zed])
  end

  it "supports block select, group, having, pluck, and pick" do
    first_org = create(:organisation)
    second_org = create(:organisation)
    first = create(:user, organisation: first_org, first_name: "Alice")
    second = create(:user, organisation: first_org, first_name: "Bob")
    third = create(:user, organisation: second_org, first_name: "Carol")

    expect(User.select { id }.order(:id).map(&:id)).to eq([first.id, second.id, third.id])
    expect(User.group { organisation_id }.having { id.count.gt(1) }.pluck { organisation_id }).to eq([first_org.id])
    expect(User.order(:id).pluck { first_name }).to eq(%w[Alice Bob Carol])
    expect(User.where(first_name: "Alice").pick { first_name }).to eq("Alice")
  end

  it "keeps ordinary non-block calls unchanged" do
    alice = create(:user, first_name: "Alice")
    create(:user, first_name: "Bob")

    expect(User.where(first_name: "Alice").pluck(:id)).to eq([alice.id])
    expect(User.order(:id).limit(1).pick(:first_name)).to eq("Alice")
    expect(User.where.not(first_name: "Bob").select(:id).map(&:id)).to eq([alice.id])
    expect(User.where(id: alice.id).or(User.where(first_name: "Bob")).count).to eq(2)
    expect(User.group(:first_name).having(first_name: AW.eq("Alice")).pluck(:first_name)).to eq(["Alice"])
  end

  it "returns selected Arel expressions and supports arrays for value extraction" do
    alice = create(:user, first_name: "Alice")
    selected = User.all.load.select { first_name.lower.as("normalized_name") }
    expect(selected).to be_a(ActiveRecord::Relation)
    expect(selected.first.normalized_name).to eq("alice")
    expect(User.pluck { [id, first_name.lower] }).to eq([[alice.id, "alice"]])
    expect(User.pick { [id, first_name.lower] }).to eq([alice.id, "alice"])
  end

  it "rejects mixed arguments and blocks without discarding the arguments" do
    %i[select where order having pluck pick group or].each do |method|
      expect { User.public_send(method, :id) { id } }.to raise_error(ArgumentError, /not both/)
      expect { User.public_send(method, id: 1) { id } }.to raise_error(ArgumentError, /not both/)
    end
    expect { User.where.not(id: 1) { id.eq(2) } }.to raise_error(ArgumentError, /not both/)
  end

  it "fails at unknown column names and invalid column calls" do
    expect { User.where { frist_name.eq("Alice") } }.to raise_error(NameError)
    expect { User.where { first_name("Alice") } }.to raise_error(NoMethodError)
  end

  it "combines same-column AW predicates and groups cross-column boolean logic" do
    alice = create(:user, first_name: "Alice", active: false)
    bob = create(:user, first_name: "Bob", active: true)
    create(:user, first_name: "Carol", active: false)

    same_column = User.where(first_name: AW.eq("Alice").or("Bob"))
    expect(same_column.where { active.eq(true) }).to contain_exactly(bob)

    grouped = User.where { first_name.eq("Alice").or(active.eq(true)) }.where { active.eq(false) }
    expect(grouped).to contain_exactly(alice)
  end

  it "supports relation or with a block and preserves incoming scopes" do
    alice = create(:user, first_name: "Alice", active: false)
    bob = create(:user, first_name: "Bob", active: true)
    carol = create(:user, first_name: "Carol", active: true)

    relation = User.where(active: true).or { first_name.eq("Alice") }
    expect(relation).to contain_exactly(alice, bob, carol)

    scoped = User.where(active: true).where { first_name.matches("B%") }
    expect(scoped).to contain_exactly(bob)
  end

  it "extracts constraints from a returned relation for an explicit join" do
    matching_org = create(:organisation)
    other_org = create(:organisation)
    matching_user = create(:user, organisation: matching_org, first_name: "Alice")
    create(:user, organisation: other_org, first_name: "Bob")

    relation = User.joins(:organisation).where { Organisation.where(id: matching_org.id) }

    expect(relation).to contain_exactly(matching_user)
    compared = User.joins(:organisation).where do |user|
      Organisation.where { |organisation| organisation.id.eq(user.organisation_id).and(organisation.id.eq(matching_org.id)) }
    end
    expect(compared).to contain_exactly(matching_user)
  end
end
