require_relative 'spec_helper'

RSpec.describe 'refinement inheritance' do
  class RefinementInheritanceBase
    using ArelWhereRefine

    def inherited_predicate
      matches('inherited')
    end

    def defined_under_refinement
      gt(18)
    end
  end

  class RefinementInheritanceChild < RefinementInheritanceBase
    def newly_defined_predicate
      matches('subclass')
    end

    def matches(value)
      [:child_matches, value]
    end
  end

  class RefinementInheritancePlainChild < RefinementInheritanceBase
  end

  class RefinementInheritanceUnrefinedChild < RefinementInheritanceBase
    def newly_defined_predicate
      matches('subclass')
    end
  end

  class RefinementInheritanceOptedInChild < RefinementInheritanceBase
    using ArelWhereRefine

    def newly_defined_predicate
      gt(18)
    end
  end

  class RefinementInheritanceReopened
    using ArelWhereRefine

    def defined_in_original_scope
      lt(65)
    end
  end

  class RefinementInheritanceReopened
    def defined_in_reopened_scope
      lt(65)
    end
  end

  it 'keeps a refinement on an inherited method defined under using' do
    expect(RefinementInheritancePlainChild.new.inherited_predicate).to be_a(AW::Chain)
  end

  it 'does not activate the refinement for a newly defined subclass method' do
    expect { RefinementInheritanceUnrefinedChild.new.newly_defined_predicate }
      .to raise_error(NoMethodError, /matches/)
  end

  it 'allows a subclass to activate the refinement for its own methods' do
    expect(RefinementInheritanceOptedInChild.new.newly_defined_predicate).to be_a(AW::Chain)
  end

  it 'lets a subclass method win over the refined Object method' do
    expect(RefinementInheritanceChild.new.inherited_predicate)
      .to eq([:child_matches, 'inherited'])
  end

  it 'does not carry using into a reopened class scope' do
    expect(RefinementInheritanceReopened.new.defined_in_original_scope).to be_a(AW::Chain)
    expect { RefinementInheritanceReopened.new.defined_in_reopened_scope }
      .to raise_error(NoMethodError, /lt/)
  end
end
