require_relative 'spec_helper'

RSpec.describe 'Arel where integration' do
  let(:users_table) { User.arel_table }
  let(:org) { create(:organisation) }

  describe 'Chain and boolean combinators over the same attribute' do
    it 'filters with gt AND lt on a date column' do
      u1 = create(:user, organisation: org, first_name: 'Old',  date_of_birth: Date.new(1990, 1, 1))
      u2 = create(:user, organisation: org, first_name: 'Mid',  date_of_birth: Date.new(2000, 1, 1))
      u3 = create(:user, organisation: org, first_name: 'Young', date_of_birth: Date.new(2010, 1, 1))

      rel = User.where(organisation: org)
                .where(date_of_birth: AW.gt(Date.new(1995, 1, 1)).and(AW.lt(Date.new(2005, 1, 1))))

      expect(rel).to contain_exactly(u2)
    end

    it 'supports direct chained predicate without combinators' do
      a = create(:user, organisation: org, first_name: 'Alice')
      create(:user, organisation: org, first_name: 'Bob')

      rel = User.where(organisation: org).where(first_name: AW.matches('%li%'))
      expect(rel).to contain_exactly(a)
    end

    it 'accepts Proc on one side of a combinator' do
      mid = create(:user, organisation: org, first_name: 'Mid', date_of_birth: Date.new(2000, 1, 1))
      create(:user, organisation: org, first_name: 'Low', date_of_birth: Date.new(1990, 1, 1))
      create(:user, organisation: org, first_name: 'High', date_of_birth: Date.new(2010, 1, 1))

      rel = User.where(organisation: org).where(
        date_of_birth: AW.gt(Date.new(1995, 1, 1)).and(->(a) { a.lt(Date.new(2005, 1, 1)) })
      )

      expect(rel).to contain_exactly(mid)
    end
  end

  describe 'Implicit eq fallback in combinators' do
    it 'treats plain value as eq(value) on right side of OR' do
      a = create(:user, organisation: org, first_name: 'Alice')
      b = create(:user, organisation: org, first_name: 'Bob')
      create(:user, organisation: org, first_name: 'Carol')

      rel = User.where(organisation: org).where(first_name: AW.eq('Alice').or('Bob'))
      expect(rel).to contain_exactly(a, b)
    end

    it 'handles strings with quotes safely' do
      oneil = create(:user, organisation: org, first_name: "O'Neil")
      rel = User.where(organisation: org).where(first_name: AW.eq("O'Neil"))
      expect(rel).to contain_exactly(oneil)
    end
  end

  describe 'Proc handler' do
    it 'applies a Proc to the Arel attribute' do
      e1 = create(:email, address: 'foo@example.com')
      create(:email, address: 'bar@other.com')

      rel = Email.where(address: ->(a) { a.matches('%@example.com') })
      expect(rel).to contain_exactly(e1)
    end

    it 'supports function chaining via Arel function + matches (LOWER + LIKE)' do
      a = create(:user, organisation: org, first_name: 'Alice')
      create(:user, organisation: org, first_name: 'BOB')

      rel = User.where(
        first_name: ->(attr) {
          lower = Arel::Nodes::NamedFunction.new('LOWER', [attr])
          Arel::Nodes::Matches.new(lower, Arel::Nodes.build_quoted('%ali%'))
        }
      ).where(organisation: org)

      expect(rel).to contain_exactly(a)
    end
  end

  describe 'Refinement usage' do
    using ArelWhereRefine

    it 'allows bare predication methods via using ArelWhereRefine' do
      a = create(:user, organisation: org, first_name: 'Alice')
      create(:user, organisation: org, first_name: 'Bob')

      # Use a predication that does not clash with RSpec's `eq` matcher
      rel = User.where(organisation: org).where(first_name: matches('Ali%'))
      expect(rel).to contain_exactly(a)
    end
  end

  describe 'Cross-column OR (discouraged but supported)' do
    it 'combines with a raw Arel node referencing a different column' do
      a = create(:user, organisation: org, first_name: 'Alice', active: false)
      b = create(:user, organisation: org, first_name: 'Zed',   active: true)

      risky = users_table[:active].eq(true)
      rel = User.where(organisation: org)
                .where(first_name: AW.eq('Alice').or(risky))

      # Behavior: both rows match because of (first_name = 'Alice' OR active = true)
      expect(rel).to contain_exactly(a, b)

      # Sanity-check SQL includes both columns and an OR
      sql = rel.to_sql
      expect(sql).to include('"users"."first_name"')
      expect(sql).to include('"users"."active"')
      expect(sql).to match(/\sOR\s/)
    end
  end

  describe 'NULL handling and BETWEEN' do
    it 'handles eq(nil) and not_eq(nil)' do
      nil_last = create(:user, organisation: org, first_name: 'Nil',  last_name: nil)
      has_last = create(:user, organisation: org, first_name: 'Has',  last_name: 'Smith')

      only_nil = User.where(organisation: org).where(last_name: AW.eq(nil))
      expect(only_nil).to contain_exactly(nil_last)

      not_nil = User.where(organisation: org).where(last_name: AW.not_eq(nil))
      expect(not_nil).to include(has_last)
      expect(not_nil).not_to include(nil_last)
    end

    # Note: `between` expects a Range; array bounds are covered in the arel_pg_ranges tests.
  end

  describe 'Grouping semantics' do
    it 'keeps parentheses when combining same-column OR with another where' do
      a = create(:user, organisation: org, first_name: 'Alice', active: false)
      b = create(:user, organisation: org, first_name: 'Bob',   active: true)
      c = create(:user, organisation: org, first_name: 'Carol', active: false)

      rel = User.where(organisation: org)
                .where(first_name: AW.eq('Alice').or('Bob'))
                .where(active: false)

      expect(rel).to contain_exactly(a)
      sql = rel.to_sql
      expect(sql).to match(/\(.*first_name.*=\s.*\sOR\s.*first_name.*=.*\)/)
    end

    it 'supports cross-column AND (discouraged pattern) with NodeExpr' do
      a = create(:user, organisation: org, first_name: 'Alice', active: true)
      _b = create(:user, organisation: org, first_name: 'Bob',   active: true)
      _c = create(:user, organisation: org, first_name: 'Carol', active: false)

      rel = User.where(organisation: org)
                .where(first_name: AW.eq('Alice').and(users_table[:active].eq(true)))

      expect(rel).to contain_exactly(a)
    end
  end
end
