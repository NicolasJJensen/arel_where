require_relative 'spec_helper'

RSpec.describe 'Chain method names' do
  it 'builds a chain for a known predication on AW and on an existing chain' do
    expect(AW.matches('Ali%')).to be_a(AW::Chain)
    expect(AW.matches('Ali%').gt(1)).to be_a(AW::Chain)
    expect(AW.matches('Ali%').lower).to be_a(AW::Chain)
  end

  it 'raises NoMethodError at the call site for an unknown name on AW' do
    expect { AW.mathces('Ali%') }.to raise_error(NoMethodError, /mathces/)
  end

  it 'raises NoMethodError at the call site for an unknown name on a chain' do
    expect { AW.eq('Alice').mathces('Ali%') }.to raise_error(NoMethodError, /mathces/)
  end

  it 'reports respond_to? honestly' do
    expect(AW).to respond_to(:matches)
    expect(AW).not_to respond_to(:mathces)
    expect(AW.eq('Alice')).to respond_to(:matches)
    expect(AW.eq('Alice')).not_to respond_to(:mathces)
  end

  it 'keeps the Active Record id probe a no-op' do
    chain = AW.eq('Alice')
    expect(chain.id).to be(chain)
  end

  it 'still accepts every name the refinement exposes' do
    column = User.arel_table[:first_name]
    expect(AW::KNOWN_METHODS).to include(:eq, :matches, :overlaps, :function, *AW::FUNCTIONS)
    expect(AW.eq('Alice').apply_to(column)).to be_a(Arel::Nodes::Equality)
  end
end
