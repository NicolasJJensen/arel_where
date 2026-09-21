require_relative 'spec_helper'

RSpec.describe 'AW loading' do
  it 'loads the refinement without activating bare predicates' do
    expect(defined?(ArelWhereRefine)).to eq('constant')
    expect(Object.new).not_to respond_to(:gteq)
    expect(User.where(first_name: AW.eq('Alice')).to_sql).to include('Alice')
  end
end
